// Real iOS startup/navigation; no account or live server result is required.
import 'dart:io';

import 'package:eros_fe/common/controller/download_controller.dart';
import 'package:eros_fe/common/global.dart';
import 'package:eros_fe/main.dart' as app;
import 'package:eros_fe/pages/setting/layout_setting_page.dart';
import 'package:eros_fe/pages/tab/view/home_page.dart';
import 'package:eros_fe/route/routes.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offline-account cold start and settings navigation', (
    tester,
  ) async {
    await app.main();
    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(finder, findsOneWidget);
    }

    await waitFor(find.byType(HomePage));
    await tester.runAsync(() async {
      final manager = Get.find<DownloadController>().pathManager;
      await manager.allowMediaScan(false);
      final marker = File('${Global.appDocPath}/Download/.nomedia');
      expect(
        await marker.exists(),
        isTrue,
        reason: 'iOS media marker belongs to the Documents download directory',
      );
      await manager.allowMediaScan(true);
      expect(await marker.exists(), isFalse);
    });
    expect(Global.profile.user.memberId ?? '', isEmpty);
    expect(Global.profile.user.passHash ?? '', isEmpty);
    expect(
      tester.takeException(),
      isNull,
      reason: 'startup must not hide Flutter exceptions',
    );
    debugPrint('IOS_SMOKE cold_start PASS');

    Get.toNamed<void>(EHRoutes.layoutSetting);
    await waitFor(find.byType(LayoutSettingPage));
    await tester.pump(const Duration(milliseconds: 700));
    debugPrint('IOS_SMOKE settings PASS');
    await tester.tap(find.byType(CupertinoNavigationBarBackButton).last);
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(LayoutSettingPage), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'navigation must not hide Flutter exceptions',
    );
    // Deliberate failure injection verifies CLI/CI propagate a failing assertion.
    expect(
      const bool.fromEnvironment('IOS_SMOKE_FORCE_FAILURE'),
      isFalse,
      reason: 'requested smoke failure injection',
    );
    debugPrint('IOS_SMOKE navigation PASS');
  });
}
