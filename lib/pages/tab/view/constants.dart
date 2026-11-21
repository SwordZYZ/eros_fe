import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

const double kNavBarBackButtonTapWidth = 50.0;
const double kNavBarLargeTitleHeightExtension = 52.0;

const double kTopTabbarHeight = kMinInteractiveDimensionCupertino;

const double kHeaderMaxHeight =
    kMinInteractiveDimensionCupertino + kTopTabbarHeight - 2.0;

// Use the same compact gallery header in both iOS window layouts.
double get galleryTabBarTrim =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? 6.0 : 0.0;

double get galleryTabBarHeight => kTopTabbarHeight - galleryTabBarTrim;
double get galleryHeaderMaxHeight => kHeaderMaxHeight - galleryTabBarTrim;

const Color _kDefaultNavBarBorderColor = Color(0x4D000000);
const Border kDefaultNavBarBorder = Border(
  bottom: BorderSide(
    color: _kDefaultNavBarBorderColor,
    width: 0.0, // One physical pixel.
    style: BorderStyle.solid,
  ),
);
