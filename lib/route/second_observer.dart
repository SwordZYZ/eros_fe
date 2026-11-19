import 'package:flutter/cupertino.dart';

import 'eh_observer.dart';
import 'routes.dart';

class SecondNavigatorObserver extends EhNavigatorObserver {
  // 单例公开访问点
  factory SecondNavigatorObserver() => _sharedInstance();

  // 私有构造函数
  SecondNavigatorObserver._() {
    // 具体初始化代码
  }

  final Stopwatch _sinceGalleryPop = Stopwatch();

  bool consumeStatusBarTapAfterGalleryBack() {
    if (!_sinceGalleryPop.isRunning) {
      return false;
    }
    _sinceGalleryPop.stop();
    // On iPadOS the native event can arrive after the route transition.
    return _sinceGalleryPop.elapsed < const Duration(milliseconds: 650);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == EHRoutes.galleryPage) {
      _sinceGalleryPop
        ..reset()
        ..start();
    }
    super.didPop(route, previousRoute);
  }

  // 静态、同步、私有访问点
  static SecondNavigatorObserver _sharedInstance() {
    _instance ??= SecondNavigatorObserver._();
    return _instance!;
  }

  // 静态私有成员，没有初始化
  static SecondNavigatorObserver? _instance;
}
