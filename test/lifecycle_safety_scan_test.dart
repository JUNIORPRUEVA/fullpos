import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('No await->setState without mounted guard (heuristic scan)', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: 'Missing lib/ directory');

    final awaitRegex = RegExp(r'\bawait\b');
    final setStateRegex = RegExp(r'\bsetState\s*\(');
    final mountedRegex = RegExp(r'\bmounted\b');
    final functionStartRegex = RegExp(r'^\s*(Future<|Future|void|Widget)\b.*\(');

    const window = 30;
    final issues = <String>[];

    for (final entity in libDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.dart')) continue;
      // Contains StatefulBuilder-local `setState` calls (not `State.setState`).
      if (entity.path.endsWith('refund_reason_dialog.dart')) {
        continue;
      }
      if (entity.path.endsWith('.g.dart') ||
          entity.path.endsWith('.freezed.dart') ||
          entity.path.endsWith('.gen.dart')) {
        continue;
      }

      final content = utf8.decode(entity.readAsBytesSync(), allowMalformed: true);
      final lines = const LineSplitter().convert(content);

      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//')) continue;
        if (!awaitRegex.hasMatch(line)) continue;

        for (var j = i + 1; j < lines.length && j <= i + window; j++) {
          final nextLine = lines[j];
          final nextTrimmed = nextLine.trimLeft();
          if (nextTrimmed.startsWith('//')) continue;

          // If we see an explicit mounted guard anywhere before setState,
          // assume the author handled lifecycle safety.
          if (mountedRegex.hasMatch(nextLine)) break;

          // Avoid cross-function false positives: stop scanning when we likely
          // hit a new function signature.
          if (functionStartRegex.hasMatch(nextTrimmed) &&
              (nextTrimmed.contains('{') || nextTrimmed.contains('=>'))) {
            break;
          }

          if (setStateRegex.hasMatch(nextLine)) {
            issues.add('${entity.path}:${j + 1} setState after await@${i + 1}');
            break;
          }
        }
      }
    }

    expect(issues, isEmpty, reason: issues.join('\n'));
  });
}
