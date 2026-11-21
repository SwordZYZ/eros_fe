import 'package:eros_fe/widget/cupertino/window_control_insets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the leading back button follows the native window inset', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    const channel = MethodChannel('eros_fe/window_layout');
    Map<String, double>? insets;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'windowControlInsets');
      return insets;
    });
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      messenger.setMockMethodCallHandler(channel, null);
    });

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      CupertinoApp(
        navigatorKey: navigator,
        home: const CupertinoPageScaffold(child: SizedBox.expand()),
      ),
    );

    Future<void> open(ObstructingPreferredSizeWidget bar) async {
      navigator.currentState!.push<void>(
        CupertinoPageRoute(
          builder: (_) => CupertinoPageScaffold(
            navigationBar: bar,
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    const bar = CupertinoNavigationBar(middle: Text('Settings'));
    final back = find.byType(CupertinoNavigationBarBackButton).hitTestable();
    final windowBack = find.byType(WindowAwareBackButton);
    await open(bar);
    final originalLeft = tester.getTopLeft(back).dx;
    await tester.tap(back);
    await tester.pumpAndSettle();

    await open(bar.withWindowAwareBackButton());
    expect(windowBack, findsNothing);
    expect(tester.getTopLeft(back).dx, originalLeft);

    insets = {'left': 48, 'right': 0};
    tester.view.physicalSize = const Size(540, 800);
    await tester.pumpAndSettle();
    expect(windowBack, findsOneWidget);
    expect(tester.getTopLeft(back).dx - tester.getTopLeft(windowBack).dx, 48);

    insets = {'left': 0, 'right': 0};
    tester.view.physicalSize = const Size(390, 800);
    await tester.pumpAndSettle();
    expect(windowBack, findsNothing);
    expect(tester.getTopLeft(back).dx, originalLeft);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(back, findsNothing);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
