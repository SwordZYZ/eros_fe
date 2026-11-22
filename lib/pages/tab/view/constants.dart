import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

const double kNavBarBackButtonTapWidth = 50.0;
const double kNavBarLargeTitleHeightExtension = 52.0;

const double kTopTabbarHeight = kMinInteractiveDimensionCupertino;

const double kHeaderMaxHeight =
    kMinInteractiveDimensionCupertino + kTopTabbarHeight - 2.0;

// Use the same compact group header for Gallery and Favorites on iOS.
double get groupTabBarTrim =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS ? 6.0 : 0.0;

double get groupTabBarHeight => kTopTabbarHeight - groupTabBarTrim;
double get groupHeaderMaxHeight => kHeaderMaxHeight - groupTabBarTrim;

const Color _kDefaultNavBarBorderColor = Color(0x4D000000);
const Border kDefaultNavBarBorder = Border(
  bottom: BorderSide(
    color: _kDefaultNavBarBorderColor,
    width: 0.0, // One physical pixel.
    style: BorderStyle.solid,
  ),
);
