import 'package:flutter/cupertino.dart';

class SplitLeftScrollScope extends StatefulWidget {
  const SplitLeftScrollScope({super.key, required this.child});

  final Widget child;

  static Widget pageScaffold(
    BuildContext context, {
    ObstructingPreferredSizeWidget? navigationBar,
    required Widget child,
  }) {
    if (context.findAncestorWidgetOfExactType<SplitLeftScrollScope>() == null) {
      return CupertinoPageScaffold(navigationBar: navigationBar, child: child);
    }

    final controller = PrimaryScrollController.of(context);
    // The list and its explicit scroll actions share this controller. Keep it
    // below the scaffold so a system status-bar tap cannot scroll the list.
    return PrimaryScrollController.none(
      child: CupertinoPageScaffold(
        navigationBar: navigationBar,
        child: PrimaryScrollController(controller: controller, child: child),
      ),
    );
  }

  @override
  State<SplitLeftScrollScope> createState() => _SplitLeftScrollScopeState();
}

class _SplitLeftScrollScopeState extends State<SplitLeftScrollScope> {
  final ScrollController _controller = ScrollController();

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
