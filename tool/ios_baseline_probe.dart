// Step 5A Debug entry point: data injection and observation only.
// The production gallery, torrent buttons and Share.share call are unchanged.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:eros_fe/common/controller/gallerycache_controller.dart';
import 'package:eros_fe/common/global.dart';
import 'package:eros_fe/common/service/controller_tag_service.dart';
import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/main.dart' as application;
import 'package:eros_fe/models/base/eh_models.dart';
import 'package:eros_fe/pages/gallery/controller/gallery_page_controller.dart';
import 'package:eros_fe/pages/gallery/controller/gallery_page_state.dart';
import 'package:eros_fe/pages/gallery/controller/torrent_controller.dart';
import 'package:eros_fe/pages/gallery/gallery_repository.dart';
import 'package:eros_fe/pages/gallery/view/gallery_widget.dart';
import 'package:eros_fe/pages/gallery/view/torrent_dialog.dart';
import 'package:eros_fe/route/routes.dart';
import 'package:eros_fe/widget/image/eh_cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';

import 'fixtures/ios_mlkit_images.dart';
import 'fixtures/ios_step5a_data.dart';

final _events = <Map<String, Object?>>[];
int _pointer = 100;
int _lifecycleStart = 0;
late GalleryProvider _gallery;

void _event(String kind, Map<String, Object?> data) {
  final event = <String, Object?>{
    'time': DateTime.now().toUtc().toIso8601String(),
    'kind': kind,
    ...data,
  };
  _events.add(event);
  debugPrint('STEP5A_EVENT ${jsonEncode(event)}');
  if (Global.appDocPath.isNotEmpty) {
    File(
      '${Global.appDocPath}/step5a-events.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_events));
  }
}

void _result(String name, bool passed, Object? actual) => _event('result', {
  'case': name,
  'status': passed ? 'PASS' : 'FAIL',
  'actual': actual,
});

List<Element> _find(bool Function(Element) predicate, [Element? parent]) {
  final result = <Element>[];
  void visit(Element element) {
    if (predicate(element)) {
      result.add(element);
    }
    element.visitChildren(visit);
  }

  final root = parent ?? WidgetsBinding.instance.rootElement;
  if (root != null) {
    visit(root);
  }
  return result;
}

bool _has(String name) =>
    _find((e) => e.widget.runtimeType.toString() == name).isNotEmpty;

Future<void> _wait(bool Function() predicate, String description) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(description);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await Future<void>.delayed(const Duration(milliseconds: 700));
  await WidgetsBinding.instance.endOfFrame;
}

Future<void> _tap(Element element) async {
  await Scrollable.ensureVisible(
    element,
    duration: const Duration(milliseconds: 300),
  );
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final box = element.findRenderObject()! as RenderBox;
  final position = box.localToGlobal(box.size.center(Offset.zero));
  final pointer = _pointer++;
  _event('tap', {
    'widget': element.widget.runtimeType.toString(),
    'x': position.dx,
    'y': position.dy,
  });
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(pointer: pointer, position: position),
  );
  await Future<void>.delayed(const Duration(milliseconds: 80));
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(pointer: pointer, position: position),
  );
  await Future<void>.delayed(const Duration(milliseconds: 700));
}

class _LocalTorrentController extends TorrentController {
  // Replace only the remote data loader; production UI and share call stay real.
  @override
  // ignore: must_call_super
  void onInit() {
    pageController = Get.find<GalleryPageController>(tag: step5aGid);
    change(
      TorrentProvider()
        ..torrents = [GalleryTorrent.fromJson(step5aTorrentData)]
        ..torrentToken = '500001',
      status: RxStatus.success(),
    );
  }
}

Future<void> _seed() async {
  const imageUrl = 'https://fixture.invalid/step5a-cover.png';
  await imageCacheManager().putFile(
    imageUrl,
    base64Decode(qrPngBase64),
    fileExtension: 'png',
    maxAge: const Duration(days: 365),
  );
  final image = const GalleryImage(
    ser: 0,
    gid: step5aGid,
    token: step5aToken,
    thumbUrl: imageUrl,
    imageUrl: imageUrl,
    thumbWidth: 264,
    thumbHeight: 264,
    imageWidth: 264,
    imageHeight: 264,
    href: 'https://fixture.invalid/s/step5a/1',
  );
  _gallery = GalleryProvider(
    gid: step5aGid,
    token: step5aToken,
    url: '/g/$step5aGid/$step5aToken/',
    imgUrl: imageUrl,
    imgUrlL: imageUrl,
    imgWidth: 264,
    imgHeight: 264,
    englishTitle: step5aTitle,
    japaneseTitle: '',
    category: 'misc',
    uploader: 'Step5A Local Fixture',
    posted: '2026-01-01 00:00',
    language: 'English',
    filecount: '1',
    rating: 4,
    ratingCount: '1',
    torrentcount: '1',
    filesize: 1048576,
    filesizeText: '1.00 MiB',
    visible: 'Yes',
    favoritedCount: '0',
    tagGroup: const [],
    galleryComment: const [],
    galleryImages: [image],
    chapter: const [],
  );
  final repository = GalleryRepository(item: _gallery);
  final state = GalleryPageState()
    ..galleryRepository = repository
    ..galleryProvider = _gallery
    ..firstPageImage = [image]
    ..currentImagePage = 0
    ..enableRead = true;
  state.images.add(image);
  Get.find<GalleryCacheController>().addGalleryPageState(state);
  _event('fixture', {
    'gid': step5aGid,
    'title': step5aTitle,
    'magnet': step5aMagnet,
    'torrentCount': 1,
    'account': 'none',
    'network': 'fixed content uses injected data and prefilled image cache',
    'cover': 'Step4 fixed QR PNG',
  });
}

Future<void> _openGallery() async {
  Get.put<GalleryRepository>(GalleryRepository(item: _gallery), tag: step5aGid);
  Get.lazyPut<TorrentController>(
    () => _LocalTorrentController(),
    tag: step5aGid,
  );
  Get.find<ControllerTagService>().pushPageCtrl(gid: step5aGid);
  Get.toNamed<void>(EHRoutes.galleryPage);
  await _wait(() => _has('GalleryActions'), 'fixed GalleryActions');
  final state = Get.find<GalleryPageController>(tag: step5aGid).gState;
  _result(
    'fixed_content',
    state.gid == step5aGid && state.mainTitle == step5aTitle,
    state.mainTitle,
  );
}

Future<void> _openTorrent() async {
  final buttons = _find(
    (e) =>
        e.widget is TextBtn &&
        (e.widget as TextBtn).iconData == FontAwesomeIcons.magnet,
  );
  if (buttons.isEmpty) {
    throw StateError('Real gallery torrent button missing');
  }
  final child = _find((e) => e.widget is CupertinoButton, buttons.last).single;
  await _tap(child);
  await _wait(() => _has('TorrentItem'), 'real TorrentItem');
  final item = _find((e) => e.widget is TorrentItem).last.widget as TorrentItem;
  _result(
    'torrent_submenu',
    item.torrent.hash == step5aHash,
    item.torrent.name,
  );
}

Future<void> _closeTorrent() async {
  if (!_has('TorrentView')) {
    return;
  }
  await _tap(_find((e) => e.widget is CupertinoDialogAction).last);
  await _wait(() => !_has('TorrentView'), 'torrent dialog close');
}

Future<Map<String, Object?>> _command(
  String command,
  Map<String, String> parameters,
) async {
  switch (command) {
    case 'snapshot':
      break;
    case 'gallery':
      await _openGallery();
      break;
    case 'torrent':
      await _openTorrent();
      break;
    case 'share':
      final before = _events.length;
      final item = _find((e) => e.widget is TorrentItem).last;
      await _tap(_find((e) => e.widget is CupertinoButton, item).single);
      await Future<void>.delayed(const Duration(seconds: 3));
      final errors = _events
          .skip(before)
          .where(
            (e) =>
                e['kind'] == 'error' &&
                '${e['error']}'.contains('sharePositionOrigin'),
          )
          .toList();
      // No exception is NOT evidence of a usable native share menu.
      _event('result', {
        'case': 'system_share_visible_and_usable',
        'status': errors.isNotEmpty ? 'FAIL' : 'NEEDS_NATIVE_OBSERVATION',
        'expected': 'system share menu appears and is usable',
        'magnet': step5aMagnet,
        'errors': errors,
        'source': 'lib/pages/gallery/view/torrent_dialog.dart:171',
      });
      break;
    case 'smoke':
      await _closeTorrent();
      await _tap(
        _find((e) => e.widget is CupertinoNavigationBarBackButton).last,
      );
      await _wait(() => !_has('GalleryActions'), 'return from gallery');
      _result('back_navigation', _has('HomePage'), Get.currentRoute);
      Get.toNamed<void>(EHRoutes.layoutSetting);
      await _wait(() => _has('LayoutSettingPage'), 'real settings page');
      _result('settings', true, 'LayoutSettingPage');
      await _tap(
        _find((e) => e.widget is CupertinoNavigationBarBackButton).last,
      );
      await _wait(() => !_has('LayoutSettingPage'), 'return from settings');
      _result('settings_back', _has('HomePage'), Get.currentRoute);
      await _openGallery();
      break;
    case 'privacy':
      await _closeTorrent();
      Get.toNamed<void>(EHRoutes.securitySetting);
      await _wait(() => _has('SecuritySettingPage'), 'real security settings');
      final value = parameters['enabled'] == 'true';
      final settings = Get.find<EhSettingService>();
      if (settings.blurredInRecentTasks != value) {
        await _tap(_find((e) => e.widget is CupertinoSwitch).last);
      }
      await Future<void>.delayed(const Duration(seconds: 1));
      _result(
        'privacy_setting_${value ? 'on' : 'off'}',
        settings.blurredInRecentTasks == value,
        settings.blurredInRecentTasks,
      );
      await _tap(
        _find((e) => e.widget is CupertinoNavigationBarBackButton).last,
      );
      await _wait(() => !_has('SecuritySettingPage'), 'return from security');
      break;
    case 'lifecycle_begin':
      _lifecycleStart = _events.length;
      _event('lifecycle_begin', {
        'label': parameters['label'],
        'privacy': Get.find<EhSettingService>().blurredInRecentTasks,
      });
      break;
    case 'lifecycle_end':
      await _wait(
        () =>
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
        'actual foreground resumed',
      );
      final recent = _events.skip(_lifecycleStart).toList();
      final states = recent
          .where((e) => e['kind'] == 'lifecycle')
          .map((e) => e['state'])
          .toList();
      final errors = recent.where((e) => e['kind'] == 'error').toList();
      final restored =
          states.contains('paused') &&
          states.contains('resumed') &&
          _has('GalleryActions');
      _result('${parameters['label']}_restore', restored, {
        'states': states,
        'route': Get.currentRoute,
      });
      _result('${parameters['label']}_no_exception', errors.isEmpty, errors);
      await _openTorrent();
      await _closeTorrent();
      _result(
        '${parameters['label']}_interaction',
        true,
        'real torrent menu reopened and closed',
      );
      break;
    default:
      throw ArgumentError('Unknown Step5A command: $command');
  }
  return {
    'command': command,
    'route': Get.currentRoute,
    'lifecycle': WidgetsBinding.instance.lifecycleState?.name,
    'gallery': _has('GalleryActions'),
    'torrent': _has('TorrentItem'),
    'privacy': Get.find<EhSettingService>().blurredInRecentTasks,
    'events': _events,
  };
}

class _LifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _event('lifecycle', {'state': state.name});
}

Future<void> main() async {
  if (!kDebugMode || !Platform.isIOS) {
    throw StateError('Step5A requires iOS Debug');
  }
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      WidgetsBinding.instance.addObserver(_LifecycleObserver());
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        _event('error', {
          'channel': 'FlutterError',
          'error': details.exception.toString(),
          'stack': details.stack.toString(),
        });
      };
      await application.main();
      await _wait(() => _has('HomePage'), 'cold start HomePage');
      _result('cold_start', true, 'HomePage');
      _result(
        'startup_no_exception',
        !_events.any((e) => e['kind'] == 'error'),
        _events.where((e) => e['kind'] == 'error').toList(),
      );
      final user = Global.profile.user;
      _result(
        'no_online_account',
        !(user.memberId?.isNotEmpty ?? false) &&
            !(user.passHash?.isNotEmpty ?? false),
        'credential presence checked; values not recorded',
      );
      await _seed();
      _event('environment', {
        'dart': Platform.version,
        'os': Platform.operatingSystemVersion,
        'mode': 'Debug',
        'autoLockTimeout': Get.find<EhSettingService>().autoLockTimeOut.value,
      });
      developer.registerExtension('ext.eros.step5a', (
        method,
        parameters,
      ) async {
        try {
          final result = await _command(
            parameters['command'] ?? 'snapshot',
            parameters,
          ).timeout(const Duration(seconds: 60));
          return developer.ServiceExtensionResponse.result(jsonEncode(result));
        } catch (error, stack) {
          _event('driver_error', {
            'command': parameters['command'],
            'error': '$error',
            'stack': '$stack',
          });
          return developer.ServiceExtensionResponse.error(
            developer.ServiceExtensionResponse.extensionError,
            '$error',
          );
        }
      });
      debugPrint('STEP5A_READY');
    },
    (error, stack) {
      debugPrint('STEP5A_UNHANDLED $error\n$stack');
      _event('error', {
        'channel': 'uncaught async',
        'error': '$error',
        'stack': '$stack',
      });
    },
  );
}
