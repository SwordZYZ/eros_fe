import 'package:eros_fe/pages/tab/view/resizable_split_view.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

const _leftKey = ValueKey('left-pane');
const _frame = Duration(milliseconds: 16);
final _handle = find.byKey(ResizableSplitView.handleKey);

Future<void> _pumpSplitView(
  WidgetTester tester,
  ValueNotifier<double> width,
  ValueNotifier<double> proportion,
) {
  return tester.pumpWidget(
    CupertinoApp(
      home: Center(
        child: ListenableBuilder(
          listenable: Listenable.merge([width, proportion]),
          builder: (context, child) => SizedBox(
            width: width.value,
            height: 500,
            child: ResizableSplitView(
              proportion: proportion.value,
              onProportionChanged: (value) => proportion.value = value,
              left: const SizedBox.expand(key: _leftKey),
              right: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    ),
  );
}

double _leftWidth(WidgetTester tester) =>
    tester.getSize(find.byKey(_leftKey)).width;

void main() {
  testWidgets('divider tracks the drag while the handle animates', (
    tester,
  ) async {
    await _pumpSplitView(tester, ValueNotifier(800), ValueNotifier(0.5));
    final restingHeight = tester.getSize(_handle).height;
    final gesture = await tester.startGesture(tester.getCenter(_handle));
    await gesture.moveBy(const Offset(35, 0));
    await tester.pump(_frame);
    expect(_leftWidth(tester), 435);

    // Both updates must count, even when delivered in the same frame.
    await gesture.moveBy(const Offset(6, 0));
    await gesture.moveBy(const Offset(9, 0));
    await tester.pump(_frame);
    expect(_leftWidth(tester), 450);
    await tester.pump(const Duration(milliseconds: 500));
    expect(_leftWidth(tester), 450);
    expect(tester.getSize(_handle).height, greaterThan(restingHeight));

    await gesture.moveBy(const Offset(-25, 0));
    await tester.pump(_frame);
    expect(_leftWidth(tester), 425);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_leftWidth(tester), 425);
    expect(tester.getSize(_handle).height, restingHeight);
  });

  testWidgets('both limits clamp and allow immediate reversal', (tester) async {
    await _pumpSplitView(tester, ValueNotifier(800), ValueNotifier(0.5));
    final gesture = await tester.startGesture(tester.getCenter(_handle));
    await gesture.moveBy(const Offset(110, 0));
    await tester.pump(_frame);
    expect(_leftWidth(tester), 480);
    await gesture.moveBy(const Offset(-10, 0));
    await tester.pump(_frame);
    expect(_leftWidth(tester), 470);
    await gesture.moveBy(const Offset(-170, 0));
    await tester.pump(_frame);
    expect(_leftWidth(tester), 320);
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump(_frame);
    expect(_leftWidth(tester), 330);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(_leftWidth(tester), 330);
    expect(tester.getSize(_handle).height, 55);
  });

  testWidgets(
    'near 640 the drag remains finite and a narrow view keeps ratio',
    (tester) async {
      final width = ValueNotifier(642.0);
      final proportion = ValueNotifier(0.25);
      await _pumpSplitView(tester, width, proportion);
      expect(_leftWidth(tester), 320.5);
      await tester.drag(_handle, const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(_leftWidth(tester), 322);
      expect(proportion.value, 1);

      proportion.value = 0.25;
      for (final narrowWidth in [640.0, 600.0]) {
        width.value = narrowWidth;
        await tester.pump();
        await tester.drag(_handle, const Offset(30, 0));
        await tester.pumpAndSettle();
        expect(_leftWidth(tester), narrowWidth / 2);
        expect(proportion.value, 0.25);
      }
      width.value = 800;
      await tester.pump();
      expect(_leftWidth(tester), 360);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a non-finite proportion from an older layout recovers', (
    tester,
  ) async {
    final proportion = ValueNotifier(double.nan);
    await _pumpSplitView(tester, ValueNotifier(800), proportion);
    expect(_leftWidth(tester), 320);
    await tester.drag(_handle, const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(_leftWidth(tester), 380);
    expect(proportion.value, 0.375);
  });
}
