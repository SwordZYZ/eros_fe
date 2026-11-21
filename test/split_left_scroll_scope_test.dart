import 'package:eros_fe/widget/cupertino/split_left_scroll_scope.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'the left list ignores status-bar taps and can still scroll explicitly',
    (tester) async {
      late ScrollController controller;
      await tester.pumpWidget(
        CupertinoApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(top: 24)),
            child: child!,
          ),
          home: SplitLeftScrollScope(
            child: Builder(
              builder: (context) {
                controller = PrimaryScrollController.of(context);
                return SplitLeftScrollScope.pageScaffold(
                  context,
                  child: ListView.builder(
                    itemCount: 40,
                    itemExtent: 80,
                    itemBuilder: (_, index) => Text('Gallery $index'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      expect(
        PrimaryScrollController.maybeOf(
          tester.element(find.byType(CupertinoPageScaffold)),
        ),
        isNull,
      );

      controller.jumpTo(600);
      await tester.pump();
      const channel = SystemChannels.statusBar;
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(const MethodCall('handleScrollToTop')),
        null,
      );
      await tester.pumpAndSettle();
      expect(controller.offset, 600);

      final animation = controller.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.ease,
      );
      await tester.pumpAndSettle();
      await animation;
      expect(controller.offset, 0);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );
}
