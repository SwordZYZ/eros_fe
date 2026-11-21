import 'dart:io';
import 'dart:math' as math;

import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/generated/l10n.dart';
import 'package:eros_fe/main.dart' as app;
import 'package:eros_fe/pages/image_view/view/view_page.dart';
import 'package:eros_fe/pages/image_view/view/view_widget.dart';
import 'package:eros_fe/pages/setting/read_setting_page.dart';
import 'package:eros_fe/pages/tab/view/home_page.dart';
import 'package:eros_fe/route/navigator_util.dart';
import 'package:eros_fe/widget/cupertino/window_control_insets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iPad reader toolbar clears the safe area and aligns controls', (
    tester,
  ) async {
    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(finder, findsOneWidget);
    }

    await app.main();
    await waitFor(find.byType(HomePage));
    const rootKey = ValueKey('reader-test-root');
    Get.offAll<void>(
      () => const CupertinoPageScaffold(key: rootKey, child: SizedBox.expand()),
      transition: Transition.noTransition,
    );
    final root = find.byKey(rootKey);
    await waitFor(root);
    final settings = Get.find<EhSettingService>();
    final previousPageInterval = settings.showPageInterval.value;
    // The extended page view's spacing trips Flutter's fixed-extent assertion.
    settings.showPageInterval.value = false;
    addTearDown(() => settings.showPageInterval.value = previousPageInterval);
    final fixture = await Directory.systemTemp.createTemp('eros-reader-');
    addTearDown(() => fixture.delete(recursive: true));
    final png = await rootBundle.load('assets/images/dundun.png');
    final file = await File('${fixture.path}/sample.png').writeAsBytes(
      png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
    );

    final viewer = find.byType(ViewPage);
    final bar = find.byType(ViewTopBar);
    Finder icon(FaIconData glyph) => find.descendant(
      of: bar,
      matching: find.byWidgetPredicate(
        (widget) => widget is FaIcon && widget.icon == glyph.data,
        description: 'reader icon ${glyph.data.codePoint}',
      ),
    );
    final back = icon(FontAwesomeIcons.chevronLeft);
    final share = icon(FontAwesomeIcons.share);
    final more = icon(FontAwesomeIcons.ellipsis);
    final tabletActions = [
      icon(FontAwesomeIcons.solidFloppyDisk),
      icon(FontAwesomeIcons.bookOpen),
      icon(FontAwesomeIcons.hourglassHalf),
      icon(FontAwesomeIcons.solidImages),
    ];

    Future<void> openReader() async {
      NavigatorUtil.goGalleryViewPageFile(0, [file.path], '0');
      await waitFor(viewer);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.tap(find.byType(ImageGestureDetector));
      await waitFor(back.hitTestable());
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> closeReader() async {
      await tester.tap(back);
      await tester.pump(const Duration(milliseconds: 700));
      expect(viewer, findsNothing);
      expect(root, findsOneWidget);
    }

    await openReader();
    final insets = await const MethodChannel(
      'eros_fe/window_layout',
    ).invokeMapMethod<String, double>('windowControlInsets');
    expect(insets, isNotNull, reason: 'run this test on an iPad simulator');

    void checkToolbar(List<Finder> actions) {
      final context = tester.element(bar);
      final safe = MediaQuery.viewPaddingOf(context);
      final gestures = MediaQuery.systemGestureInsetsOf(context);
      final center = tester.getCenter(back).dy;
      for (final action in [back, ...actions, share, more]) {
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.getCenter(action).dy, closeTo(center, 0.5));
      }
      final targets = find.descendant(
        of: bar,
        matching: find.byType(CupertinoButton),
      );
      expect(targets, findsNWidgets(3));
      for (final target in targets.evaluate()) {
        final rect = tester.getRect(find.byWidget(target.widget));
        expect(rect.size, const Size(44, 44));
        expect(
          rect.top,
          greaterThanOrEqualTo(math.max(safe.top, gestures.top)),
        );
      }
      final left = tester.getTopLeft(targets.first).dx;
      final right = tester.getTopRight(targets.last).dx;
      expect(
        left,
        closeTo(
          math.max(safe.left + insets!['left']!, gestures.left) + 16,
          0.5,
        ),
      );
      expect(
        right,
        closeTo(
          MediaQuery.sizeOf(context).width -
              math.max(safe.right + insets['right']!, gestures.right) -
              16,
          0.5,
        ),
      );
      debugPrint(
        'READER_TOOLBAR safe=$safe gestures=$gestures UIKit=$insets '
        'left=$left right=$right iconY=$center',
      );
    }

    Future<void> checkReadSettingsBack() async {
      await tester.tap(more);
      final readSettings = find.byType(ReadSettingPage);
      await waitFor(readSettings);
      await tester.pump(const Duration(milliseconds: 500));
      final windowBack = find.descendant(
        of: readSettings,
        matching: find.byType(WindowAwareBackButton),
      );
      final settingsBack = find.descendant(
        of: readSettings,
        matching: find.byType(CupertinoNavigationBarBackButton),
      );
      expect(settingsBack.hitTestable(), findsOneWidget);
      final leftInset = insets!['left']!;
      expect(windowBack, leftInset > 0 ? findsOneWidget : findsNothing);
      if (leftInset > 0) {
        expect(
          tester.getTopLeft(settingsBack).dx - tester.getTopLeft(windowBack).dx,
          closeTo(leftInset, 0.5),
        );
      }
      await tester.tap(settingsBack);
      await tester.pump(const Duration(milliseconds: 500));
      expect(readSettings, findsNothing);
      expect(more.hitTestable(), findsOneWidget);
    }

    checkToolbar(tabletActions);
    await tester.tap(share);
    await waitFor(find.text(L10n.current.share_image));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text(L10n.current.cancel));
    await tester.pump(const Duration(milliseconds: 500));

    await checkReadSettingsBack();
    await closeReader();

    // Test a compact Flutter window from the time the reader opens.
    final size = tester.view.physicalSize;
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = Size(
      390 * tester.view.devicePixelRatio,
      size.height,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await openReader();
    for (final action in tabletActions) {
      expect(action, findsNothing);
    }
    checkToolbar([]);
    await checkReadSettingsBack();
    await closeReader();
    expect(tester.takeException(), isNull);
  });
}
