import 'package:eros_fe/route/second_observer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

class SplitLeftScrollScope extends StatefulWidget {
  const SplitLeftScrollScope({super.key, required this.child});

  final Widget child;

  @override
  State<SplitLeftScrollScope> createState() => _SplitLeftScrollScopeState();
}

class _SplitLeftScrollScopeState extends State<SplitLeftScrollScope> {
  final ScrollController _controller = _SplitLeftScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PrimaryScrollController(
      controller: _controller,
      child: widget.child,
    );
  }
}

class _SplitLeftScrollController extends ScrollController {
  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) {
    // UIKit can report a status-bar tap immediately after the right-pane back
    // button. Match CupertinoPageScaffold's status-bar scroll animation.
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        offset == 0.0 &&
        duration == const Duration(milliseconds: 500) &&
        curve == Curves.linearToEaseOut &&
        SecondNavigatorObserver().consumeStatusBarTapAfterGalleryBack()) {
      return Future<void>.value();
    }
    return super.animateTo(offset, duration: duration, curve: curve);
  }
}
