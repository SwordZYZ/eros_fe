import 'package:eros_fe/models/gallery_torrent.dart';
import 'package:eros_fe/pages/gallery/view/torrent_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the red magnet shares its row as text from the button rect', (
    tester,
  ) async {
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'com.apple.UIKit.activity.CopyToPasteboard';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    const first = TorrentItem(
      torrent: GalleryTorrent(hash: '1111111111111111111111111111111111111111'),
      token: '1',
    );
    const selected = TorrentItem(
      torrent: GalleryTorrent(hash: '0123456789abcdef0123456789abcdef01234567'),
      token: '2',
    );
    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 340,
              child: CupertinoAlertDialog(
                content: Column(children: [first, selected]),
              ),
            ),
          ),
        ),
      ),
    );

    final button = find.descendant(
      of: find.byWidget(selected),
      matching: find.byType(CupertinoButton),
    );
    final rect = tester.getRect(button);
    expect(rect.isEmpty, isFalse);
    expect(rect.left, greaterThan(400));
    await tester.tap(button);
    await tester.pumpAndSettle();

    final call = calls.single;
    expect(call.method, 'share');
    expect(call.arguments, {
      'text': 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
      'originX': rect.left,
      'originY': rect.top,
      'originWidth': rect.width,
      'originHeight': rect.height,
    });
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS}));
}
