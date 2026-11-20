// Step 4 acceptance entry point. Starts the real app and exercises native ML Kit
// with fixed offline inputs; the production lib/main.dart stays unchanged.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eros_fe/main.dart' as application;
import 'package:eros_fe/route/routes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';

import 'fixtures/ios_mlkit_images.dart';

const _run = String.fromEnvironment('STEP4_RUN', defaultValue: 'manual');
const _timeout = Duration(seconds: 30);

void _result(String name, Object expected, Object actual) {
  final passed = expected == actual;
  debugPrint(
    'STEP4_RESULT ${jsonEncode({'run': _run, 'case': name, 'passed': passed, 'expected': expected, 'actual': actual})}',
  );
  if (!passed) {
    throw StateError('$name: expected $expected, got $actual');
  }
}

bool _hasWidget(String type) {
  var found = false;
  void visit(Element element) {
    if (element.widget.runtimeType.toString() == type) {
      found = true;
    }
    element.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) {
    visit(root);
  }
  return found;
}

Future<void> _waitForWidget(String type) async {
  final deadline = DateTime.now().add(_timeout);
  while (!_hasWidget(type)) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('$type did not appear', _timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  await WidgetsBinding.instance.endOfFrame;
  _result('core_page_$type', true, _hasWidget(type));
}

Future<void> main() async {
  if (!kDebugMode || !Platform.isIOS) {
    throw StateError(
      'This acceptance entry point requires an iOS Debug build.',
    );
  }
  await application.main();
  debugPrint(
    'STEP4_ENV ${jsonEncode({'run': _run, 'dart': Platform.version, 'os': Platform.operatingSystemVersion})}',
  );
  Directory? fixtures;
  BarcodeScanner? scanner;
  LanguageIdentifier? identifier;
  try {
    await _waitForWidget('HomePage');
    fixtures = await Directory.systemTemp.createTemp('eros_mlkit_step4_');
    scanner = BarcodeScanner(
      formats: [BarcodeFormat.qrCode, BarcodeFormat.ean13],
    );
    for (final input in [
      ('qr', qrPngBase64, qrExpected, BarcodeFormat.qrCode),
      ('ean13', ean13PngBase64, ean13Expected, BarcodeFormat.ean13),
    ]) {
      final image = File('${fixtures.path}/${input.$1}.png');
      await image.writeAsBytes(base64Decode(input.$2));
      final barcodes = await scanner
          .processImage(InputImage.fromFile(image))
          .timeout(_timeout);
      final matching = barcodes.where(
        (barcode) => barcode.rawValue == input.$3 && barcode.format == input.$4,
      );
      _result(
        'barcode_${input.$1}',
        input.$3,
        matching.isEmpty
            ? barcodes.map((b) => b.rawValue).join(',')
            : matching.first.rawValue!,
      );
    }
    identifier = LanguageIdentifier(confidenceThreshold: 0.5);
    for (final input in const [
      (
        'en',
        'This is a fixed English sentence for testing language identification on a mobile device.',
      ),
      ('ja', 'これは日本語の文章です。言語識別が正しく動作することを確認しています。'),
      ('zh', '这是一段用于验证语言识别功能的中文文本，我们希望能够准确识别这段文字的语言。'),
    ]) {
      final language = await identifier
          .identifyLanguage(input.$2)
          .timeout(_timeout);
      _result('language_${input.$1}', input.$1, language);
    }
    Get.toNamed<void>(EHRoutes.layoutSetting);
    await _waitForWidget('LayoutSettingPage');
    debugPrint('STEP4_SUMMARY ${jsonEncode({'run': _run, 'passed': true})}');
  } catch (error, stack) {
    debugPrint(
      'STEP4_SUMMARY ${jsonEncode({'run': _run, 'passed': false, 'error': error.toString()})}',
    );
    debugPrintStack(stackTrace: stack);
    rethrow;
  } finally {
    await scanner?.close();
    await identifier?.close();
    await fixtures?.delete(recursive: true);
  }
}
