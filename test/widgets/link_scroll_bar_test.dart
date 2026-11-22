import 'package:eros_fe/common/service/layout_service.dart';
import 'package:eros_fe/common/service/theme_service.dart';
import 'package:eros_fe/const/theme_colors.dart';
import 'package:eros_fe/models/favcat.dart';
import 'package:eros_fe/pages/tab/controller/favorite/favorite_tabbar_controller.dart';
import 'package:eros_fe/pages/tab/view/tabbar/favorite_tabbar_page.dart';
import 'package:eros_fe/route/routes.dart';
import 'package:eros_fe/widget/link_scroll_bar.dart';
import 'package:eros_fe/widget/link_scroll_bar_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';

void main() {
  testWidgets('indicator matches the laid-out label when opening a group', (
    tester,
  ) async {
    final pages = PageController(initialPage: 2);
    final tabs = LinkScrollBarController();
    addTearDown(pages.dispose);
    addTearDown(tabs.dispose);
    await _pumpBar(
      tester,
      tabs: tabs,
      pages: pages,
      initIndex: 2,
      labelTopPadding: 4,
      contentPadding: const EdgeInsetsDirectional.only(start: 8),
      items: [
        LinkTabItem(title: '首页'),
        LinkTabItem(title: 'Longer group'),
        LinkTabItem(title: '收藏'),
      ],
    );

    final selectedLabel = tester.getRect(find.text('收藏'));
    await _expectIndicator(tester, selectedLabel);
    expect(
      selectedLabel.center.dy - tester.getTopLeft(find.byKey(_boundaryKey)).dy,
      closeTo(20, 0.5),
    );

    await tester.tap(find.text('首页'));
    await tester.pumpAndSettle();
    expect(pages.page, 0);
    expect(
      tester.getTopLeft(find.text('首页')).dx -
          tester.getTopLeft(find.byKey(_boundaryKey)).dx,
      18,
    );
    await _expectIndicator(tester, tester.getRect(find.text('首页')));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-220, 0));
    await tester.pump();
    final progress = pages.page!;
    expect(progress, allOf(greaterThan(0), lessThan(1)));
    await _expectIndicator(
      tester,
      Rect.lerp(
        tester.getRect(find.text('首页')),
        tester.getRect(find.text('Longer group')),
        progress,
      )!,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle();
    expect(pages.page, 2);
    await _expectIndicator(tester, tester.getRect(find.text('收藏')));
  });

  testWidgets('favorite labels stay aligned after scrolling and resizing', (
    tester,
  ) async {
    final pages = PageController();
    final tabs = LinkScrollBarController();
    addTearDown(pages.dispose);
    addTearDown(tabs.dispose);
    final items = [
      LinkTabItem(title: '全部收藏'),
      LinkTabItem(title: 'Long favorite name'),
      LinkTabItem(title: 'Category 2'),
      LinkTabItem(title: '稍后阅读'),
    ];
    const padding = EdgeInsets.symmetric(horizontal: 8);
    await _pumpBar(
      tester,
      tabs: tabs,
      pages: pages,
      width: 210,
      itemPadding: padding,
      items: items,
    );

    pages.jumpToPage(3);
    await tester.pumpAndSettle();
    final lastLabel = find.text('稍后阅读');
    final bar = find.byKey(_boundaryKey);
    expect(tester.getRect(bar).contains(tester.getCenter(lastLabel)), isTrue);
    await _expectIndicator(tester, tester.getRect(lastLabel));

    await _pumpBar(
      tester,
      tabs: tabs,
      pages: pages,
      itemPadding: padding,
      items: items,
      textScale: 1.4,
    );
    expect(pages.page, 3);
    await _expectIndicator(tester, tester.getRect(lastLabel));
  });

  testWidgets('favorite menu reveals and selects the last group after a tap', (
    tester,
  ) async {
    final pages = PageController();
    final tabs = LinkScrollBarController();
    final favorites = _Favorites();
    addTearDown(pages.dispose);
    addTearDown(tabs.dispose);
    addTearDown(Get.reset);
    Get.put<LayoutServices>(_Layout());
    Get.put<ThemeService>(_Theme());

    await tester.pumpWidget(
      GetCupertinoApp(
        getPages: [
          GetPage(
            name: EHRoutes.selFavorite,
            page: () => Center(
              child: CupertinoButton(
                onPressed: () => Get.back(result: favorites.favcatList.last),
                child: const Text('Jump to last group'),
              ),
            ),
          ),
        ],
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 240,
            height: 240,
            child: Column(
              children: [
                RepaintBoundary(
                  key: _boundaryKey,
                  child: FavoriteTabBar(
                    pageController: pages,
                    linkScrollBarController: tabs,
                    controller: favorites,
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: pages,
                    onPageChanged: tabs.scrollToItem,
                    itemCount: favorites.favcatList.length,
                    itemBuilder: (_, _) => const SizedBox(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tapped = find.text('Read');
    final last = find.text('Local');
    await tester.tap(tapped);
    await tester.pumpAndSettle();
    expect(pages.page, 1);
    expect(
      tester.widget<Text>(tapped).style!.color,
      CupertinoColors.activeBlue,
    );
    expect(last.hitTestable(), findsNothing);

    final menu = find.byWidgetPredicate(
      (widget) => widget is FaIcon && widget.icon == FontAwesomeIcons.bars.data,
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jump to last group'));
    await tester.pumpAndSettle();

    expect(pages.page, favorites.favcatList.length - 1);
    expect(last.hitTestable(), findsOneWidget);
    expect(tester.widget<Text>(last).style!.color, CupertinoColors.activeBlue);
    expect(
      tester.widget<Text>(tapped).style!.color,
      isNot(CupertinoColors.activeBlue),
    );
    await _expectIndicator(tester, tester.getRect(last));
  });

  testWidgets('standalone tabs underline only the text beside an icon', (
    tester,
  ) async {
    final tabs = LinkScrollBarController();
    addTearDown(tabs.dispose);
    await _pumpBar(tester, tabs: tabs, items: []);
    expect(tester.takeException(), isNull);

    final items = [
      LinkTabItem(title: 'Home'),
      LinkTabItem(title: 'With icon', icon: CupertinoIcons.star),
    ];
    await _pumpBar(
      tester,
      tabs: tabs,
      itemPadding: const EdgeInsetsDirectional.only(start: 18, end: 6),
      items: items,
    );
    final label = find.text('With icon');
    await tester.tap(label);
    await tester.pumpAndSettle();
    await _expectIndicator(tester, tester.getRect(label));
  });
}

class _Favorites extends Fake implements FavoriteTabBarController {
  final _showMenu = true.obs;

  @override
  bool get showBarsBtn => _showMenu.value;

  @override
  int get index => 0;

  @override
  List<Favcat> get favcatList => const [
    Favcat(favId: 'a', favTitle: 'All'),
    Favcat(favId: '0', favTitle: 'Read'),
    Favcat(favId: '1', favTitle: 'Long middle group'),
    Favcat(favId: 'l', favTitle: 'Local'),
  ];
}

class _Layout extends GetxService implements LayoutServices {
  @override
  bool get isLayoutLarge => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Theme extends GetxService implements ThemeService {
  final _mode = ThemesModeEnum.darkMode.obs;

  @override
  ThemesModeEnum get themeModel => _mode.value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpBar(
  WidgetTester tester, {
  required LinkScrollBarController tabs,
  required List<LinkTabItem> items,
  PageController? pages,
  int initIndex = 0,
  double labelTopPadding = 0,
  double width = 600,
  double textScale = 1,
  EdgeInsetsGeometry contentPadding = EdgeInsets.zero,
  EdgeInsetsGeometry itemPadding = const EdgeInsets.symmetric(horizontal: 10),
}) async {
  await tester.pumpWidget(
    CupertinoApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 240,
              child: Column(
                children: [
                  RepaintBoundary(
                    key: _boundaryKey,
                    child: SizedBox(
                      height: 40,
                      child: LinkScrollBar(
                        controller: tabs,
                        pageController: pages,
                        items: items,
                        initIndex: initIndex,
                        labelTopPadding: labelTopPadding,
                        contentPadding: contentPadding,
                        itemPadding: itemPadding,
                        onItemChange: pages == null
                            ? null
                            : (index) => pages.animateToPage(
                                index,
                                duration: kDuration,
                                curve: Curves.ease,
                              ),
                      ),
                    ),
                  ),
                  if (pages != null)
                    Expanded(
                      child: Listener(
                        onPointerDown: (_) => tabs.enableScrollToItem(),
                        child: PageView.builder(
                          controller: pages,
                          onPageChanged: tabs.scrollToItem,
                          itemCount: items.length,
                          itemBuilder: (_, _) => const SizedBox(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _boundaryKey = ValueKey('tab-bar-boundary');

Future<void> _expectIndicator(WidgetTester tester, Rect label) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  const scale = 2.0;
  final indicator = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: scale);
    try {
      final pixels = (await image.toByteData())!;
      final row = image.height - 1;
      int? first;
      int? last;
      for (var x = 0; x < image.width; x++) {
        final offset = 4 * (row * image.width + x);
        if (pixels.getUint8(offset) == 0 &&
            pixels.getUint8(offset + 1) == 122 &&
            pixels.getUint8(offset + 2) == 255 &&
            pixels.getUint8(offset + 3) == 255) {
          first ??= x;
          last = x;
        }
      }
      expect(first, isNotNull, reason: 'The blue indicator must be visible.');
      return (left: first! / scale, right: (last! + 1) / scale);
    } finally {
      image.dispose();
    }
  });
  expect(indicator, isNotNull);
  final origin = tester.getTopLeft(find.byKey(_boundaryKey)).dx;
  final expected = label.shift(Offset(-origin, 0));
  final reason = 'Blue indicator $indicator, rendered label $expected';
  expect(indicator!.left, closeTo(expected.left, 0.75), reason: reason);
  expect(indicator.right, closeTo(expected.right, 0.75), reason: reason);
}
