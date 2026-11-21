import 'package:eros_fe/common/service/layout_service.dart';
import 'package:eros_fe/pages/tab/controller/tabhome_controller.dart';
import 'package:eros_fe/route/app_pages.dart';
import 'package:eros_fe/route/first_observer.dart';
import 'package:eros_fe/route/main_observer.dart';
import 'package:eros_fe/route/routes.dart';
import 'package:eros_fe/route/second_observer.dart';
import 'package:eros_fe/widget/cupertino/split_left_scroll_scope.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import 'home_page_small.dart';
import 'resizable_split_view.dart';

class TabHomeLarge extends GetView<TabHomeController> {
  const TabHomeLarge({super.key});

  @override
  Widget build(BuildContext context) {
    final LayoutServices layoutServices = Get.find();
    final mainNavigatorObserver = MainNavigatorObserver();
    final left = Navigator(
      key: Get.nestedKey(1),
      observers: [
        FirstNavigatorObserver(),
        if (mainNavigatorObserver.navigator == null) mainNavigatorObserver,
      ],
      onGenerateRoute: (settings) {
        final route = AppPages.routes.firstWhereOrNull(
          (GetPage page) => page.name == settings.name,
        );
        if (route != null &&
            route.name != EHRoutes.root &&
            route.name != EHRoutes.home) {
          return GetPageRoute(
            settings: settings,
            showCupertinoParallax: false,
            page: () {
              final page = route.page();
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
                return SplitLeftScrollScope(child: page);
              }
              return page;
            },
          );
        }
        return GetPageRoute(
          settings: settings,
          page: () => const TabHomeSmall(),
          showCupertinoParallax: false,
        );
      },
    );
    final right = Navigator(
      key: Get.nestedKey(2),
      observers: [SecondNavigatorObserver()],
      initialRoute: EHRoutes.empty,
      onGenerateRoute: AppPages.onGenerateRoute,
    );
    return Obx(
      () => ResizableSplitView(
        proportion: layoutServices.sideProportion,
        onProportionChanged: (value) => layoutServices.sideProportion = value,
        left: left,
        right: right,
      ),
    );
  }
}
