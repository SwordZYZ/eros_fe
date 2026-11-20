// Host-side Step 5A driver. Uses the pinned Flutter tools' vm_service package.
// Usage: dart --packages=<flutter_tools package_config> tool/ios_baseline_driver.dart
//        <flutter-run.log> <command> <result.json> [key=value ...]
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln(
      'Usage: <Flutter run log> <command> <result.json> [key=value]',
    );
    exitCode = 2;
    return;
  }
  final log = File(args[0]).readAsStringSync();
  final match = RegExp(
    r'A Dart VM Service[^\n]*available at: (http://\S+)',
  ).firstMatch(log);
  if (match == null) throw StateError('No Dart VM Service URL in ${args[0]}');
  final http = Uri.parse(match.group(1)!);
  final ws = http.replace(scheme: 'ws', path: '${http.path}ws');
  final service = await vmServiceConnectUri(ws.toString());
  try {
    final vm = await service.getVM();
    final isolate = vm.isolates!.firstWhere((i) => i.name == 'main');
    final parameters = <String, String>{'command': args[1]};
    for (final pair in args.skip(3)) {
      final split = pair.indexOf('=');
      if (split <= 0) throw ArgumentError('Expected key=value: $pair');
      parameters[pair.substring(0, split)] = pair.substring(split + 1);
    }
    final response = await service
        .callServiceExtension(
          'ext.eros.step5a',
          isolateId: isolate.id,
          args: parameters,
        )
        .timeout(const Duration(seconds: 70));
    final data = response.json!;
    File(
      args[2],
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
    stdout.writeln(
      jsonEncode({
        'command': args[1],
        'route': data['route'],
        'lifecycle': data['lifecycle'],
        'gallery': data['gallery'],
        'torrent': data['torrent'],
        'privacy': data['privacy'],
        'results': (data['events'] as List)
            .where((e) => e['kind'] == 'result')
            .toList(),
      }),
    );
  } finally {
    await service.dispose();
  }
}
