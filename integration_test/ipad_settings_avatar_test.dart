import 'package:eros_fe/generated/l10n.dart';
import 'package:eros_fe/main.dart' as app;
import 'package:eros_fe/pages/item/user_item.dart';
import 'package:eros_fe/pages/login/view/login_page.dart';
import 'package:eros_fe/pages/tab/view/home_page_large.dart';
import 'package:eros_fe/pages/tab/view/setting_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the iPad settings avatar remains tappable in a wide window', (
    tester,
  ) async {
    final pixelRatio = tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);

    // Set Flutter window metrics, independently of the simulator's orientation.
    Future<void> resize(Size window) async {
      tester.view.physicalSize = window * pixelRatio;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
    }

    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(finder, findsOneWidget);
    }

    await resize(const Size(800, 820));
    await app.main();
    await waitFor(find.byType(TabHomeLarge));
    final settingsTab = find.descendant(
      of: find.byType(CupertinoTabBar),
      matching: find.text(L10n.current.tab_setting),
    );
    await tester.tap(settingsTab);
    await waitFor(find.byType(SettingTab));

    final account = find.byType(UserWidget);
    expect(account, findsOneWidget);
    expect(account.hitTestable(), findsOneWidget);
    expect(
      MediaQuery.orientationOf(tester.element(account)),
      Orientation.portrait,
    );

    await resize(const Size(820, 800));
    expect(find.byType(TabHomeLarge), findsOneWidget);
    expect(find.byType(SettingTab), findsOneWidget);
    expect(account, findsOneWidget);
    expect(account.hitTestable(), findsOneWidget);
    expect(
      MediaQuery.orientationOf(tester.element(account)),
      Orientation.landscape,
    );
    final title = find
        .descendant(
          of: find.byType(CupertinoSliverNavigationBar),
          matching: find.text(L10n.current.tab_setting),
        )
        .hitTestable();
    expect(title, findsOneWidget);
    expect(
      tester.getRect(account).left,
      greaterThan(tester.getRect(title).right),
    );
    await tester.tap(account);
    await waitFor(find.byType(LoginPage));
    final back = find.byType(CupertinoNavigationBarBackButton);
    expect(back.hitTestable(), findsOneWidget);
    await tester.tap(back);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(LoginPage), findsNothing);
    expect(account.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
