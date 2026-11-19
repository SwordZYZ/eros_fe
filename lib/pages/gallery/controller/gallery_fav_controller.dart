import 'package:eros_fe/common/controller/cache_controller.dart';
import 'package:eros_fe/common/service/controller_tag_service.dart';
import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/extension.dart';
import 'package:eros_fe/generated/l10n.dart';
import 'package:eros_fe/network/api.dart';
import 'package:eros_fe/pages/controller/fav_controller.dart';
import 'package:eros_fe/pages/gallery/controller/gallery_page_controller.dart';
import 'package:eros_fe/pages/item/controller/galleryitem_controller.dart';
import 'package:eros_fe/utils/logger.dart';
import 'package:eros_fe/utils/vibrate.dart';
import 'package:get/get.dart';

import 'gallery_page_state.dart';

class GalleryFavController extends GetxController {
  final RxBool _isLoading = false.obs;

  bool get isLoading => _isLoading.value;

  set isLoading(bool value) => _isLoading.value = value;
  String favnote = '';

  final EhSettingService _ehSettingService = Get.find();

  late GalleryPageController _pageController;
  GalleryPageState get _pageState => _pageController.gState;

  final CacheController cacheController = Get.find();

  GalleryItemController get _itemController =>
      Get.find(tag: _pageController.gState.gid);

  bool get isRegItemController =>
      Get.isRegistered<GalleryItemController>(tag: _pageController.gState.gid);

  final FavController favController = Get.find();

  @override
  void onInit() {
    super.onInit();
    _pageController = Get.find(tag: pageCtrlTag);

    _localFav.value = _pageState.localFav;

    // _favTitle 初始化
    if (_pageState.galleryProvider != null &&
        _pageState.galleryProvider?.favTitle != null &&
        _pageState.galleryProvider!.favTitle!.isNotEmpty) {
      _favTitle.value = _pageState.galleryProvider?.favTitle ?? '';
    } else {
      _favTitle.value = localFav ? L10n.of(Get.context!).local_favorite : '';
    }

    // _favcat初始化
    if (_pageState.galleryProvider != null &&
        _pageState.galleryProvider?.favcat != null &&
        _pageState.galleryProvider!.favcat!.isNotEmpty) {
      _favcat.value = _pageState.galleryProvider?.favcat ?? '';
    } else {
      _favcat.value = localFav ? 'l' : '';
    }
  }

  final RxBool _localFav = false.obs;

  bool get localFav => _pageState.localFav;

  final RxString _favTitle = L10n.of(Get.context!).notFav.obs;
  String get favTitle => _favTitle.value;

  final RxString _favcat = ''.obs;
  String get favcat => _favcat.value;

  void setFav(String favcat, String favtitle) {
    final localOnly = favcat.isEmpty && localFav;
    final category = localOnly ? 'l' : favcat;
    final title = localOnly
        ? L10n.current.local_favorite
        : category.isEmpty
        ? ''
        : favtitle;
    _favTitle.value = title;
    _favcat.value = category;

    try {
      if (isRegItemController) {
        _itemController.setFavTitleAndFavcat(
          favTitle: title,
          favcat: category,
        );
      }
    } catch (e, stack) {
      logger.e(
        'Could not update the list favorite',
        error: e,
        stackTrace: stack,
      );
    }
    _pageState.galleryProvider = _pageState.galleryProvider?.copyWith(
      favcat: category.oN,
      favTitle: title.oN,
    );
  }

  bool get isFav => favcat.isNotEmpty || localFav;

  /// 添加到上次
  Future<void> _addToLastFavcat(String lastFavcat) async {
    isLoading = true;

    try {
      final result = await favController.addToLastFavcat(
        _pageState.galleryProvider?.gid ?? '0',
        _pageState.galleryProvider?.token ?? '',
        lastFavcat,
      );
      setFav(result.favId, result.favTitle);
      _removeGalleryCache();
    } catch (e, stack) {
      _showUpdateFailure(e, stack);
    } finally {
      isLoading = false;
    }
  }

  /// 点击收藏按钮处理
  Future<void> tapFav() async {
    if (isLoading) return;

    /// 网络收藏或者本地收藏
    if (favcat.isNotEmpty || _pageState.localFav) {
      logger.d(' del fav');
      await delFav();
    } else {
      logger.d(' add fav');
      final String _lastFavcat = _ehSettingService.lastFavcat;
      logger.d('上次收藏夹 $_lastFavcat');

      // 添加到上次收藏夹
      if (_ehSettingService.isFavLongTap.value &&
          favController.hasOnlineCategory(_lastFavcat)) {
        logger.d('添加到上次收藏夹 $_lastFavcat');
        await _addToLastFavcat(_lastFavcat);
      } else {
        // 手选收藏夹
        logger.d('手选收藏夹');
        await _selectToSave();
      }
    }
  }

  // 选择并收藏
  Future<void> _selectToSave() async {
    isLoading = true;
    try {
      // 进行收藏
      final result = await favController.selectToSave(
        _pageState.galleryProvider?.gid ?? '0',
        _pageState.galleryProvider?.token ?? '',
        oriFavcat: favcat,
        gallery: _pageState.galleryProvider,
      );
      // 收藏后处理
      if (result != null) {
        if (result.favId == 'l') {
          _pageState.localFav = true;
        } else {
          _ehSettingService.lastFavcat = result.favId;
        }
        setFav(result.favId, result.favTitle);
        _removeGalleryCache();
      }
    } catch (e, stack) {
      _showUpdateFailure(e, stack);
    } finally {
      isLoading = false;
    }
  }

  /// 删除收藏
  Future<void> delFav() async {
    isLoading = true;
    try {
      await favController.delFav(
        favcat,
        _pageState.galleryProvider?.gid ?? '0',
        _pageState.galleryProvider?.token ?? '',
      );
      _removeGalleryCache();
      if (favcat == 'l' || favcat.isEmpty) _pageState.localFav = false;
      setFav('', '');
    } catch (e, stack) {
      _showUpdateFailure(e, stack);
    } finally {
      isLoading = false;
    }
  }

  // 长按事件
  Future<void> longTapFav() async {
    if (isLoading) return;

    vibrateUtil.heavy();
    // 手选收藏夹
    await _selectToSave();
  }

  void _showUpdateFailure(Object error, StackTrace stack) {
    if (!isClosed) {
      favController.showUpdateFailure(error, stack);
    }
  }

  void _removeGalleryCache() {
    if (!isRegItemController) {
      return;
    }
    final url = _itemController.galleryProvider.url;
    logger.d('delete cache $url');
    cacheController.clearDioCache(path: '${Api.getBaseUrl()}$url');
  }
}
