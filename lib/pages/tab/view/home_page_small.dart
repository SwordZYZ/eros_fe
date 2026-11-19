import 'package:eros_fe/common/service/layout_service.dart';
import 'package:eros_fe/const/const.dart';
import 'package:eros_fe/pages/tab/controller/tabhome_controller.dart';
import 'package:eros_fe/widget/cupertino/split_left_scroll_scope.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

class TabHomeSmall extends GetView<TabHomeController> {
  const TabHomeSmall({super.key});
  @override
  Widget build(BuildContext context) {
    controller.init(inContext: context);

    return Obx(() => CupertinoTabScaffold(
          controller: controller.tabController,
          tabBar: CupertinoTabBar(
            backgroundColor: kEnableImpeller
                ? CupertinoTheme.of(context).barBackgroundColor.withOpacity(1)
                : null,
            items: controller.listBottomNavigationBarItem,
            onTap: controller.onTap,
          ),
          tabBuilder: (BuildContext context, int index) {
            // return controller.viewList[index];
            return CupertinoTabView(
              builder: (BuildContext context) {
                final page = controller.viewList[index];
                if (isLayoutLarge &&
                    defaultTargetPlatform == TargetPlatform.iOS) {
                  return SplitLeftScrollScope(child: page);
                }
                return page;
              },
            );
          },
        ));
  }
}
