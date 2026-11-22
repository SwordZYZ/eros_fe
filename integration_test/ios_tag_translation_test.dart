import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:eros_fe/common/controller/tag_controller.dart';
import 'package:eros_fe/common/controller/tag_trans_controller.dart';
import 'package:eros_fe/common/global.dart';
import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/common/service/locale_service.dart';
import 'package:eros_fe/common/service/theme_service.dart';
import 'package:eros_fe/models/gallery_tag.dart';
import 'package:eros_fe/models/tag_group.dart';
import 'package:eros_fe/pages/gallery/view/gallery_widget.dart';
import 'package:eros_fe/pages/setting/tag_translat_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oktoast/oktoast.dart';

const _api =
    'https://api.github.com/repos/EhTagTranslation/Database/releases/latest';
const _cdn =
    'https://fastly.jsdelivr.net/gh/EhTagTranslation/Database@release/db.raw.json.gz';
const _release = 'https://github.com/EhTagTranslation/Database/releases';
const _latestPage = '$_release/latest';
String _assetPage(String tag) => '$_release/expanded_assets/$tag';
String _direct(String tag) => '$_release/download/$tag/db.raw.json.gz';
const _published = '2026-11-21T21:36:33Z';

enum _UpdateResult { imported, skipped, failed }

class _Settings extends EhSettingService {
  // Use the test database and in-memory settings.
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _TagColors extends TagController {
  @override
  void onReady() {}
}

List<int> _dictionary(String translation, {bool includeRemoved = false}) {
  return gzip.encode(
    utf8.encode(
      jsonEncode({
        'data': [
          {
            'namespace': 'artist',
            'data': {
              'example': {'name': translation},
              'uncategorized': {'name': '无分类译名'},
              'legacy': {'name': '跨分类译名'},
              'artist-only': {'name': '仅作者译名'},
              if (includeRemoved) 'removed': {'name': '旧标签'},
            },
          },
          {
            'namespace': 'group',
            'data': {
              'example': {'name': '同名团队'},
            },
          },
          {
            'namespace': 'rows',
            'data': {
              'heading-only': {'name': '分类标题'},
            },
          },
          {'namespace': 'empty-category', 'data': {}},
        ],
      }),
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('manual updates refresh only the version and gallery tags', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'tag-translation-test-',
    );
    Global.appSupportPath = directory.path;
    await isarHelper.initIsar();
    addTearDown(() async {
      Get.reset();
      await isarHelper.isar.close();
      await directory.delete(recursive: true);
    });

    Get.testMode = true;
    Global.profile = Global.profile.copyWith(locale: 'zh_CN');
    Get.put(LocaleService());
    Get.put<TagController>(_TagColors());
    final settings = Get.put<EhSettingService>(_Settings());
    Get.put(ThemeService());
    settings.isTagTranslate = true;
    settings.enableTagTranslateCDN = true;

    final requests = <String>[];
    var tag = 'v1';
    var releaseBytes = _dictionary('初版译名', includeRemoved: true);
    var cdnBytes = releaseBytes;
    var haveDigest = true;
    var cdnFailed = false;
    var directFailed = false;
    var apiFailed = true;
    var webFailed = false;
    late Completer<void> releaseGate;
    Future<void> Function(String, void Function(int, int))? checkProgress;
    final controller = Get.put(
      TagTransController(
        fetchRelease: (url) async {
          requests.add(url);
          await releaseGate.future;
          if (apiFailed) {
            throw const SocketException('GitHub API unreachable');
          }
          return {
            'tag_name': tag,
            'published_at': _published,
            'assets': [
              {
                'name': 'db.raw.json.gz',
                'browser_download_url': _direct(tag),
                if (haveDigest)
                  'digest': 'sha256:${sha256.convert(releaseBytes)}',
              },
            ],
          };
        },
        fetchReleasePage: (uri) async {
          requests.add(uri.toString());
          if (webFailed) {
            throw const SocketException('GitHub web unreachable');
          }
          if (uri.toString() == _latestPage) {
            return '''
<main>
  <relative-time datetime="$_published"></relative-time>
  <include-fragment src="${_assetPage(tag)}"></include-fragment>
</main>''';
          }
          expect(uri.toString(), _assetPage(tag));
          return '''
<ul>
  <li><a href="${_direct(tag).replaceFirst('db.raw.json.gz', 'db.full.json.gz')}">db.full.json.gz</a>
    <clipboard-copy value="sha256:${sha256.convert([0])}"></clipboard-copy>
  </li>
  <li><a href="${Uri.parse(_direct(tag)).path}">db.raw.json.gz</a>
    ${haveDigest ? '<clipboard-copy value="sha256:${sha256.convert(releaseBytes)}"></clipboard-copy>' : ''}
  </li>
</ul>''';
        },
        download: ({required url, required savePath, onReceiveProgress}) async {
          requests.add(url);
          await checkProgress?.call(url, onReceiveProgress!);
          if ((url == _cdn && cdnFailed) ||
              (url == _direct(tag) && directFailed)) {
            throw const HttpException('Synthetic download failure');
          }
          await File(
            savePath,
          ).writeAsBytes(url == _cdn ? cdnBytes : releaseBytes);
        },
      ),
    );

    const cachedTags = TagGroup(
      tagType: 'artist',
      galleryTags: [
        GalleryTag(type: 'artist', title: 'example', tagTranslat: '缓存译名'),
        GalleryTag(type: 'artist', title: 'removed', tagTranslat: '缓存旧标签'),
        GalleryTag(type: '', title: 'uncategorized', tagTranslat: '缓存旧标签'),
        GalleryTag(type: 'legacy-type', title: 'legacy', tagTranslat: '缓存旧标签'),
      ],
    );

    Widget screen({required Key galleryKey}) {
      return OKToast(
        child: CupertinoApp(
          navigatorKey: Get.key,
          home: Column(
            children: [
              const Expanded(
                child: SizedBox(width: 393, child: TagTranslatePage()),
              ),
              TagGroupItem(key: galleryKey, tagGroupData: cachedTags),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(screen(galleryKey: const ValueKey(0)));
    final page = tester.element(find.byType(TagTranslatePage));
    final gallery = tester.element(find.byType(TagGroupItem));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final route = ModalRoute.of(page);
    expect(find.text('当前版本:'), findsOneWidget);
    expect(find.text('example'), findsOneWidget);

    Future<void> refresh({
      required List<String> downloads,
      List<String> metadataFallback = const [],
      Map<String, (int, String)> progress = const {},
      required String visibleVersion,
      required String visibleTranslation,
      String? before,
      _UpdateResult result = _UpdateResult.imported,
    }) async {
      requests.clear();
      releaseGate = Completer<void>();
      final previousVersion = find.text(
        '当前版本:${isarHelper.getTranslateVersion()}',
      );
      final versionElement = tester.element(previousVersion);
      final testedDownloads = <String>[];
      checkProgress = progress.isEmpty
          ? null
          : (url, report) async {
              final expected = progress[url];
              if (expected == null) {
                return;
              }
              testedDownloads.add(url);

              report(10, -1);
              await tester.pump();
              expect(find.text('下载中…'), findsOneWidget);
              expect(find.textContaining('下载进度：'), findsNothing);
              report(expected.$1, 1000);
              await tester.pump();
              final label = find.text(expected.$2);
              expect(label, findsOneWidget);
              expect(find.text('下载中…'), findsNothing);
              expect(tester.element(previousVersion), same(versionElement));
              expect(
                tester.getBottomLeft(label).dy,
                lessThanOrEqualTo(tester.getTopLeft(previousVersion).dy),
              );
              expect(
                tester
                    .renderObject<RenderParagraph>(previousVersion)
                    .didExceedMaxLines,
                isFalse,
              );
              expect(find.text('手动更新开始'), findsNothing);
              expect(find.text('更新完成'), findsNothing);
            };
      await tester.tap(find.byIcon(CupertinoIcons.refresh));
      await tester.pump();
      expect(requests, [_api]);
      expect(find.text('下载中…'), findsNothing);
      expect(find.textContaining('下载进度：'), findsNothing);
      if (before != null) {
        expect(find.text(before), findsOneWidget);
      }

      // Join the update started by the visible refresh button.
      final update = controller.updateTranslations();
      releaseGate.complete();
      if (result == _UpdateResult.failed) {
        await expectLater(update, throwsA(isA<Exception>()));
      } else {
        expect(await update, result == _UpdateResult.imported);
      }
      await tester.pump();

      expect(requests, [_api, ...metadataFallback, ...downloads]);
      expect(testedDownloads, progress.keys.toList());
      expect(find.text('下载中…'), findsNothing);
      expect(find.textContaining('下载进度：'), findsNothing);
      expect(isarHelper.getTranslateVersion(), visibleVersion);
      final subtitle = find.text('当前版本:$visibleVersion');
      expect(subtitle, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(subtitle).didExceedMaxLines,
        isFalse,
      );
      expect(find.text(visibleTranslation), findsOneWidget);
      expect(
        find.text('更新完成'),
        result == _UpdateResult.imported ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('更新失败'),
        result == _UpdateResult.failed ? findsOneWidget : findsNothing,
      );
      expect(tester.element(find.byType(TagTranslatePage)), same(page));
      expect(tester.element(find.byType(TagGroupItem)), same(gallery));
      expect(ModalRoute.of(page), same(route));
      expect(navigator.canPop(), isFalse);
      expect(tester.takeException(), isNull);
      dismissAllToast();
      await tester.pumpAndSettle();
    }

    await refresh(
      downloads: [_cdn],
      metadataFallback: [_latestPage, _assetPage(tag)],
      progress: {_cdn: (427, '下载进度：42.7%')},
      visibleVersion: 'v1 $_published',
      visibleTranslation: '初版译名',
      before: 'example',
    );
    expect(find.text('无分类译名'), findsOneWidget);
    expect(find.text('跨分类译名'), findsOneWidget);
    const cases = [
      GalleryTag(type: 'artist', title: 'example', tagTranslat: ''),
      GalleryTag(type: 'group', title: 'example', tagTranslat: ''),
      GalleryTag(type: 'group', title: 'artist-only', tagTranslat: ''),
      GalleryTag(type: 'legacy-type', title: 'example', tagTranslat: ''),
      GalleryTag(type: 'empty-category', title: 'legacy', tagTranslat: ''),
      GalleryTag(type: '', title: 'heading-only', tagTranslat: ''),
    ];
    final legacyDuplicate = await controller.getTagTranslateText(
      'example',
      namespace: 'legacy-type',
    );
    final expected = [
      '初版译名',
      '同名团队',
      'artist-only',
      legacyDuplicate,
      '跨分类译名',
      'heading-only',
    ];
    expect(controller.getGalleryTagTranslations(cases), expected);
    expect(TagTransController().getGalleryTagTranslations(cases), expected);

    expect(find.text('旧标签'), findsOneWidget);
    final used = await isarHelper.findTagTranslate(
      'example',
      namespace: 'artist',
    );
    await isarHelper.tapTagTranslate(used!);

    // Force a re-import under the same version with a stale CDN response.
    releaseBytes = _dictionary('重下译名');
    await refresh(
      downloads: [_cdn, _direct(tag)],
      metadataFallback: [_latestPage, _assetPage(tag)],
      progress: {_cdn: (900, '下载进度：90.0%'), _direct(tag): (123, '下载进度：12.3%')},
      visibleVersion: 'v1 $_published',
      visibleTranslation: '重下译名',
      before: '初版译名',
    );
    expect(find.text('removed'), findsOneWidget);
    expect(find.text('同名团队'), findsNothing);
    expect(
      (await isarHelper.findTagTranslate(
        'example',
        namespace: 'artist',
      ))!.lastUseTime,
      greaterThan(0),
    );

    cdnFailed = true;
    tag = 'v2';
    releaseBytes = _dictionary('直连译名');
    await refresh(
      downloads: [_cdn, _direct(tag)],
      metadataFallback: [_latestPage, _assetPage(tag)],
      visibleVersion: 'v2 $_published',
      visibleTranslation: '直连译名',
    );

    // The API client can return a successful cached v1 after the website
    // fallback installed v2. The cached asset and digest are still valid.
    apiFailed = false;
    cdnFailed = false;
    tag = 'v1';
    releaseBytes = _dictionary('缓存旧版译名');
    cdnBytes = releaseBytes;
    await refresh(
      downloads: [],
      visibleVersion: 'v2 $_published',
      visibleTranslation: '直连译名',
      result: _UpdateResult.skipped,
    );
    expect(find.text('缓存旧版译名'), findsNothing);

    cdnFailed = true;
    directFailed = true;
    tag = 'v3';
    releaseBytes = _dictionary('未入库译名');
    await refresh(
      downloads: [_cdn, _direct(tag)],
      progress: {_cdn: (260, '下载进度：26.0%'), _direct(tag): (321, '下载进度：32.1%')},
      visibleVersion: 'v2 $_published',
      visibleTranslation: '直连译名',
      result: _UpdateResult.failed,
    );
    expect(find.text('未入库译名'), findsNothing);

    directFailed = false;
    haveDigest = false;
    await refresh(
      downloads: [_direct(tag)],
      visibleVersion: 'v3 $_published',
      visibleTranslation: '未入库译名',
    );

    settings.enableTagTranslateCDN = false;
    haveDigest = true;
    await refresh(
      downloads: [_direct(tag)],
      visibleVersion: 'v3 $_published',
      visibleTranslation: '未入库译名',
    );

    // A downloaded but invalid dictionary also leaves both saved values intact.
    tag = 'v4';
    releaseBytes = gzip.encode(utf8.encode('{"data":[]}'));
    await refresh(
      downloads: [_direct(tag)],
      visibleVersion: 'v3 $_published',
      visibleTranslation: '未入库译名',
      result: _UpdateResult.failed,
    );

    apiFailed = true;
    await refresh(
      downloads: [],
      visibleVersion: 'v3 $_published',
      visibleTranslation: '未入库译名',
      result: _UpdateResult.failed,
    );

    settings.enableTagTranslateCDN = true;
    webFailed = true;
    await refresh(
      downloads: [],
      metadataFallback: [_latestPage],
      visibleVersion: 'v3 $_published',
      visibleTranslation: '未入库译名',
      result: _UpdateResult.failed,
    );

    // Mount another gallery from the same cached objects.
    await tester.pumpWidget(screen(galleryKey: const ValueKey(1)));
    expect(find.text('未入库译名'), findsOneWidget);
    expect(find.text('缓存译名'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
