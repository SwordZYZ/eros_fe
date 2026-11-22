import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:eros_fe/common/global.dart';
import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/const/const.dart';
import 'package:flutter_socks_proxy/socks_proxy.dart';
import 'package:get/get.dart' hide Response;
import 'package:html/parser.dart' as html;
import 'package:native_dio_adapter/native_dio_adapter.dart';

import 'api.dart';
import 'request.dart';

const tagDictionaryAssetName = 'db.raw.json.gz';
const tagDictionaryReleaseApi =
    'https://api.github.com/repos/EhTagTranslation/Database/releases/latest';
const _metadataTimeout = Duration(seconds: 10);

Uri _githubReleaseUri(List<String> suffix) => Uri(
  scheme: 'https',
  host: 'github.com',
  pathSegments: ['EhTagTranslation', 'Database', 'releases', ...suffix],
);

class TagDictionaryRelease {
  const TagDictionaryRelease._(
    this._tag,
    this._publishedAt,
    this.downloadUri,
    this.sha256,
  );

  factory TagDictionaryRelease.fromApi(Map release) {
    final tag = release['tag_name'];
    if (tag is! String || tag.isEmpty) {
      throw const FormatException('Invalid tag dictionary release tag');
    }
    final publishedAt = _releaseDate(release['published_at']);
    final assets = release['assets'];
    final asset = assets is List
        ? assets.whereType<Map>().firstWhereOrNull(
            (asset) => asset['name'] == tagDictionaryAssetName,
          )
        : null;
    final url = asset?['browser_download_url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null ||
        uri != _githubReleaseUri(['download', tag, tagDictionaryAssetName])) {
      throw const FormatException('Missing tag dictionary release asset');
    }
    return TagDictionaryRelease._(
      tag,
      publishedAt,
      uri,
      _parseSha256(asset?['digest']),
    );
  }

  final String _tag;
  final String _publishedAt;
  String get version => '$_tag $_publishedAt';
  final Uri downloadUri;
  final String? sha256;

  bool isOlderThan(String installedVersion) {
    final separator = installedVersion.indexOf(' ');
    final installedTag = separator < 0
        ? installedVersion
        : installedVersion.substring(0, separator);
    final order = _compareNumericTags(_tag, installedTag);
    if (order != null && order != 0) {
      return order < 0;
    }

    // Existing databases store the tag and GitHub publication timestamp.
    final installedDate = separator < 0
        ? null
        : DateTime.tryParse(installedVersion.substring(separator + 1));
    return installedDate != null &&
        DateTime.parse(_publishedAt).isBefore(installedDate);
  }

  static Future<TagDictionaryRelease> fromWeb(
    Future<String> Function(Uri) fetchPage,
  ) async {
    final latest = _githubReleaseUri(['latest']);
    final page = html.parse(await fetchPage(latest));
    final fragmentSource = page
        .querySelector(
          'main include-fragment[src*="/releases/expanded_assets/"]',
        )
        ?.attributes['src'];
    final fragment = fragmentSource == null
        ? null
        : latest.resolve(fragmentSource);
    final tag = fragment?.pathSegments.lastOrNull;
    if (tag == null ||
        tag.isEmpty ||
        fragment != _githubReleaseUri(['expanded_assets', tag])) {
      throw const FormatException('Invalid GitHub release asset fragment');
    }
    final publishedAt = _releaseDate(
      page
          .querySelector('main relative-time[datetime]')
          ?.attributes['datetime'],
    );

    final assets = html.parseFragment(await fetchPage(fragment!));
    final downloadUri = _githubReleaseUri([
      'download',
      tag,
      tagDictionaryAssetName,
    ]);
    final row = assets
        .querySelectorAll('li')
        .firstWhereOrNull(
          (item) => item
              .querySelectorAll('a[href]')
              .any(
                (link) =>
                    fragment.resolve(link.attributes['href']!) == downloadUri,
              ),
        );
    if (row == null) {
      throw const FormatException('Missing tag dictionary release asset');
    }
    final digest = row
        .querySelector('clipboard-copy[value^="sha256:"]')
        ?.attributes['value'];
    return TagDictionaryRelease._(
      tag,
      publishedAt,
      downloadUri,
      _parseSha256(digest),
    );
  }
}

final _numericTag = RegExp(r'^[vV]?(\d+(?:\.\d+)*)$');

int? _compareNumericTags(String releaseTag, String installedTag) {
  final release = _numericTag.firstMatch(releaseTag)?.group(1)?.split('.');
  final installed = _numericTag.firstMatch(installedTag)?.group(1)?.split('.');
  if (release == null || installed == null) {
    return null;
  }

  for (var i = 0; i < release.length || i < installed.length; i++) {
    final current = i < release.length ? int.tryParse(release[i]) : 0;
    final local = i < installed.length ? int.tryParse(installed[i]) : 0;
    if (current == null || local == null) {
      return null;
    }
    final order = current.compareTo(local);
    if (order != 0) {
      return order;
    }
  }
  return 0;
}

String _releaseDate(Object? publishedAt) {
  if (publishedAt is! String || DateTime.tryParse(publishedAt) == null) {
    throw const FormatException('Invalid tag dictionary release metadata');
  }
  return publishedAt;
}

String? _parseSha256(Object? digest) => digest is String
    ? RegExp(
        r'^sha256:([a-fA-F0-9]{64})$',
      ).firstMatch(digest)?.group(1)?.toLowerCase()
    : null;

Future<Map> fetchTagDictionaryReleaseApi(String url) async {
  final data = await _fetchMetadata(url, ResponseType.json);
  if (data is Map) {
    return data;
  }
  throw const FormatException('Invalid GitHub release API response');
}

Future<String> fetchTagDictionaryReleasePage(Uri uri) async {
  final data = await _fetchMetadata(uri.toString(), ResponseType.plain);
  if (data is String) {
    return data;
  }
  throw const FormatException('Invalid GitHub release web response');
}

Future<Object?> _fetchMetadata(String url, ResponseType responseType) async {
  final client = _dictionaryClient(receiveTimeout: _metadataTimeout);
  client.interceptors.add(DioCacheInterceptor(options: Api.cacheOption));
  final cancel = CancelToken();
  try {
    final response = await client
        .get<Object?>(
          url,
          options: getCacheOptions(
            refresh: true,
            forceCache: false,
          ).copyWith(responseType: responseType),
          cancelToken: cancel,
        )
        .timeout(
          _metadataTimeout,
          onTimeout: () {
            cancel.cancel();
            throw TimeoutException('GitHub release metadata request timed out');
          },
        );
    return response.data;
  } finally {
    client.close(force: true);
  }
}

typedef TagDictionaryAssetDownloader =
    Future<void> Function({
      required String url,
      required String savePath,
      ProgressCallback? onReceiveProgress,
    });

Future<void> downloadTagDictionaryAsset({
  required String url,
  required String savePath,
  ProgressCallback? onReceiveProgress,
}) async {
  final client = _dictionaryClient(receiveTimeout: const Duration(seconds: 30));
  try {
    await client.download(url, savePath, onReceiveProgress: onReceiveProgress);
  } finally {
    client.close(force: true);
  }
}

Dio _dictionaryClient({required Duration receiveTimeout}) {
  // Public GitHub and CDN requests use the configured proxy with normal TLS
  // validation and without E-Hentai cookies.
  final client = Dio(
    BaseOptions(
      connectTimeout: _metadataTimeout,
      receiveTimeout: receiveTimeout,
      headers: {'User-Agent': EHConst.CHROME_USER_AGENT},
    ),
  );
  final proxy = globalDioConfig.proxy;
  client.httpClientAdapter =
      Get.find<EhSettingService>().nativeHttpClientAdapter
      ? NativeAdapter()
      : IOHttpClientAdapter(
          createHttpClient: () {
            final httpClient = createProxyHttpClient();
            if (proxy != null && proxy.isNotEmpty) {
              httpClient.findProxy = (_) => proxy;
            }
            return httpClient;
          },
        );
  return client;
}
