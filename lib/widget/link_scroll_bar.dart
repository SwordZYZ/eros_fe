import 'package:eros_fe/index.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

const kDuration = Duration(milliseconds: 300);
const double kDefIndicatorHeight = 4;

final LinkScrollBarController _defaultLinkScrollBarController =
    LinkScrollBarController();

class LinkTabItem {
  LinkTabItem({
    required this.title,
    this.icon,
    this.iconColor,
    this.actinos,
  });

  final String title;
  final Object? icon;
  final Color? iconColor;
  final List<LinkTabItemAction>? actinos;
}

class LinkTabItemAction {
  LinkTabItemAction({
    required this.actinoText,
    this.icon,
    this.onTap,
    this.color,
  });
  final String actinoText;
  final Object? icon;
  final VoidCallback? onTap;
  final Color? color;
}

class LinkScrollBar extends StatefulWidget {
  LinkScrollBar({
    super.key,
    LinkScrollBarController? controller,
    this.pageController,
    required this.items,
    required this.initIndex,
    this.indicatorHeight = kDefIndicatorHeight,
    this.labelTopPadding = 0,
    this.contentPadding = EdgeInsets.zero,
    this.itemPadding = const EdgeInsets.only(left: 10, right: 10),
    this.onItemChange,
  }) : controller = controller ?? _defaultLinkScrollBarController;

  final List<LinkTabItem> items;
  final int initIndex;
  final double indicatorHeight;
  final double labelTopPadding;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsetsGeometry itemPadding;
  final LinkScrollBarController controller;
  final ValueChanged<int>? onItemChange;
  final PageController? pageController;

  @override
  State<LinkScrollBar> createState() => _LinkScrollBarState();
}

class _LinkScrollBarState extends State<LinkScrollBar>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _contentKey = GlobalKey();
  final _tabKeys = <_TabKeys>[];
  late final ValueChanged<int> _scrollToItemCallback = _selectItem;
  late final AnimationController _selectionAnimation;
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initIndex;
    _selectionAnimation = AnimationController.unbounded(
      vsync: this,
      value: _selectedIndex.toDouble(),
    );
    _updateTabKeys();
    widget.controller.scrollToItemCall = _scrollToItemCallback;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _centerItem(_selectedIndex);
      }
    });
  }

  @override
  void didUpdateWidget(LinkScrollBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTabKeys();
    if (oldWidget.pageController != null && widget.pageController == null) {
      _selectionAnimation.value = _selectedIndex.toDouble();
    }
    if (oldWidget.controller != widget.controller) {
      _unbindController(oldWidget.controller);
      widget.controller.scrollToItemCall = _scrollToItemCallback;
    }
  }

  @override
  void dispose() {
    _unbindController(widget.controller);
    _selectionAnimation.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _unbindController(LinkScrollBarController controller) {
    if (controller.scrollToItemCall == _scrollToItemCallback) {
      controller.scrollToItemCall = null;
    }
  }

  void _updateTabKeys() {
    final count = widget.items.length;
    if (_tabKeys.length > count) {
      _tabKeys.removeRange(count, _tabKeys.length);
    }
    while (_tabKeys.length < count) {
      _tabKeys.add(_TabKeys());
    }
  }

  void _selectItem(int index) {
    if (_tabKeys.isEmpty) {
      return;
    }
    index = index.clamp(0, _tabKeys.length - 1);
    setState(() => _selectedIndex = index);
    if (widget.pageController == null) {
      _selectionAnimation.animateTo(
        index.toDouble(),
        duration: kDuration,
        curve: Curves.ease,
      );
    }
    _centerItem(index);
  }

  void _centerItem(int index) {
    if (_tabKeys.isEmpty || !_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (!position.hasContentDimensions) {
      return;
    }

    final item = _tabKeys[index.clamp(0, _tabKeys.length - 1)]
        .item
        .currentContext
        ?.findRenderObject();
    if (item is! RenderBox || !item.hasSize) {
      return;
    }
    final target = RenderAbstractViewport.of(item)
        .getOffsetToReveal(item, 0.5)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) {
      _scrollController.animateTo(
        target,
        duration: kDuration,
        curve: Curves.ease,
      );
    }
  }

  double _indicatorPage() {
    final controller = widget.pageController;
    if (controller == null) {
      return _selectionAnimation.value;
    }
    if (controller.positions.length == 1 &&
        controller.position.hasContentDimensions) {
      return controller.page ?? _selectedIndex.toDouble();
    }
    return _selectedIndex.toDouble();
  }

  Widget _buildBarItem(int index) {
    final item = widget.items[index];
    final keys = _tabKeys[index];
    final selected = index == _selectedIndex.clamp(0, _tabKeys.length - 1);
    return Builder(
      builder: (context) => GestureDetector(
        key: keys.item,
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (widget.pageController != null) {
            widget.controller.disableScrollToItem();
          }
          _selectItem(index);
          widget.onItemChange?.call(index);
        },
        onLongPress: () async {
          final actions = item.actinos;
          if (actions == null) {
            return;
          }
          vibrateUtil.medium();
          logger.d('onLongPress $index');
          await showItemAttach(
            targetContext: context,
            margin: const EdgeInsets.only(
              left: 10,
              right: 10,
              top: 10,
              bottom: 40,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: actions
                    .map(
                      (action) => GestureDetector(
                        onTap: () {
                          SmartDialog.dismiss();
                          action.onTap?.call();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (action.icon != null)
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: _buildLinkIcon(
                                    action.icon,
                                    size: 16,
                                    color:
                                        action.color ??
                                        CupertinoDynamicColor.resolve(
                                          CupertinoColors.label,
                                          context,
                                        ),
                                  ),
                                ),
                              Text(
                                action.actinoText,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: action.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        },
        child: Padding(
          padding: widget.itemPadding.add(
            EdgeInsets.only(top: widget.labelTopPadding),
          ),
          child: Column(
            children: [
              const Spacer(),
              Row(
                children: [
                  if (item.icon != null) ...[
                    _buildLinkIcon(item.icon, size: 16),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    item.title,
                    key: keys.label,
                    style: TextStyle(
                      fontSize: 14,
                      color: CupertinoDynamicColor.resolve(
                        selected
                            ? CupertinoColors.activeBlue
                            : CupertinoColors.label,
                        context,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      padding: widget.contentPadding,
      child: CustomPaint(
        key: _contentKey,
        foregroundPainter: _TabIndicatorPainter(
          contentKey: _contentKey,
          tabs: _tabKeys,
          height: widget.indicatorHeight,
          currentPage: _indicatorPage,
          repaint: widget.pageController ?? _selectionAnimation,
        ),
        child: Column(
          children: [
            Expanded(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.items.length, _buildBarItem),
              ),
            ),
            SizedBox(height: widget.indicatorHeight),
          ],
        ),
      ),
    );
  }
}

class _TabKeys {
  final item = GlobalKey();
  final label = GlobalKey();
}

class _TabIndicatorPainter extends CustomPainter {
  _TabIndicatorPainter({
    required this.contentKey,
    required this.tabs,
    required this.height,
    required this.currentPage,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GlobalKey contentKey;
  final List<_TabKeys> tabs;
  final double height;
  final double Function() currentPage;
  final _paint = Paint()..color = CupertinoColors.activeBlue;

  Rect? _labelBounds(int index, RenderBox content, Size size) {
    final label = tabs[index].label.currentContext?.findRenderObject();
    if (label is! RenderBox || !label.hasSize) {
      return null;
    }

    final left = label.localToGlobal(Offset.zero, ancestor: content).dx;
    return Rect.fromLTWH(left, size.height - height, label.size.width, height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (tabs.isEmpty) {
      return;
    }
    final content = contentKey.currentContext?.findRenderObject();
    if (content is! RenderBox) {
      return;
    }

    // Read the text bounds after layout, in the same coordinates as the bar.
    final page = currentPage().clamp(0.0, (tabs.length - 1).toDouble());
    final index = page.floor();
    final start = _labelBounds(index, content, size);
    if (start == null) {
      return;
    }
    final end = page == index
        ? start
        : _labelBounds(page.ceil(), content, size) ?? start;
    final bounds = Rect.lerp(start, end, page - index)!;
    final radius = Radius.circular(height * 3 / 4);
    canvas.drawRRect(
      RRect.fromRectAndCorners(bounds, topLeft: radius, topRight: radius),
      _paint,
    );
  }

  @override
  bool shouldRepaint(covariant _TabIndicatorPainter oldDelegate) => true;
}

Widget _buildLinkIcon(
  Object? icon, {
  required double size,
  Color? color,
}) {
  if (icon is FaIconData) {
    return FaIcon(icon, size: size, color: color);
  }
  return Icon(icon as IconData?, size: size, color: color);
}

class FooSliverPersistentHeaderDelegate extends SliverPersistentHeaderDelegate {
  FooSliverPersistentHeaderDelegate({
    required this.builder,
    required this.maxHeight,
    required this.minHeight,
  });

  final double minHeight;
  final double maxHeight;

  final Widget Function(
      BuildContext context, double shrinkOffset, bool overlapsContent) builder;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      builder(context, shrinkOffset, overlapsContent);

  @override
  double get maxExtent => maxHeight;

  @override
  double get minExtent => minHeight;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return minHeight != oldDelegate.minExtent ||
        maxHeight != oldDelegate.maxExtent;
  }
}

Future showItemAttach({
  required BuildContext targetContext,
  required Widget child,
  String? tag,
  VoidCallback? onDismiss,
  double? width,
  EdgeInsetsGeometry? margin,
  AlignmentGeometry? alignmentTemp,
}) async {
  await SmartDialog.showAttach(
    highlightBuilder: (Offset targetOffset, Size targetSize) {
      return Positioned(
        left: targetOffset.dx,
        top: targetOffset.dy + 2,
        child: Container(
          height: targetSize.height - 4,
          width: targetSize.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
          ),
        ),
      );
    },
    tag: tag,
    keepSingle: true,
    targetContext: targetContext,
    onDismiss: onDismiss,
    builder: (BuildContext context) {
      return SafeArea(
        top: false,
        bottom: false,
        child: Container(
          width: width,
          margin: margin,
          // constraints: const BoxConstraints(maxHeight: 300, minHeight: 50),
          // decoration: BoxDecoration(
          //   borderRadius: BorderRadius.circular(16),
          //   boxShadow: [
          //     BoxShadow(
          //       color: Colors.black.withOpacity(0.2),
          //       offset: const Offset(0, 0),
          //       blurRadius: 10, //阴影模糊程度
          //       spreadRadius: 1, //阴影扩散程度
          //     ),
          //   ],
          // ),
          // color: CupertinoColors.systemGrey5,
          child: CupertinoPopupSurface(
            child: child,
          ),
        ),
      );
    },
  );
}
