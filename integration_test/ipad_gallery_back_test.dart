import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:eros_fe/common/controller/gallerycache_controller.dart';
import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/index.dart';
import 'package:eros_fe/main.dart' as app;
import 'package:eros_fe/pages/gallery/controller/gallery_page_state.dart';
import 'package:eros_fe/pages/gallery/gallery_repository.dart';
import 'package:eros_fe/pages/gallery/view/sliver/gallery_page.dart';
import 'package:eros_fe/pages/gallery/view/sliver/slivers.dart';
import 'package:eros_fe/pages/item/gallery_item.dart';
import 'package:eros_fe/pages/tab/controller/group/custom_sublist_controller.dart';
import 'package:eros_fe/pages/tab/controller/group/custom_tabbar_controller.dart';
import 'package:eros_fe/pages/tab/controller/tabhome_controller.dart';
import 'package:eros_fe/pages/tab/view/empty.dart';
import 'package:eros_fe/pages/tab/view/history_page.dart';
import 'package:eros_fe/pages/tab/view/home_page_large.dart';
import 'package:eros_fe/pages/tab/view/resizable_split_view.dart';
import 'package:eros_fe/pages/tab/view/tabbar/custom_profiles_page.dart';
import 'package:eros_fe/pages/tab/view/tabbar/custom_tabbar_page.dart';
import 'package:eros_fe/widget/cupertino/window_control_insets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

import '../tool/fixtures/ios_mlkit_images.dart';

const _profileId = 'ipad-gallery-back-fixture';
const _coverUrl = 'https://fixture.invalid/ipad-gallery-back.png';
const _coldNarrow = bool.fromEnvironment('IOS_IPAD_GROUP_COLD_NARROW');

class _FixtureList extends CustomSubListController {
  _FixtureList(this.items, {String profileId = _profileId})
    : super(profileUuid: profileId);

  final List<GalleryProvider> items;

  @override
  Future<void> firstLoad() async {
    change(items, status: RxStatus.success());
  }
}

List<GalleryProvider> _seedGalleries() {
  final cache = Get.find<GalleryCacheController>();
  return List.generate(40, (index) {
    final gid = '${950003000 + index}';
    final image = GalleryImage(
      ser: 0,
      gid: gid,
      token: 'localfixture',
      thumbUrl: _coverUrl,
      imageUrl: _coverUrl,
      thumbWidth: 264,
      thumbHeight: 264,
      href: 'https://fixture.invalid/preview/$gid',
    );
    final gallery = GalleryProvider(
      gid: gid,
      token: 'localfixture',
      url: '/g/$gid/localfixture/',
      imgUrl: _coverUrl,
      imgUrlL: _coverUrl,
      imgWidth: 264,
      imgHeight: 264,
      japaneseTitle: '日本語のテスト $index',
      englishTitle: 'Local gallery $index',
      category: 'misc',
      uploader: 'Local fixture',
      posted: '2026-01-01 00:00',
      language: 'English',
      filecount: '1',
      rating: 4,
      ratingCount: '1',
      torrentcount: '0',
      filesizeText: '1 MiB',
      visible: 'Yes',
      favoritedCount: '0',
      tagGroup: const [],
      galleryComment: const [],
      galleryImages: [image],
    );
    cache.addGalleryPageState(
      GalleryPageState()
        ..galleryProvider = gallery
        ..firstPageImage = [image]
        ..currentImagePage = 0
        ..enableRead = true
        ..images.add(image)
        ..galleryRepository = GalleryRepository(
          item: gallery,
          tabTag: _profileId,
        ),
    );
    return gallery;
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  const testName = _coldNarrow
      ? 'iPad single-column launch switches configured groups'
      : 'iPad detail back preserves the left list position';
  testWidgets(testName, (tester) async {
    final physicalSize = tester.view.physicalSize;
    if (_coldNarrow) {
      final pixelRatio = tester.view.devicePixelRatio;
      tester.view.physicalSize = Size(540 * pixelRatio, 800 * pixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
    } else if (physicalSize.width < physicalSize.height) {
      tester.view.physicalSize = Size(physicalSize.height, physicalSize.width);
      addTearDown(tester.view.resetPhysicalSize);
    }
    await app.main();
    final groups = List.generate(
      5,
      (index) => CustomProfile(
        uuid: index == 0 ? _profileId : 'ipad-gallery-back-fixture-$index',
        name: '测试 ${index + 1}',
        listModeValue: 'list',
      ),
    );
    Global.profile = Global.profile.copyWith(
      customTabConfig: CustomTabConfig(profiles: groups).oN,
    );
    final settings = Get.find<EhSettingService>();
    settings.tabletLayoutType = TabletLayout.automatic;
    final showJapanese = settings.jpnTitleInGalleryPage;
    settings.jpnTitleInGalleryPage = true;
    addTearDown(() => settings.jpnTitleInGalleryPage = showJapanese);
    final items = _seedGalleries();
    for (final group in groups) {
      Get.lazyPut<CustomSubListController>(
        () => _FixtureList(
          group.uuid == _profileId ? items : [],
          profileId: group.uuid,
        ),
        tag: group.uuid,
      );
    }
    final cover = MemoryImage(base64Decode(qrPngBase64));
    final painting = PaintingBinding.instance;
    painting.imageCache.putIfAbsent(
      const CachedNetworkImageProvider(_coverUrl),
      () => cover.loadImage(cover, painting.instantiateImageCodecWithSize),
    );

    // FlutterSliverList does not expose its children through the onstage
    // visitor. Hit testing below still filters out clipped and cached cards.
    final cards = find.byType(GalleryItemWidget, skipOffstage: false);
    final gallery = find.byType(GalleryPage);
    final back = find.descendant(
      of: gallery,
      matching: find.byType(CupertinoNavigationBarBackButton),
    );
    final detailActions = find.descendant(
      of: gallery,
      matching: find.byType(GalleryActions),
    );
    for (
      var frame = 0;
      frame < 150 && cards.hitTestable().evaluate().isEmpty;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(cards, findsWidgets, reason: 'local list cards finished rendering');
    expect(cards.hitTestable(), findsWidgets);

    Future<void> settleNavigation() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
    }

    Future<void> waitForDetail() async {
      await settleNavigation();
      for (
        var frame = 0;
        frame < 50 && detailActions.evaluate().isEmpty;
        frame++
      ) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(detailActions, findsOneWidget);
      expect(back, findsOneWidget);
      final original = find.descendant(
        of: gallery,
        matching: find.textContaining('Local gallery'),
      );
      final japanese = find.descendant(
        of: gallery,
        matching: find.textContaining('日本語のテスト'),
      );
      expect(original.hitTestable(), findsOneWidget);
      expect(japanese.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomLeft(original).dy,
        lessThan(tester.getTopLeft(japanese).dy),
      );
    }

    Finder cardFinder(Element card) => find.byElementPredicate(
      (element) => identical(element, card),
      skipOffstage: false,
    );

    List<Element> visibleCards() =>
        cards.hitTestable().evaluate().toList()..sort((a, b) {
          double top(Element element) =>
              tester.getTopLeft(cardFinder(element)).dy;
          return top(a).compareTo(top(b));
        });

    ({String? gid, double y, double pixels}) location() {
      final card = visibleCards().first;
      return (
        gid: (card.widget as GalleryItemWidget).galleryProvider.gid,
        y: tester.getTopLeft(cardFinder(card)).dy,
        pixels: Scrollable.of(card, axis: Axis.vertical).position.pixels,
      );
    }

    expect(tester.takeException(), isNull, reason: 'fixture startup');

    final split = find.byType(TabHomeLarge);
    final insets = await const MethodChannel(
      'eros_fe/window_layout',
    ).invokeMapMethod<String, double>('windowControlInsets');
    expect(insets, isNotNull);
    Finder groupLabelFor(String label) => find.descendant(
      of: find.byType(CustomTabBar),
      matching: find.text(label),
    );
    final groupLabel = groupLabelFor(groups.first.name);
    final indicator = find.descendant(
      of: find.byType(CustomTabBar),
      matching: find.byType(TitleIndicator),
    );
    final groupMenu = find.descendant(
      of: find.byType(CustomTabBar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is FaIcon && widget.icon == FontAwesomeIcons.bars.data,
      ),
    );
    ({double gap, double labelOffset}) checkGroupLayout() {
      final row = tester.getRect(find.byType(CustomTabBar));
      final label = tester.getRect(groupLabel);
      final line = tester.getRect(indicator);
      expect(row.height, closeTo(38, 0.5));
      expect(line.bottom, closeTo(row.bottom, 0.5));
      expect(line.top - label.bottom, inInclusiveRange(0, 9));
      expect(tester.getCenter(groupMenu).dy, closeTo(label.center.dy, 1));
      return (
        gap: line.top - label.bottom,
        labelOffset: label.center.dy - row.top,
      );
    }

    Future<void> checkGroupSwitching(String layout) async {
      final controller = Get.find<CustomTabbarController>();
      for (final group in [...groups.skip(1), groups.first]) {
        final label = groupLabelFor(group.name);
        final item = find.ancestor(
          of: label,
          matching: find.byType(InnerLinkTabItem),
        );
        expect(label.hitTestable(), findsOneWidget, reason: layout);
        await tester.tap(label);
        await tester.pump(const Duration(milliseconds: 500));
        for (
          var frame = 0;
          frame < 15 && controller.currProfileUuid != group.uuid;
          frame++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          tester.widget<InnerLinkTabItem>(item).selected,
          isTrue,
          reason: '$layout: ${group.name} label became selected',
        );
        expect(
          controller.currProfileUuid,
          group.uuid,
          reason:
              '$layout: switched to ${group.name}, attached positions: '
              '${controller.pageController.positions.length}',
        );
        await settleNavigation();
      }
      debugPrint('IPAD_GROUP_SWITCH $layout: ${groups.length} groups passed');
    }

    Future<void> checkGroupManagementBack(String layout) async {
      expect(groupMenu.hitTestable(), findsOneWidget, reason: layout);
      await tester.tap(groupMenu);
      await settleNavigation();
      final profiles = find.byType(CustomProfilesPage);
      expect(profiles, findsOneWidget, reason: layout);
      final windowBack = find.descendant(
        of: profiles,
        matching: find.byType(WindowAwareBackButton),
      );
      final profilesBack = find.descendant(
        of: profiles,
        matching: find.byType(CupertinoNavigationBarBackButton),
      );
      expect(profilesBack.hitTestable(), findsOneWidget, reason: layout);
      final leftInset = insets!['left']!;
      expect(windowBack, leftInset > 0 ? findsOneWidget : findsNothing);
      if (leftInset > 0) {
        expect(
          tester.getTopLeft(profilesBack).dx - tester.getTopLeft(windowBack).dx,
          closeTo(leftInset, 0.5),
        );
      }
      await tester.tap(profilesBack.hitTestable());
      await settleNavigation();
      expect(profiles, findsNothing, reason: layout);
      debugPrint('IPAD_GROUP_MANAGEMENT_BACK $layout: passed');
    }

    if (_coldNarrow) {
      expect(split, findsNothing);
      checkGroupLayout();
      const layout = '540 pt single-column cold launch';
      await checkGroupManagementBack(layout);
      await checkGroupSwitching(layout);
      expect(tester.takeException(), isNull);
      return;
    }

    expect(split, findsOneWidget);
    final wideGroup = checkGroupLayout();
    final toolbarTop = MediaQuery.paddingOf(tester.element(split)).top;
    final toolbar = find.descendant(
      of: find.byType(CustomTabbarList),
      matching: find.byType(CupertinoNavigationBar),
    );
    Finder inToolbar(Finder child) =>
        find.descendant(of: toolbar, matching: child);
    final title = inToolbar(find.text(L10n.current.tab_gallery));
    final search = inToolbar(find.byIcon(CupertinoIcons.search));
    final jump = inToolbar(find.byIcon(CupertinoIcons.arrow_uturn_down_circle));
    expect(
      MediaQuery.paddingOf(tester.element(toolbar)).top,
      closeTo(toolbarTop, 0.5),
    );
    expect(
      tester.getCenter(groupLabel).dy,
      greaterThan(tester.getCenter(title).dy),
    );

    void checkLeading(Finder icon) {
      expect(icon.hitTestable(), findsOneWidget);
      expect(
        tester.getTopLeft(icon).dx,
        greaterThanOrEqualTo(insets!['left']! + 8),
      );
      expect(tester.getTopLeft(icon).dy, greaterThanOrEqualTo(toolbarTop));
      for (final item in [title, search, jump]) {
        expect(
          tester.getCenter(icon).dy,
          closeTo(tester.getCenter(item).dy, 1),
        );
      }
    }

    final tabMap = Get.find<TabHomeController>().tabMap;
    final previousTabs = Map<String, bool>.of(tabMap);
    addTearDown(() => tabMap.assignAll(previousTabs));
    tabMap.assignAll({for (final tab in previousTabs.keys) tab: true});
    tabMap[EHRoutes.history] = false;
    await settleNavigation();
    checkLeading(
      inToolbar(
        find.byWidgetPredicate(
          (widget) =>
              widget is FaIcon && widget.icon == FontAwesomeIcons.history.data,
        ),
      ),
    );
    tabMap[EHRoutes.download] = false;
    await settleNavigation();
    checkLeading(inToolbar(find.byIcon(CupertinoIcons.ellipsis_circle)));
    tabMap.assignAll(previousTabs);
    await settleNavigation();

    Future<void> sendStatusBarTap() async {
      const channel = SystemChannels.statusBar;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('handleScrollToTop')),
        null,
      );
    }

    final failures = <String>[];
    for (final replace in [false, true]) {
      final path = replace
          ? 'drag divider, replace detail then back'
          : 'open detail then back';
      await tester.drag(cardFinder(visibleCards().last), const Offset(0, -850));
      await settleNavigation();
      final before = location();
      expect(before.pixels, greaterThan(0));

      final visible = visibleCards();
      expect(visible.length, greaterThan(1));
      final firstGid =
          (visible[1].widget as GalleryItemWidget).galleryProvider.gid;
      await tester.tap(cardFinder(visible[1]));
      await waitForDetail();
      expect(tester.getTopLeft(back).dy, greaterThanOrEqualTo(toolbarTop));
      var expectedAfterBack = before;
      if (replace) {
        final firstDetail = tester.element(gallery);
        final handle = find.byKey(ResizableSplitView.handleKey);
        expect(handle, findsOneWidget);
        final initialX = tester.getTopLeft(handle).dx;
        final drag = await tester.startGesture(tester.getCenter(handle));
        await drag.moveBy(const Offset(40, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.getTopLeft(handle).dx, closeTo(initialX + 40, 1));
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.getTopLeft(handle).dx, closeTo(initialX + 40, 1));
        await drag.up();
        await settleNavigation();
        expect(tester.getTopLeft(handle).dx, closeTo(initialX + 40, 1));
        expect(tester.element(gallery), same(firstDetail));
        expectedAfterBack = location();
        expect(expectedAfterBack.pixels, closeTo(before.pixels, 1));
        final replacement = visibleCards().firstWhere(
          (card) =>
              (card.widget as GalleryItemWidget).galleryProvider.gid !=
              firstGid,
        );
        await tester.tap(cardFinder(replacement));
        await waitForDetail();
        expect(tester.element(gallery), isNot(same(firstDetail)));
        final replacementError = tester.takeException();
        if (replacementError != null) {
          failures.add('$path during replacement: $replacementError');
        }
      }

      await tester.tap(back);
      await tester.pump();
      // The native event arrived after the back transition on the test iPad.
      await tester.pump(const Duration(milliseconds: 350));
      await sendStatusBarTap();
      await settleNavigation();
      expect(gallery, findsNothing);
      expect(find.byType(EmptyPage), findsOneWidget);
      final after = location();
      final backError = tester.takeException();
      final positionMatches =
          expectedAfterBack.gid == after.gid &&
          (expectedAfterBack.y - after.y).abs() < 1 &&
          (expectedAfterBack.pixels - after.pixels).abs() < 1;
      debugPrint(
        'IPAD_GALLERY_BACK $path before=$before after=$after error=$backError',
      );
      if (!positionMatches) {
        failures.add('$path position: $expectedAfterBack -> $after');
      }
      if (backError != null) {
        failures.add('$path after back: $backError');
      }
    }
    expect(failures, isEmpty);
    final middle = location();
    Get.toNamed<void>(EHRoutes.history, id: 1);
    await settleNavigation();
    final history = find.byType(HistoryTab);
    final historyBack = find.descendant(
      of: history,
      matching: find.byType(CupertinoNavigationBarBackButton),
    );
    expect(historyBack.hitTestable(), findsOneWidget);
    await tester.tap(historyBack.hitTestable());
    await settleNavigation();
    await sendStatusBarTap();
    await settleNavigation();
    expect(history, findsNothing);
    expect(location(), middle);

    await tester.tap(title);
    await settleNavigation();
    expect(location().pixels, closeTo(0, 1));
    expect(tester.takeException(), isNull);

    await checkGroupManagementBack('split view');

    // A narrow iPad window uses the full-width details route.
    final wideSize = tester.view.physicalSize;
    final pixelRatio = tester.view.devicePixelRatio;
    tester.view.physicalSize = Size(540 * pixelRatio, 800 * pixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await settleNavigation();
    expect(split, findsNothing);
    final narrowGroup = checkGroupLayout();
    expect(narrowGroup.gap, closeTo(wideGroup.gap, 0.5));
    expect(narrowGroup.labelOffset, closeTo(wideGroup.labelOffset, 0.5));
    await tester.tap(cardFinder(visibleCards().first));
    await settleNavigation();
    final windowBack = find.descendant(
      of: gallery,
      matching: find.byType(WindowAwareBackButton),
    );
    expect(back.hitTestable(), findsOneWidget);
    final leftInset = insets!['left']!;
    expect(windowBack, leftInset > 0 ? findsOneWidget : findsNothing);
    if (leftInset > 0) {
      expect(
        tester.getTopLeft(back).dx - tester.getTopLeft(windowBack).dx,
        closeTo(leftInset, 0.5),
      );
    }
    await tester.tap(back);
    await settleNavigation();
    expect(gallery, findsNothing);
    tester.view.physicalSize = wideSize;
    await settleNavigation();
    expect(split, findsOneWidget);
    final expandedGroup = checkGroupLayout();
    expect(expandedGroup.gap, closeTo(wideGroup.gap, 0.5));
    expect(expandedGroup.labelOffset, closeTo(wideGroup.labelOffset, 0.5));
    await checkGroupManagementBack('expanded split view');
    await checkGroupSwitching('expanded split view');
    expect(tester.takeException(), isNull);
  });
}
