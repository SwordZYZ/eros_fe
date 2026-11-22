import 'dart:async';

import 'package:eros_fe/pages/tab/view/resizable_split_view.dart';
import 'package:eros_fe/widget/cupertino/window_control_insets.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _channel = MethodChannel('eros_fe/window_layout');
const _ipad = TargetPlatformVariant({TargetPlatform.iOS});
const _groupList = ValueKey('group-list');
const _groupEditor = ValueKey('group-editor');

void main() {
  testWidgets(
    'waits for the window before exposing full-width and split routes',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      Map<String, double>? nativeInsets = {'pending': 1.0};
      var requests = 0;
      messenger.setMockMethodCallHandler(_channel, (call) async {
        expect(call.method, 'windowControlInsets');
        requests++;
        return nativeInsets;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

      final root = GlobalKey<NavigatorState>();
      const left = ValueKey('left');
      const right = ValueKey('right');
      final leftLeading = _insetProbe(left);
      final rightLeading = _insetProbe(right);
      await tester.pumpWidget(
        WindowControlInsetsScope(
          child: CupertinoApp(
            navigatorKey: root,
            home: ResizableSplitView(
              proportion: 0.5,
              onProportionChanged: (_) {},
              left: leftLeading,
              right: rightLeading,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(left), findsNothing);
      expect(find.byKey(right), findsNothing);
      expect(requests, 1);

      Future<void> publishGeometry(double left, double right) async {
        nativeInsets = {'left': left, 'right': right};
        await _notifyWindowLayoutChanged(messenger);
        await tester.pump();
      }

      await publishGeometry(48, 24);
      expect(_insetsAt(tester, left), const EdgeInsets.only(left: 48));
      expect(_insetsAt(tester, right), const EdgeInsets.only(right: 24));
      expect(requests, 2);

      const fullWidth = ValueKey('full-width');
      root.currentState!.push<void>(
        CupertinoPageRoute(builder: (_) => _insetProbe(fullWidth)),
      );
      await tester.pumpAndSettle();
      expect(
        _insetsAt(tester, fullWidth),
        const EdgeInsets.only(left: 48, right: 24),
      );
      expect(requests, 2);

      await publishGeometry(70, 0);
      expect(_insetsAt(tester, fullWidth), const EdgeInsets.only(left: 70));
      expect(requests, 3);
      root.currentState!.pop();
      await tester.pumpAndSettle();
      expect(_insetsAt(tester, left), const EdgeInsets.only(left: 70));
      expect(_insetsAt(tester, right), EdgeInsets.zero);

      nativeInsets = {'left': 36.0, 'right': 0.0};
      tester.view.physicalSize = const Size(720, 600);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(_insetsAt(tester, left), const EdgeInsets.only(left: 36));
      expect(_insetsAt(tester, right), EdgeInsets.zero);

      await publishGeometry(0, 0);
      expect(_insetsAt(tester, left), EdgeInsets.zero);
      expect(_insetsAt(tester, right), EdgeInsets.zero);
    },
    variant: _ipad,
  );

  testWidgets('retries pending startup geometry without a notification', (
    tester,
  ) async {
    const toolbar = ValueKey('toolbar');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var requests = 0;
    messenger.setMockMethodCallHandler(_channel, (_) async {
      requests++;
      if (requests == 1) {
        return {'pending': 1.0};
      }
      if (requests == 2) {
        throw PlatformException(code: 'temporarily-unavailable');
      }
      return {'left': 48.0};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await tester.pumpWidget(
      WindowControlInsetsScope(child: _insetProbe(toolbar)),
    );
    expect(find.byKey(toolbar), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(requests, 2);
    expect(find.byKey(toolbar), findsNothing);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(requests, 3);
    expect(_insetsAt(tester, toolbar), const EdgeInsets.only(left: 48));

    await tester.pump(const Duration(seconds: 1));
    expect(requests, 3);
  }, variant: _ipad);

  testWidgets('recovers avoidance after fallback without a window event', (
    tester,
  ) async {
    const toolbar = ValueKey('toolbar');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var nativeInsets = {'pending': 1.0};
    var requests = 0;
    messenger.setMockMethodCallHandler(_channel, (_) async {
      requests++;
      return nativeInsets;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await tester.pumpWidget(
      WindowControlInsetsScope(child: _insetProbe(toolbar)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(_insetsAt(tester, toolbar), EdgeInsets.zero);
    final toolbarElement = tester.element(find.byKey(toolbar));

    await tester.pump(const Duration(milliseconds: 150));
    expect(_insetsAt(tester, toolbar), EdgeInsets.zero);
    nativeInsets = {'left': 48.0};
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    expect(_insetsAt(tester, toolbar), const EdgeInsets.only(left: 48));
    expect(tester.element(find.byKey(toolbar)), same(toolbarElement));

    final recoveredRequests = requests;
    await tester.pump(const Duration(seconds: 2));
    expect(requests, recoveredRequests);
  }, variant: _ipad);

  testWidgets('bounds startup retries and accepts a later window update', (
    tester,
  ) async {
    const toolbar = ValueKey('toolbar');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var nativeInsets = {'pending': 1.0};
    var requests = 0;
    messenger.setMockMethodCallHandler(_channel, (_) async {
      requests++;
      return nativeInsets;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await tester.pumpWidget(
      WindowControlInsetsScope(child: _insetProbe(toolbar)),
    );
    await tester.pump(const Duration(milliseconds: 499));
    expect(find.byKey(toolbar), findsNothing);
    expect(requests, 5);

    await tester.pump(const Duration(milliseconds: 1));
    expect(_insetsAt(tester, toolbar), EdgeInsets.zero);
    final toolbarElement = tester.element(find.byKey(toolbar));
    expect(requests, 6);
    await tester.pump(const Duration(milliseconds: 1499));
    expect(requests, 20);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(requests, 20);
    expect(_insetsAt(tester, toolbar), EdgeInsets.zero);

    nativeInsets = {'left': 48.0};
    await _notifyWindowLayoutChanged(messenger);
    await tester.pump();
    expect(_insetsAt(tester, toolbar), const EdgeInsets.only(left: 48));
    expect(tester.element(find.byKey(toolbar)), same(toolbarElement));

    nativeInsets = {'pending': 1.0};
    await _notifyWindowLayoutChanged(messenger);
    await tester.pump(const Duration(seconds: 1));
    expect(_insetsAt(tester, toolbar), const EdgeInsets.only(left: 48));
    expect(requests, 22);
  }, variant: _ipad);

  testWidgets('a missing startup reply cannot keep the app hidden', (
    tester,
  ) async {
    const toolbar = ValueKey('toolbar');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final reply = Completer<Map<String, double>>();
    messenger.setMockMethodCallHandler(_channel, (_) => reply.future);
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    await tester.pumpWidget(
      WindowControlInsetsScope(child: _insetProbe(toolbar)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(_insetsAt(tester, toolbar), EdgeInsets.zero);

    reply.complete({'left': 48.0});
    await tester.pump();
    await tester.pump();
    expect(_insetsAt(tester, toolbar), const EdgeInsets.only(left: 48));
  }, variant: _ipad);

  testWidgets('uses the same chevron position throughout push and pop', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      _channel,
      (_) async => {'left': 48.0, 'right': 0.0},
    );
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));

    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      WindowControlInsetsScope(
        child: CupertinoApp(
          navigatorKey: navigator,
          home: const CupertinoPageScaffold(child: SizedBox.expand()),
        ),
      ),
    );
    await tester.pump();

    void push(Key key) {
      navigator.currentState!.push<void>(
        CupertinoPageRoute(
          builder: (_) => CupertinoPageScaffold(
            key: key,
            navigationBar: CupertinoNavigationBar(
              middle: Text(key.toString()),
              // The editor and its parent can have different trailing padding.
              padding: key == _groupEditor
                  ? const EdgeInsetsDirectional.only(end: 16)
                  : null,
            ).withWindowAwareBackButton(),
            child: const SizedBox.expand(),
          ),
        ),
      );
    }

    final chevrons = find.byElementPredicate((element) {
      if (element.widget.key != StandardComponentType.backButton.key) {
        return false;
      }
      // Cupertino keeps the source and destination bars laid out but hidden
      // while their chevrons are drawn by the Hero overlay.
      var visible = true;
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        if (widget is Visibility && !widget.visible) {
          visible = false;
        }
        return visible;
      });
      return visible;
    });
    void expectChevronPosition() {
      expect(chevrons, findsWidgets);
      for (final chevron in chevrons.evaluate()) {
        expect(
          tester.getTopLeft(find.byWidget(chevron.widget)).dx,
          closeTo(48 + 8, 0.5),
        );
      }
    }

    push(_groupList);
    await tester.pumpAndSettle();
    expectChevronPosition();

    Future<void> checkTransition() async {
      await tester.pump();
      for (var frame = 0; frame < 23; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expectChevronPosition();
      }
      await tester.pumpAndSettle();
      expectChevronPosition();
    }

    push(_groupEditor);
    await checkTransition();
    expect(find.byKey(_groupEditor), findsOneWidget);

    await tester.tap(
      find.byType(CupertinoNavigationBarBackButton).hitTestable(),
    );
    await checkTransition();
    expect(find.byKey(_groupEditor), findsNothing);
    expect(find.byKey(_groupList), findsOneWidget);
  }, variant: _ipad);
}

Widget _insetProbe(Key key) => WindowControlInsets(
  builder: (_, insets) =>
      Padding(key: key, padding: insets, child: const SizedBox.expand()),
);

EdgeInsetsGeometry _insetsAt(WidgetTester tester, Key key) =>
    tester.widget<Padding>(find.byKey(key)).padding;

Future<void> _notifyWindowLayoutChanged(TestDefaultBinaryMessenger messenger) =>
    messenger.handlePlatformMessage(
      _channel.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('windowLayoutChanged'),
      ),
      (_) {},
    );
