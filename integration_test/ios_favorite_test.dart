import 'dart:convert';

import 'package:eros_fe/common/controller/gallerycache_controller.dart';
import 'package:eros_fe/common/controller/user_controller.dart';
import 'package:eros_fe/common/global.dart';
import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/generated/l10n.dart';
import 'package:eros_fe/main.dart' as app;
import 'package:eros_fe/models/base/eh_models.dart';
import 'package:eros_fe/network/app_dio/pdio.dart';
import 'package:eros_fe/pages/controller/favorite_sel_controller.dart';
import 'package:eros_fe/pages/gallery/controller/gallery_fav_controller.dart';
import 'package:eros_fe/pages/gallery/controller/gallery_page_controller.dart';
import 'package:eros_fe/pages/gallery/controller/gallery_page_state.dart';
import 'package:eros_fe/pages/gallery/gallery_repository.dart';
import 'package:eros_fe/pages/gallery/view/gallery_favcat.dart';
import 'package:eros_fe/pages/item/controller/galleryitem_controller.dart';
import 'package:eros_fe/pages/tab/view/home_page_large.dart';
import 'package:eros_fe/route/navigator_util.dart';
import 'package:eros_fe/widget/image/eh_cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:oktoast/oktoast.dart';

import '../test/fixtures/favorite_server.dart';
import '../tool/fixtures/ios_mlkit_images.dart';

void main() {
  // Navigator cancels the held pointer when the long press opens a dialog.
  // Let the live binding deliver that cancellation to the recognizer.
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.shouldPropagateDevicePointerEvents = true;

  testWidgets('iPad gallery confirms favorite changes before updating UI', (
    tester,
  ) async {
    final server = await FavoriteServer.start();
    addTearDown(server.close);
    final previousConfig = globalDioConfig;
    globalDioConfig = DioHttpConfig(baseUrl: server.origin);
    addTearDown(() => globalDioConfig = previousConfig);
    await app.main();

    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) {
          return;
        }
      }
      expect(finder, findsWidgets);
    }

    await waitFor(find.byType(TabHomeLarge));
    globalDioConfig = DioHttpConfig(baseUrl: server.origin);
    final user = Get.find<UserController>();
    final previousUser = user.user;
    // A test-only identity for the loopback server. No login or profile write.
    user.user = previousUser.value
        .copyWith(memberId: '123'.oN, passHash: 'fixture'.oN)
        .obs;
    addTearDown(() => user.user = previousUser);
    final settings = Get.find<EhSettingService>();
    final selector = Get.find<FavoriteSelectorController>();
    final gallery = await _seedGallery();
    server.cover = gallery.imgUrl;
    GalleryItemController.bindToCard(gallery);
    expect(Get.find<GalleryItemController>(tag: gallery.gid).favCat, isEmpty);
    GalleryItemController.bindToCard(
      gallery.copyWith(favcat: '2'.oN, favTitle: 'Category 2'.oN),
    );
    expect(Get.find<GalleryItemController>(tag: gallery.gid).favCat, '2');
    GalleryItemController.bindToCard(gallery);
    expect(Get.find<GalleryItemController>(tag: gallery.gid).favCat, isEmpty);
    NavigatorUtil.goGalleryPage(galleryProvider: gallery);
    final button = find.byType(GalleryFavButton);
    await waitFor(button);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.ensureVisible(button);
    expect(tester.takeException(), isNull);
    final controller = Get.find<GalleryFavController>(tag: gallery.gid);
    Map<String, int?> counts() => {
      for (final fav in selector.favcatList) fav.favId: fav.totNum,
    };

    final before = counts();
    final emptyHeart = find.descendant(
      of: button,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is FaIcon && widget.icon == FontAwesomeIcons.heart.data,
      ),
    );
    final filledHeart = find.descendant(
      of: button,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is FaIcon && widget.icon == FontAwesomeIcons.solidHeart.data,
      ),
    );
    final failureToast = find.text(L10n.current.favorite_update_failed);
    Future<void> clearFailureToast() async {
      dismissAllToast();
      await tester.pumpAndSettle();
      expect(failureToast, findsNothing);
    }

    settings.isFavLongTap.value = true;
    settings.lastFavcat = '0';
    for (final mode in [FavoriteWrite.disconnect, FavoriteWrite.reject]) {
      server.response = mode;
      await tester.tap(button);
      await waitFor(failureToast);
      expect(controller.isLoading, isFalse);
      expect(emptyHeart, findsOneWidget);
      expect(counts(), before);
      expect(settings.lastFavcat, '0');
      expect(server.category, isNull);
      await clearFailureToast();
    }

    server.response = FavoriteWrite.accept;
    await tester.tap(button);
    await waitFor(filledHeart);
    expect(controller.favcat, '0');
    expect(server.category, '0');
    expect(counts()['0'], (before['0'] ?? 0) + 1);

    settings.isFavPicker.value = true;
    Future<void> chooseCategory() async {
      await waitFor(filledHeart.hitTestable());
      expect(controller.isLoading, isFalse);
      await tester.longPress(filledHeart);
      final picker = find.byType(CupertinoPicker).hitTestable();
      await waitFor(picker);
      final scroller = tester.widget<CupertinoPicker>(picker).scrollController!;
      scroller.jumpToItem(2);
      await tester.pump();
      final confirm = find.text(L10n.current.ok).hitTestable();
      await waitFor(confirm);
      await tester.tap(confirm);
    }

    server.response = FavoriteWrite.reject;
    final afterAdd = counts();
    await chooseCategory();
    await waitFor(failureToast);
    expect(server.writes.last['favcat'], '2');
    expect(controller.favcat, '0');
    expect(counts(), afterAdd);
    expect(server.category, '0');
    await clearFailureToast();

    server.response = FavoriteWrite.accept;
    await chooseCategory();
    await waitFor(filledHeart);
    expect(server.writes.last['favcat'], '2');
    expect(controller.favcat, '2');
    expect(server.category, '2');
    expect(counts()['0'], (afterAdd['0'] ?? 0) - 1);
    expect(counts()['2'], (afterAdd['2'] ?? 0) + 1);

    server.response = FavoriteWrite.reject;
    final afterMove = counts();
    await tester.tap(button);
    await waitFor(failureToast);
    expect(filledHeart, findsOneWidget);
    expect(counts(), afterMove);
    expect(server.category, '2');
    await clearFailureToast();

    server.response = FavoriteWrite.accept;
    await tester.tap(button);
    await waitFor(emptyHeart);
    expect(server.category, isNull);
    expect(counts()['2'], (afterMove['2'] ?? 0) - 1);

    settings.isFavLongTap.value = false;
    settings.isFavPicker.value = false;
    await tester.tap(button);
    final category = find
        .byWidgetPredicate(
          (widget) => widget is FavCatAddListItem && widget.favcat == '1',
        )
        .hitTestable();
    await waitFor(category);
    await tester.tap(category);
    await waitFor(filledHeart);
    expect(controller.favcat, '1');
    expect(server.category, '1');
    await tester.tap(button);
    await waitFor(emptyHeart);
    expect(server.category, isNull);

    final writeCount = server.writes.length;
    await tester.tap(button);
    final local = find.text(L10n.current.local_favorite);
    await waitFor(local);
    await tester.tap(local.last);
    await waitFor(filledHeart);
    expect(controller.favcat, 'l');
    await tester.tap(button);
    await waitFor(emptyHeart);
    expect(server.writes.length, writeCount);
    expect(tester.takeException(), isNull);

    final detail = Get.find<GalleryPageController>(tag: gallery.gid);
    settings.lastFavcat = '9';
    server.category = '2';
    await detail.handOnRefresh();
    await waitFor(filledHeart);
    expect(controller.favcat, '2');
    expect(settings.lastFavcat, '9');
    server.category = null;
    await detail.handOnRefresh();
    await waitFor(emptyHeart);
    expect(controller.favcat, isEmpty);
    expect(settings.lastFavcat, '9');
    expect(server.writes.length, writeCount);
    expect(tester.takeException(), isNull);

    // Task 3 tracks the detail route's double disposal. Leave the borrowed
    // controller with its route owner during this test's automatic unmount.
    detail.scrollController?.removeListener(detail.scrollControllerLister);
    detail.scrollController = null;
    debugPrint(
      'IOS_FAVORITE button, category, count and server assertions PASS',
    );
  });
}

Future<GalleryProvider> _seedGallery() async {
  const gid = '950000005';
  const token = 'favoritefixture';
  const cover = 'https://fixture.invalid/favorite-cover.png';
  const image = GalleryImage(
    ser: 0,
    gid: gid,
    token: token,
    thumbUrl: cover,
    imageUrl: cover,
    thumbWidth: 264,
    thumbHeight: 264,
    href: 'https://fixture.invalid/s/favorite/1',
  );
  await imageCacheManager().putFile(
    cover,
    base64Decode(qrPngBase64),
    fileExtension: 'png',
    maxAge: const Duration(days: 1),
  );
  const gallery = GalleryProvider(
    gid: gid,
    token: token,
    url: '/g/$gid/$token/',
    imgUrl: cover,
    imgUrlL: cover,
    imgWidth: 264,
    imgHeight: 264,
    englishTitle: 'Favorite test gallery',
    japaneseTitle: '',
    category: 'misc',
    uploader: 'Test',
    posted: '2026-01-01 00:00',
    postTime: '2026-01-01 00:00',
    language: 'English',
    filecount: '1',
    rating: 4,
    ratingCount: '1',
    torrentcount: '0',
    filesize: 1048576,
    filesizeText: '1.00 MiB',
    visible: 'Yes',
    favoritedCount: '0',
    tagGroup: [],
    galleryComment: [],
    galleryImages: [image],
    chapter: [],
  );
  Get.find<GalleryCacheController>().addGalleryPageState(
    GalleryPageState()
      ..galleryRepository = GalleryRepository(item: gallery)
      ..galleryProvider = gallery
      ..firstPageImage = [image]
      ..images.add(image)
      ..enableRead = true
      ..currentImagePage = 0,
  );
  return gallery;
}
