import 'package:eros_fe/common/controller/history_controller.dart';
import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/common/service/layout_service.dart';
import 'package:eros_fe/common/service/theme_service.dart';
import 'package:eros_fe/const/theme_colors.dart';
import 'package:eros_fe/models/base/eh_models.dart';
import 'package:eros_fe/pages/controller/fav_controller.dart';
import 'package:eros_fe/pages/gallery/controller/gallery_page_state.dart';
import 'package:eros_fe/pages/item/controller/galleryitem_controller.dart';
import 'package:eros_fe/pages/item/gallery_item.dart';
import 'package:eros_fe/pages/tab/controller/tabhome_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:keframe/keframe.dart';

class _Services extends GetxController
    implements EhSettingService, FavController, HistoryController {
  final _tagLimit = 6.obs;
  final _fixedHeight = true.obs;
  final _blurCover = false.obs;

  @override
  int get listViewTagLimit => _tagLimit.value;

  @override
  bool get isPureDarkTheme => false;

  @override
  bool get debugMode => false;

  @override
  bool get fixedHeightOfListItems => _fixedHeight.value;

  @override
  bool get blurringOfCoverBackground => _blurCover.value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Tabs extends GetxController implements TabHomeController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Theme extends ThemeService {
  @override
  void onInit() {}
}

class _Layout extends LayoutServices {
  @override
  void onInit() {}
}

void main() {
  tearDown(Get.reset);

  testWidgets('a left card retains its latest values when detail is replaced', (
    tester,
  ) async {
    final services = _Services();
    Get.put<EhSettingService>(services, permanent: true);
    Get.put<FavController>(services, permanent: true);
    Get.put<TabHomeController>(_Tabs(), permanent: true);
    Get.put<HistoryController>(services, permanent: true);
    Get.put<ThemeService>(_Theme(), permanent: true);
    Get.put<LayoutServices>(_Layout()..layoutMode = LayoutMode.large);

    final navigator = GlobalKey<NavigatorState>();
    final cache = GlobalKey<SizeCacheWidgetState>();
    final showCard = ValueNotifier(false);
    addTearDown(showCard.dispose);
    const row = GalleryProvider(gid: '42', englishTitle: 'Fixture');
    final state = GalleryPageState()..galleryProvider = row;

    GetPageRoute<void> detail(String name) => GetPageRoute<void>(
      settings: RouteSettings(name: name),
      page: () => const SizedBox(),
      transitionDuration: Duration.zero,
    );

    await tester.pumpWidget(
      GetMaterialApp(
        home: Row(
          children: [
            Expanded(
              child: SizeCacheWidget(
                key: cache,
                child: ListView(
                  children: [
                    ValueListenableBuilder<bool>(
                      valueListenable: showCard,
                      builder: (context, show, child) => show
                          ? const FrameSeparateWidget(
                              index: 0,
                              placeHolder: SizedBox(height: 216),
                              child: GalleryItemWidget(
                                tabTag: 'list',
                                galleryProvider: row,
                              ),
                            )
                          : const SizedBox(height: 100),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Navigator(
                key: navigator,
                onGenerateRoute: (_) => detail('A'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    GalleryItemController.bindToCard(row);
    final initial = state.itemController!;
    expect(initial.favCat, isEmpty);
    final refreshed = row.copyWith(favTitle: 'Category 2'.oN, favcat: '2'.oN);
    GalleryItemController.bindToCard(refreshed);
    expect(state.itemController!.favCat, '2');
    showCard.value = true;
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final favoriteIcon = find.descendant(
      of: find.byType(GalleryItemWidget),
      matching: find.byType(FaIcon),
    );
    expect(
      tester.widget<FaIcon>(favoriteIcon).color,
      ThemeColors.favColor['2'],
    );

    navigator.currentState!.pushReplacement(detail('B'));
    await tester.pumpAndSettle();
    expect(initial.isClosed, isTrue, reason: 'route A disposed its dependency');
    final restored = state.itemController!;
    expect(restored.galleryProvider, same(refreshed));
    expect(restored.favCat, '2');

    restored.setFavTitleAndFavcat(favTitle: 'Category 6', favcat: '6');
    GalleryItemController.bindToCard(refreshed);
    expect(state.itemController!.favCat, '6');
    await tester.pumpAndSettle();
    expect(
      tester.widget<FaIcon>(favoriteIcon).color,
      ThemeColors.favColor['6'],
    );
    navigator.currentState!.pushReplacement(detail('C'));
    await tester.pumpAndSettle();
    expect(state.itemController!.favCat, '6');

    GalleryItemController.bindToCard(row);
    expect(state.itemController!.favCat, isEmpty);
    expect(state.itemController!.isFav, isFalse);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(GalleryItemWidget), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(favoriteIcon, findsNothing);
    expect(cache.currentState!.itemsSizeCache[0]!.height, 216);
  });
}
