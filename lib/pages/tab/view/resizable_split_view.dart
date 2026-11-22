import 'package:eros_fe/widget/cupertino/window_control_insets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

class ResizableSplitView extends StatefulWidget {
  const ResizableSplitView({
    super.key,
    required this.proportion,
    required this.onProportionChanged,
    required this.left,
    required this.right,
  });

  static const handleKey = ValueKey('split-view-handle');

  final double proportion;
  final ValueChanged<double> onProportionChanged;
  final Widget left;
  final Widget right;

  @override
  State<ResizableSplitView> createState() => _ResizableSplitViewState();
}

class _ResizableSplitViewState extends State<ResizableSplitView> {
  static const _minPaneWidth = 320.0;
  static const _dividerWidth = 0.6;
  bool _pressed = false;
  double _dragProportion = 0;

  void _setPressed(bool pressed) => setState(() => _pressed = pressed);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final travel = width - 2 * _minPaneWidth;
        final proportion = widget.proportion.isNaN
            ? 0.0
            : widget.proportion.clamp(0.0, 1.0);
        final leftWidth = travel > 0
            ? _minPaneWidth + travel * proportion
            : width / 2;

        return Row(
          textDirection: TextDirection.ltr,
          children: [
            SizedBox(
              width: leftWidth,
              child: WindowControlInsetsRegion(
                leftOffset: 0,
                rightOffset: width - leftWidth,
                child: ClipRect(child: widget.left),
              ),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Row(
                    textDirection: TextDirection.ltr,
                    children: [
                      Container(
                        width: _dividerWidth,
                        color: CupertinoDynamicColor.resolve(
                          CupertinoColors.systemGrey4,
                          context,
                        ),
                      ),
                      Expanded(
                        child: WindowControlInsetsRegion(
                          leftOffset: leftWidth + _dividerWidth,
                          rightOffset: 0,
                          child: ClipRect(child: widget.right),
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    key: ResizableSplitView.handleKey,
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onHorizontalDragDown: (_) => _setPressed(true),
                    onHorizontalDragStart: (_) => _dragProportion = proportion,
                    onHorizontalDragEnd: (_) => _setPressed(false),
                    onHorizontalDragCancel: () => _setPressed(false),
                    onHorizontalDragUpdate: (details) {
                      if (travel <= 0) {
                        return;
                      }
                      // Several pointer updates can arrive before the next layout.
                      _dragProportion =
                          (_dragProportion + details.delta.dx / travel).clamp(
                            0.0,
                            1.0,
                          );
                      widget.onProportionChanged(_dragProportion);
                    },
                    child: AnimatedContainer(
                      decoration: BoxDecoration(
                        color: CupertinoDynamicColor.resolve(
                          CupertinoColors.systemGrey,
                          context,
                        ).withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(_pressed ? 5 : 1.5),
                      ),
                      margin: EdgeInsets.only(
                        left: _pressed ? 5 : 2,
                        right: _pressed ? 5 : 20,
                      ),
                      height: _pressed ? 80 : 55,
                      width: _pressed ? 10 : 3,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.ease,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
