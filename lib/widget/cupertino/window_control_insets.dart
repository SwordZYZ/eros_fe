import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WindowControlInsetsScope extends StatefulWidget {
  const WindowControlInsetsScope({super.key, required this.child});

  final Widget child;

  @override
  State<WindowControlInsetsScope> createState() =>
      _WindowControlInsetsScopeState();
}

class _WindowControlInsetsScopeState extends State<WindowControlInsetsScope>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('eros_fe/window_layout');
  static const _startupDisplayWait = Duration(milliseconds: 500);
  static const _startupRetryWindow = Duration(seconds: 2);
  static const _startupRetryDelay = Duration(milliseconds: 100);

  final _supportedPlatform =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  EdgeInsets? _insets;
  int _request = 0;
  Timer? _startupDisplayDeadline;
  Timer? _startupRetryDeadline;
  Timer? _startupRetry;

  @override
  void initState() {
    super.initState();
    if (_supportedPlatform) {
      WidgetsBinding.instance.addObserver(this);
      _startupDisplayDeadline = Timer(_startupDisplayWait, () {
        setState(() => _insets = EdgeInsets.zero);
      });
      _startupRetryDeadline = Timer(_startupRetryWindow, () {
        _startupRetry?.cancel();
      });
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'windowLayoutChanged') {
          unawaited(_refresh());
        }
      });
      unawaited(_refresh());
    }
  }

  @override
  void didChangeMetrics() => unawaited(_refresh());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    _startupRetry?.cancel();
    final request = ++_request;
    Map<String, double>? data;
    var pending = false;
    try {
      data = await _channel.invokeMapMethod<String, double>(
        'windowControlInsets',
      );
      pending = data?.containsKey('pending') ?? false;
    } on MissingPluginException {
      // The channel is only implemented in the iOS runner.
    } on PlatformException {
      pending = true;
    }
    if (!mounted || request != _request) {
      return;
    }
    if (pending) {
      if (_startupRetryDeadline?.isActive == true) {
        _startupRetry = Timer(_startupRetryDelay, () => unawaited(_refresh()));
      }
      return;
    }

    _startupDisplayDeadline?.cancel();
    _startupRetryDeadline?.cancel();
    final insets = EdgeInsets.only(
      left: data?['left'] ?? 0,
      right: data?['right'] ?? 0,
    );
    if (insets != _insets) {
      setState(() => _insets = insets);
    }
  }

  @override
  void dispose() {
    _startupDisplayDeadline?.cancel();
    _startupRetryDeadline?.cancel();
    _startupRetry?.cancel();
    if (_supportedPlatform) {
      WidgetsBinding.instance.removeObserver(this);
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supportedPlatform) {
      return widget.child;
    }

    // Give UIKit time to lay out the window before building interactive routes.
    final insets = _insets;
    if (insets == null) {
      return const SizedBox.expand();
    }
    return _WindowControlInsetsData(insets: insets, child: widget.child);
  }
}

class _WindowControlInsetsData extends InheritedWidget {
  const _WindowControlInsetsData({required this.insets, required super.child});

  final EdgeInsets insets;

  @override
  bool updateShouldNotify(_WindowControlInsetsData oldWidget) =>
      insets != oldWidget.insets;
}

class WindowControlInsetsRegion extends StatelessWidget {
  const WindowControlInsetsRegion({
    super.key,
    required this.leftOffset,
    required this.rightOffset,
    required this.child,
  });

  final double leftOffset;
  final double rightOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final insets = WindowControlInsets.of(context);
    return _WindowControlInsetsData(
      insets: EdgeInsets.only(
        left: math.max(0, insets.left - leftOffset),
        right: math.max(0, insets.right - rightOffset),
      ),
      child: child,
    );
  }
}

class WindowControlInsets extends StatelessWidget {
  const WindowControlInsets({super.key, required this.builder});

  final Widget Function(BuildContext, EdgeInsets) builder;

  static EdgeInsets of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_WindowControlInsetsData>()
          ?.insets ??
      EdgeInsets.zero;

  @override
  Widget build(BuildContext context) => builder(context, of(context));
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
  Widget build(BuildContext context) =>
      bar.leading == null && bar.automaticallyImplyLeading
      ? WindowAwareNavigationPadding(child: bar)
      : bar;
}

class WindowAwareNavigationPadding extends StatelessWidget {
  const WindowAwareNavigationPadding({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route == null ||
        !route.canPop ||
        (route is PageRoute && route.fullscreenDialog)) {
      return child;
    }

    // Cupertino's toolbar applies horizontal safe-area padding to its built-in
    // back button, including the chevron captured for the route transition.
    final insets = WindowControlInsets.of(context);
    final isLtr = Directionality.of(context) == TextDirection.ltr;
    final extra = isLtr
        ? EdgeInsets.only(left: insets.left)
        : EdgeInsets.only(right: insets.right);
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(padding: media.padding + extra),
      child: child,
    );
  }
}
