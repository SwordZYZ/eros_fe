import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WindowAwareBackButton extends StatelessWidget {
  const WindowAwareBackButton._({
    required this.startInset,
    this.previousPageTitle,
  });

  final double startInset;
  final String? previousPageTitle;

  static WindowAwareBackButton? leadingFor(
    BuildContext context,
    EdgeInsets insets, {
    String? previousPageTitle,
  }) {
    final route = ModalRoute.of(context);
    if (route == null ||
        !route.canPop ||
        (route is PageRoute && route.fullscreenDialog)) {
      return null;
    }

    final startInset = Directionality.of(context) == TextDirection.ltr
        ? insets.left
        : insets.right;
    return startInset > 0
        ? WindowAwareBackButton._(
            startInset: startInset,
            previousPageTitle: previousPageTitle,
          )
        : null;
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.only(start: startInset),
    child: CupertinoNavigationBarBackButton(
      previousPageTitle: previousPageTitle,
      // The navigation-bar transition also builds this in a Hero overlay.
      onPressed: () => Navigator.maybePop(context),
    ),
  );
}

extension WindowAwareNavigationBar on CupertinoNavigationBar {
  ObstructingPreferredSizeWidget withWindowAwareBackButton() =>
      _WindowAwareNavigationBar(this);
}

class _WindowAwareNavigationBar extends StatelessWidget
    implements ObstructingPreferredSizeWidget {
  const _WindowAwareNavigationBar(this.bar);

  final CupertinoNavigationBar bar;

  @override
  Size get preferredSize => bar.preferredSize;

  @override
  bool shouldFullyObstruct(BuildContext context) =>
      bar.shouldFullyObstruct(context);

  @override
  Widget build(BuildContext context) {
    if (bar.leading != null || !bar.automaticallyImplyLeading) {
      return bar;
    }

    return WindowControlInsets(
      builder: (context, insets) {
        final leading = WindowAwareBackButton.leadingFor(
          context,
          insets,
          previousPageTitle: bar.previousPageTitle,
        );
        if (leading == null) {
          return bar;
        }

        return CupertinoNavigationBar(
          key: bar.key,
          leading: leading,
          automaticallyImplyMiddle: bar.automaticallyImplyMiddle,
          previousPageTitle: bar.previousPageTitle,
          middle: bar.middle,
          trailing: bar.trailing,
          border: bar.border,
          backgroundColor: bar.backgroundColor,
          automaticBackgroundVisibility: bar.automaticBackgroundVisibility,
          enableBackgroundFilterBlur: bar.enableBackgroundFilterBlur,
          brightness: bar.brightness,
          padding: bar.padding,
          transitionBetweenRoutes: bar.transitionBetweenRoutes,
          heroTag: bar.heroTag,
          bottom: bar.bottom,
        );
      },
    );
  }
}

class WindowControlInsets extends StatefulWidget {
  const WindowControlInsets({super.key, required this.builder});

  final Widget Function(BuildContext, EdgeInsets) builder;

  @override
  State<WindowControlInsets> createState() => _WindowControlInsetsState();
}

class _WindowControlInsetsState extends State<WindowControlInsets> {
  static const _channel = MethodChannel('eros_fe/window_layout');
  Future<Map<String, double>?>? _insets;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      // UIKit calculates the extra inset for the current window geometry.
      MediaQuery.sizeOf(context);
      MediaQuery.viewPaddingOf(context);
      _insets = _channel.invokeMapMethod<String, double>('windowControlInsets');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _insets,
      builder: (context, snapshot) => widget.builder(
        context,
        EdgeInsets.only(
          left: snapshot.data?['left'] ?? 0,
          right: snapshot.data?['right'] ?? 0,
        ),
      ),
    );
  }
}
