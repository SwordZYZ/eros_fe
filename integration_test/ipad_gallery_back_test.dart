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
import 'package:eros_fe/pages/tab/view/empty.dart';
import 'package:eros_fe/pages/tab/view/home_page_large.dart';
import 'package:eros_fe/pages/tab/view/resizable_split_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

import '../tool/fixtures/ios_mlkit_images.dart';

const _profileId = 'ipad-gallery-back-fixture';
const _coverUrl = 'https://fixture.invalid/ipad-gallery-back.png';

class _FixtureList extends CustomSubListController {
  _FixtureList(this.items) : super(profileUuid: _profileId);

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

  testWidgets('iPad detail back preserves the left list position', (
    tester,
  ) async {
    await app.main();
    Global.profile = Global.profile.copyWith(
      customTabConfig: const CustomTabConfig(
        profiles: [
          CustomProfile(
            uuid: _profileId,
            name: 'Local galleries',
            listModeValue: 'list',
          ),
        ],
      ).oN,
    );
    Get.find<EhSettingService>().tabletLayoutType = TabletLayout.automatic;
    final items = _seedGalleries();
    Get.lazyPut<CustomSubListController>(
      () => _FixtureList(items),
      tag: _profileId,
    );
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
    expect(find.byType(TabHomeLarge), findsOneWidget);
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
      // On a real iPad the status-bar event arrived about 350 ms after back.
      await tester.pump(const Duration(milliseconds: 350));
      const statusBar = SystemChannels.statusBar;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        statusBar.name,
        statusBar.codec.encodeMethodCall(const MethodCall('handleScrollToTop')),
        null,
      );
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
  });
}
