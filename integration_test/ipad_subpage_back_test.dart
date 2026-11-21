import 'package:eros_fe/common/controller/quicksearch_controller.dart';
import 'package:eros_fe/common/controller/update_controller.dart';
import 'package:eros_fe/common/controller/user_controller.dart';
import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/index.dart';
import 'package:eros_fe/main.dart' as app;
import 'package:eros_fe/pages/tab/controller/group/custom_sublist_controller.dart';
import 'package:eros_fe/pages/tab/view/history_page.dart';
import 'package:eros_fe/pages/tab/view/home_page_large.dart';
import 'package:eros_fe/pages/tab/view/setting_page.dart';
import 'package:eros_fe/pages/tab/view/tabbar/custom_profile_setting_page.dart';
import 'package:eros_fe/pages/tab/view/tabbar/custom_profiles_page.dart';
import 'package:eros_fe/pages/tab/view/tabbar/custom_tabbar_page.dart';
import 'package:eros_fe/widget/cupertino/window_control_insets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

const _split = bool.fromEnvironment('IOS_IPAD_SUBPAGE_SPLIT');
const _phone = bool.fromEnvironment('IOS_SUBPAGE_PHONE');
const _profileId = 'subpage-back-fixture';
const _profileName = 'Local test group';

class _OfflineList extends CustomSubListController {
  _OfflineList() : super(profileUuid: _profileId);

  @override
  Future<void> firstLoad() async => change([], status: RxStatus.success());
}

class _OfflineUpdate extends UpdateController {
  @override
  Future<void> checkUpdate({bool showDialog = false}) async {}
}

class _OfflineQuickSearch extends QuickSearchController {
  @override
  Future<void> syncQuickSearch() async {}
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('iPad subpage back buttons clear the window controls', (
    tester,
  ) async {
    const window = _phone
        ? Size(390, 800)
        : (_split ? Size(1030, 800) : Size(540, 800));
    tester.view.physicalSize = window * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);

    await app.main();
    Get.find<EhSettingService>().tabletLayoutType = TabletLayout.automatic;
    Global.profile = Global.profile.copyWith(
      customTabConfig: const CustomTabConfig(
        profiles: [CustomProfile(uuid: _profileId, name: _profileName)],
      ).oN,
    );
    Get.lazyPut<CustomSubListController>(_OfflineList.new, tag: _profileId);
    Get.put<UpdateController>(_OfflineUpdate(), permanent: true);
    // GetX keeps the old fenix factory after deletion, so mark it replaceable.
    GetInstance().markAsDirty<QuickSearchController>();
    Get.put<QuickSearchController>(_OfflineQuickSearch(), permanent: true);
    expect(Get.find<QuickSearchController>(), isA<_OfflineQuickSearch>());
    final user = Get.find<UserController>();
    final previousUser = user.user;
    user.user = kDefUser.obs;
    addTearDown(() => user.user = previousUser);

    Future<void> settleNavigation() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
    }

    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(finder, findsOneWidget);
    }

    final gallery = find.byType(CustomTabbarList);
    final groupBar = find.byType(CustomTabBar);
    await waitFor(groupBar);
    expect(find.byType(TabHomeLarge), _split ? findsOneWidget : findsNothing);
    final insets = await const MethodChannel(
      'eros_fe/window_layout',
    ).invokeMapMethod<String, double>('windowControlInsets');
    expect(insets, _phone ? isNull : isNotNull);
    final leftInset = insets?['left'] ?? 0;

    Future<void> checkBack(String route) async {
      final back = find
          .byElementPredicate(
            (element) =>
                element.widget is CupertinoNavigationBarBackButton &&
                ModalRoute.of(element)?.settings.name == route,
          )
          .hitTestable();
      await waitFor(back);
      final windowBack = find.ancestor(
        of: back,
        matching: find.byType(WindowAwareBackButton),
      );
      expect(
        windowBack,
        leftInset > 0 ? findsOneWidget : findsNothing,
        reason: route,
      );
      if (leftInset > 0) {
        expect(
          tester.getTopLeft(back).dx - tester.getTopLeft(windowBack).dx,
          closeTo(leftInset, 0.5),
          reason: route,
        );
      }
      await tester.tap(back);
      await settleNavigation();
      expect(back, findsNothing, reason: route);
      expect(tester.takeException(), isNull, reason: route);
      debugPrint('IPAD_SUBPAGE_BACK ${window.width} pt $route: passed');
    }

    Get.toNamed<void>(EHRoutes.history, id: _split ? 1 : null);
    await settleNavigation();
    await waitFor(find.byType(HistoryTab));
    await checkBack(EHRoutes.history);
    expect(find.byType(HistoryTab), findsNothing);
    expect(gallery.hitTestable(), findsOneWidget);

    final groupMenu = find.descendant(
      of: groupBar,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is FaIcon && widget.icon == FontAwesomeIcons.bars.data,
      ),
    );
    await tester.tap(groupMenu.hitTestable());
    await settleNavigation();
    final profiles = find.byType(CustomProfilesPage);
    await waitFor(profiles);
    await tester.tap(
      find
          .descendant(of: profiles, matching: find.text(_profileName))
          .hitTestable(),
    );
    await settleNavigation();
    await waitFor(find.byType(CustomProfileSettingPage));
    await checkBack(EHRoutes.customProfileSetting);
    expect(profiles.hitTestable(), findsOneWidget);
    await checkBack(EHRoutes.customProfiles);

    final l10n = L10n.current;
    final settings = find.byType(SettingTab);
    final settingsTab = find.descendant(
      of: find.byType(CupertinoTabBar),
      matching: find.text(l10n.tab_setting),
    );
    await tester.tap(settingsTab);
    await settleNavigation();
    await waitFor(settings);

    for (final (label, route) in [
      (l10n.eh, EHRoutes.ehSetting),
      (l10n.layout, EHRoutes.layoutSetting),
      (l10n.read, EHRoutes.readSetting),
      (l10n.download, EHRoutes.downloadSetting),
      (l10n.search, EHRoutes.searchSetting),
      (l10n.advanced, EHRoutes.advancedSetting),
      (l10n.security, EHRoutes.securitySetting),
      (l10n.about, EHRoutes.about),
    ]) {
      final item = find.descendant(of: settings, matching: find.text(label));
      expect(item.hitTestable(), findsOneWidget, reason: route);
      await tester.tap(item.hitTestable());
      await settleNavigation();
      if (route == EHRoutes.layoutSetting || route == EHRoutes.searchSetting) {
        final (subLabel, subRoute) = route == EHRoutes.layoutSetting
            ? (l10n.tabbar_setting, EHRoutes.pageSetting)
            : (l10n.quick_search, EHRoutes.quickSearch);
        final subItem = find.text(subLabel).hitTestable();
        await waitFor(subItem);
        await tester.tap(subItem);
        await settleNavigation();
        await checkBack(subRoute);
      }
      await checkBack(route);
      expect(settings.hitTestable(), findsOneWidget, reason: route);
    }
  });
}
