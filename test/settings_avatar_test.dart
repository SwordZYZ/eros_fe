import 'package:eros_fe/common/controller/user_controller.dart';
import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/generated/l10n.dart';
import 'package:eros_fe/models/index.dart';
import 'package:eros_fe/pages/item/user_item.dart';
import 'package:eros_fe/pages/tab/controller/setting_controller.dart';
import 'package:eros_fe/pages/tab/view/setting_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class _TestSettings extends GetxService implements EhSettingService {
  @override
  final isSafeMode = false.obs;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestUser extends GetxController implements UserController {
  @override
  Rx<User> user = const User(nickName: 'Account').obs;

  @override
  bool get isLogin => user.value.nickName != null;

  int accountActions = 0;

  @override
  Future<void> showLogOutDialog(BuildContext context) async {
    accountActions++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('one tappable account entry survives resize and title collapse', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(375, 390);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(Get.reset);

    final settings = _TestSettings();
    final user = _TestUser();
    Get.put<EhSettingService>(settings);
    Get.put<UserController>(user);
    Get.put(SettingViewController());
    await tester.pumpWidget(
      const GetCupertinoApp(
        localizationsDelegates: [L10n.delegate],
        home: SettingTab(),
      ),
    );
    await tester.pumpAndSettle();

    final account = find.byType(UserWidget);
    Future<void> tapAccount(int count) async {
      expect(account, findsOneWidget);
      expect(account.hitTestable(), findsOneWidget);
      await tester.tap(account);
      expect(user.accountActions, count);
    }

    await tapAccount(1);
    final largeTitle = find
        .descendant(
          of: find.byType(CupertinoSliverNavigationBar),
          matching: find.text(L10n.current.tab_setting),
        )
        .first;
    expect(
      tester.getCenter(account).dy,
      closeTo(tester.getCenter(largeTitle).dy, 2),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -220));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scroll.position.pixels, greaterThan(60));
    await tapAccount(2);

    tester.view.physicalSize = const Size(390, 375);
    await tester.pumpAndSettle();
    await tapAccount(3);

    settings.isSafeMode.value = true;
    await tester.pumpAndSettle();
    expect(account, findsNothing);
    tester.view.physicalSize = const Size(375, 390);
    await tester.pumpAndSettle();
    expect(account, findsNothing);
    settings.isSafeMode.value = false;
    await tester.pumpAndSettle();
    await tapAccount(4);

    user.user.value = const User(
      nickName: 'A long account nickname that should fit beside the title',
    );
    await tester.pumpAndSettle();
    await tapAccount(5);

    expect(tester.takeException(), isNull);
  });
}
