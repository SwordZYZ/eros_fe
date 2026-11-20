import 'package:eros_fe/common/service/layout_service.dart';
import 'package:eros_fe/main.dart' as app;
import 'package:eros_fe/pages/tab/view/resizable_split_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iPad divider tracks touch and preserves both navigators', (
    tester,
  ) async {
    await app.main();
    final handle = find.byKey(ResizableSplitView.handleKey);
    for (
      var attempt = 0;
      attempt < 150 && handle.evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(handle, findsOneWidget, reason: 'requires an iPad in split layout');

    final layout = Get.find<LayoutServices>();
    layout.sideProportion = 0.5;
    final left = Get.nestedKey(1)!.currentState!;
    final right = Get.nestedKey(2)!.currentState!;
    final testPage = find.byKey(const ValueKey('right-test-content'));
    right.push<void>(
      CupertinoPageRoute(
        builder: (_) => const CupertinoPageScaffold(
          child: Center(
            child: Text('Detail', key: ValueKey('right-test-content')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(testPage, findsOneWidget);

    // Measure the leading edge. The handle's own animated width can change.
    double dividerPosition() => tester.getTopLeft(handle).dx;

    final start = dividerPosition();
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(dividerPosition(), closeTo(start + 40, 1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(dividerPosition(), closeTo(start + 40, 1));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(dividerPosition(), closeTo(start + 10, 1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(dividerPosition(), closeTo(start + 10, 1));

    expect(Get.nestedKey(1)!.currentState, same(left));
    expect(Get.nestedKey(2)!.currentState, same(right));
    expect(testPage, findsOneWidget);
    right.pop();
    await tester.pumpAndSettle();
    expect(testPage, findsNothing);
    expect(dividerPosition(), closeTo(start + 10, 1));
    expect(tester.takeException(), isNull);
  });
}
