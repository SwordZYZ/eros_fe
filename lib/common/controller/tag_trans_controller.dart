import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/const/const.dart';
import 'package:eros_fe/extension.dart';
import 'package:eros_fe/models/gallery_tag.dart';
import 'package:eros_fe/network/tag_dictionary_release.dart';
import 'package:eros_fe/store/db/entity/tag_translat.dart';
import 'package:eros_fe/utils/logger.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as path;

import '../global.dart';

const _cdnUrl =
    'https://fastly.jsdelivr.net/gh/EhTagTranslation/Database@release/db.raw.json.gz';

class TagTransController extends GetxController {
  TagTransController({
    Future<Map> Function(String) fetchRelease = fetchTagDictionaryReleaseApi,
    Future<String> Function(Uri) fetchReleasePage =
        fetchTagDictionaryReleasePage,
    TagDictionaryAssetDownloader download = downloadTagDictionaryAsset,
  }) : _fetchRelease = fetchRelease,
       _fetchReleasePage = fetchReleasePage,
       _download = download;

  final EhSettingService ehSettingService = Get.find();
  final Future<Map> Function(String) _fetchRelease;
  final Future<String> Function(Uri) _fetchReleasePage;
  final TagDictionaryAssetDownloader _download;
  final _dictionaryRevision = 0.obs;
  final _downloadProgress = Rxn<({int received, int total})>();

  ({int received, int total})? get downloadProgress => _downloadProgress.value;

  Future<bool>? _pendingUpdate;
  late Set<String> _namespaces = isarHelper.findAllTagNamespaces();

  Future<bool> updateTranslations({bool force = false}) async {
    final pending = _pendingUpdate;
    if (pending != null) {
      final updated = await pending;
      return updated || (force && await updateTranslations(force: true));
    }

    final update = _downloadAndImport(force: force).whenComplete(() {
      _pendingUpdate = null;
    });
    _pendingUpdate = update;
    return update;
  }

  Future<bool> _downloadAndImport({required bool force}) async {
    final useCdn = ehSettingService.enableTagTranslateCDN;
    final release = await _latestRelease(useCdn: useCdn);
    final version = release.version;
    final installedVersion = isarHelper.getTranslateVersion();
    if (release.isOlderThan(installedVersion)) {
      logger.w('Skipping older tag dictionary $version (installed: $installedVersion)');
      return false;
    }
    if (!force && version == installedVersion) {
      return false;
    }

    final temp = await Directory.systemTemp.createTemp('eros-tag-translation-');
    try {
      final file = await _downloadDictionary(
        temp,
        useCdn: useCdn,
        releaseUrl: release.downloadUri.toString(),
        expectedSha256: release.sha256,
      );
      final namespaces = await isarHelper.importTagTranslations(
        file.path,
        version,
      );
      _namespaces = namespaces.toSet();
      ehSettingService.tagTranslatVer.value = version;
      _dictionaryRevision.value++;
      return true;
    } finally {
      try {
        await temp.delete(recursive: true);
      } on FileSystemException catch (error) {
        logger.w('Could not remove tag dictionary download', error: error);
      }
    }
  }

  Future<TagDictionaryRelease> _latestRelease({required bool useCdn}) async {
    try {
      final response = await _fetchRelease(tagDictionaryReleaseApi);
      return TagDictionaryRelease.fromApi(response);
    } catch (error) {
      if (!useCdn) {
        rethrow;
      }
      logger.w('GitHub release API failed, using the release page', error: error);
      return TagDictionaryRelease.fromWeb(_fetchReleasePage);
    }
  }

  Future<File> _downloadDictionary(
    Directory temp, {
    required bool useCdn,
    required String releaseUrl,
    required String? expectedSha256,
  }) async {
    if (useCdn && expectedSha256 != null) {
      try {
        final file = File(path.join(temp.path, 'cdn-$tagDictionaryAssetName'));
        await _downloadAsset(_cdnUrl, file);
        await _verifyDigest(file, expectedSha256);
        return file;
      } catch (error) {
        logger.w('Tag dictionary CDN failed, falling back to GitHub', error: error);
      }
    }

    final file = File(path.join(temp.path, tagDictionaryAssetName));
    await _downloadAsset(releaseUrl, file);
    if (expectedSha256 != null) {
      await _verifyDigest(file, expectedSha256);
    }
    return file;
  }

  Future<void> _downloadAsset(String url, File file) async {
    _downloadProgress.value = (received: 0, total: -1);
    try {
      await _download(
        url: url,
        savePath: file.path,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _downloadProgress.value = (received: received, total: total);
          }
        },
      );
    } finally {
      _downloadProgress.value = null;
    }
  }

  Future<void> _verifyDigest(File file, String expectedSha256) async {
    final actual = await sha256.bind(file.openRead()).first;
    if (actual.toString() != expectedSha256) {
      throw const FormatException('Tag dictionary SHA-256 mismatch');
    }
  }

  List<String> getGalleryTagTranslations(List<GalleryTag> tags) {
    // Subscribe the tag area to successful imports, including the same version.
    final _ = _dictionaryRevision.value;
    final translations = isarHelper.findTagTranslations(
      keys: tags.map((tag) => tag.title.toLowerCase()).toList(),
      namespaces: tags.map((tag) => _dictionaryNamespace(tag.type)).toList(),
    );
    return List.generate(
      tags.length,
      (i) => translations[i]?.nameNotMD ?? tags[i].title,
    );
  }

  /// 获取翻译结果
  Future<String?> _getTagTransStr(String key, {String? namespace}) async {
    TagTranslat? tr =
        await isarHelper.findTagTranslate(key, namespace: namespace);

    return tr?.nameNotMD ?? key;
  }

  Future<String?> getTranTagWithNameSpase(
    String tag, {
    String namespace = '',
  }) async {
    if (tag.contains(':')) {
      final RegExp rpfx = RegExp(r'(\w+):"?([^\$]+)\$?"?');
      final RegExpMatch? rult = rpfx.firstMatch(tag.toLowerCase());
      String nameSpase = rult?.group(1) ?? '';
      if (nameSpase.length == 1) {
        nameSpase = EHConst.prefixToNameSpaceMap[nameSpase] ?? nameSpase;
      }

      final String tag0 = rult?.group(2) ?? '';
      final String nameSpaseTran =
          EHConst.translateTagType[nameSpase] ?? nameSpase;
      final String transTag =
          await _getTagTransStr(tag0, namespace: nameSpase) ?? tag0;

      return '$nameSpaseTran:$transTag';
    } else {
      return await _getTagTransStr(tag.toLowerCase(), namespace: namespace);
    }
  }

  /// 自动拆分解析匹配查询tag翻译
  Future<String?> getTranTagWithNameSpaseAuto(String text) async {
    if (!text.trim().contains(' ')) {
      return await getTranTagWithNameSpase(text);
    }
    logger.t(text);
    final array = text.split(RegExp(r'\s+'));
    logger.t(array.map((e) => '[$e]').join(','));

    for (int i = 0; i < array.length; i++) {
      if (array[i].startsWith(RegExp(r'-?\w+:"?'))) {
        if (!RegExp(r'\$"?$').hasMatch(array[i])) {
          final tempArray = array.sublist(i);
          final offset = tempArray
              .indexWhere((element) => RegExp(r'\$"?$').hasMatch(element));
          for (int j = 0; j < offset; j++) {
            array[i] = '${array[i]} ${array[i + 1]}';
            array.removeAt(i + 1);
          }
        }
      }
    }

    logger.t(array.map((e) => '[$e]').join(''));

    final translateList = [];
    for (final text in array) {
      final String? translate = await getTranTagWithNameSpase(text);
      translateList.add(translate ?? text);
    }

    return translateList.join('   ');
  }

  Future<String?> getTagTranslateText(
    String text, {
    String? namespace,
    bool ignoreNamespace = false,
  }) async {
    if (text.contains(':')) {
      final RegExp regPfx = RegExp(r'(\w):(.+)');
      final RegExpMatch? rult = regPfx.firstMatch(text.toLowerCase());
      final String pfx = rult?.group(1) ?? '';
      final String? nameSpase = EHConst.prefixToNameSpaceMap[pfx];
      final String tag = rult?.group(2) ?? '';
      final String? transTag = await _getTagTransStr(tag, namespace: nameSpase);

      if (transTag == null) {
        return text;
      }

      if (ignoreNamespace) {
        return transTag;
      } else {
        return '$pfx:$transTag';
      }

      // return _transTag != null ? '$pfx:$_transTag' : text;
    } else {
      return _getTagTransStr(
        text.toLowerCase(),
        namespace: _dictionaryNamespace(namespace),
      );
    }
  }

  String? _dictionaryNamespace(String? namespace) =>
      namespace != null && namespace.isNotEmpty && _namespaces.contains(namespace)
      ? namespace
      : null;

  Future<TagTranslat?> getTagTranslate(String text, String namespace) async {
    final TagTranslat? translates =
        await isarHelper.findTagTranslate(text, namespace: namespace);

    logger.d(translates?.intro);
    // 查询code字段
    final qryMap = {};
    final RegExp regCode = RegExp(r'`(([\w:]+\s+?)*[\w:]+)`');
    final matches = regCode.allMatches(translates?.intro ?? '');
    for (final match in matches) {
      final ori = match.group(1);
      if (ori != null) {
        final translateCode = await getTagTranslateText(
          ori,
          ignoreNamespace: true,
        );
        if (translateCode != null && translateCode != ori) {
          logger.t('match $ori $translateCode');
          qryMap[ori] = translateCode;
        }
      }
    }

    final intro = translates?.intro?.replaceAllMapped(regCode,
        (match) => ' `${qryMap[match.group(1)]} (${match.group(1)})` ');
    logger.t(intro);

    return translates?.copyWith(intro: intro);
  }

  Future<List<TagTranslat>> getTagTranslatesLike(
      {String text = '', int limit = 100}) async {
    logger.d('getTagTranslatesLike $text');
    if (text.isEmpty) {
      return [];
    }

    final List<TagTranslat> translates =
        await isarHelper.findTagTranslateContains(text, limit);

    return translates;
  }

  Future<void> tapTagTranslate(TagTranslat tagTranslat) async {
    await isarHelper.tapTagTranslate(tagTranslat);
  }
}
