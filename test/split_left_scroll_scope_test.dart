import 'package:eros_fe/route/routes.dart';
import 'package:eros_fe/route/second_observer.dart';
import 'package:eros_fe/widget/cupertino/split_left_scroll_scope.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'left pane ignores the status-bar scroll immediately after gallery back',
    (tester) async {
      await tester.pumpWidget(
        CupertinoApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(top: 24)),
            child: child!,
          ),
          home: SplitLeftScrollScope(
            child: CupertinoPageScaffold(
              child: ListView.builder(
                itemCount: 40,
                itemExtent: 80,
                itemBuilder: (_, index) => Text('Gallery $index'),
              ),
            ),
          ),
        ),
      );
      final controller = PrimaryScrollController.of(
        tester.element(find.byType(CupertinoPageScaffold)),
      );

      Future<void> sendStatusBarTap() async {
        const channel = SystemChannels.statusBar;
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          channel.codec.encodeMethodCall(const MethodCall('handleScrollToTop')),
          null,
        );
        await tester.pumpAndSettle();
      }

      controller.jumpTo(600);
      await tester.pump();
      await sendStatusBarTap();
      expect(controller.offset, 0);

      controller.jumpTo(600);
      await tester.pump();
      final poppedRoute = CupertinoPageRoute<void>(
        settings: const RouteSettings(name: EHRoutes.galleryPage),
        builder: (_) => const SizedBox.shrink(),
      );
      SecondNavigatorObserver().didPop(poppedRoute, null);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)),
      );
      await sendStatusBarTap();
      expect(controller.offset, 600);

      final animation = controller.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.ease,
      );
      await tester.pumpAndSettle();
      await animation;
      expect(controller.offset, 0);

      controller.jumpTo(600);
      await tester.pump();
      await sendStatusBarTap();
      expect(controller.offset, 0);
    },
    variant: const TargetPlatformVariant(<TargetPlatform>{TargetPlatform.iOS}),
  );
}
