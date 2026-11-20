import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/index.dart';
import 'package:eros_fe/pages/item/user_item.dart';
import 'package:eros_fe/pages/tab/controller/setting_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

class SettingTab extends GetView<SettingViewController> {
  const SettingTab({super.key});

  @override
  Widget build(BuildContext context) {
    controller.initData(context);
    final title = L10n.of(context).tab_setting;
    final settings = Get.find<EhSettingService>();

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          Obx(() {
            final account = settings.isSafeMode.value
                ? null
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 112),
                    child: const UserWidget(),
                  );

            return SliverLayoutBuilder(
              builder: (context, constraints) {
                // Move the account button before the large-title row clips
                // its tap target during collapse.
                final accountInLargeTitle =
                    account != null &&
                    MediaQuery.orientationOf(context) == Orientation.portrait &&
                    constraints.scrollOffset <= 8;
                return CupertinoSliverNavigationBar(
                  heroTag: 'setting',
                  alwaysShowMiddle: false,
                  middle: Text(title),
                  largeTitle: accountInLargeTitle
                      ? Row(
                          children: [
                            Expanded(child: Text(title)),
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                end: 16,
                              ),
                              child: account,
                            ),
                          ],
                        )
                      : Text(title),
                  trailing: accountInLargeTitle ? null : account,
                );
              },
            );
          }),
          SliverSafeArea(
            top: false,
            sliver: SliverCupertinoListSection.insetGrouped(
              itemCount: controller.itemCount,
              itemBuilder: (context, index) {
                return controller.cupertinoListTileBuilder(index);
              },
            ),
          ),
        ],
      ),
    );
  }
}
