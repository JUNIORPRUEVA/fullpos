import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';

class ThemeAudit {
  ThemeAudit._();

  static void run() {
    if (!kDebugMode) return;

    final root = Directory.current;
    final libDir = Directory('${root.path}${Platform.pathSeparator}lib');
    if (!libDir.existsSync()) {
      debugPrint('ThemeAudit: lib/ no encontrado, omitiendo auditoria.');
      return;
    }

    final excludedFragments = <String>[
      '${Platform.pathSeparator}core${Platform.pathSeparator}theme',
      '${Platform.pathSeparator}core${Platform.pathSeparator}constants',
      '${Platform.pathSeparator}core${Platform.pathSeparator}utils',
      '${Platform.pathSeparator}features${Platform.pathSeparator}settings'
          '${Platform.pathSeparator}data${Platform.pathSeparator}'
          'theme_settings_model.dart',
      '${Platform.pathSeparator}features${Platform.pathSeparator}settings'
          '${Platform.pathSeparator}providers${Platform.pathSeparator}'
          'theme_provider.dart',
    ];

    final pattern = RegExp(r'\bColors\.|\bColor\(');
    final hits = <String>[];

    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (!path.endsWith('.dart')) continue;
      if (excludedFragments.any(path.contains)) continue;

      String content;
      try {
        final bytes = entity.readAsBytesSync();
        // Some files may be saved in a legacy encoding on Windows.
        // We don't want the audit to freeze/crash because of that.
        content = utf8.decode(bytes, allowMalformed: true);
        // If the file is empty or looks undecodable, still continue; regex will fail.
      } catch (e) {
        // As a last resort, try default decoding; if it fails, skip.
        try {
          content = entity.readAsStringSync();
        } catch (_) {
          debugPrint(
            'ThemeAudit: no se pudo leer "$path" (encoding). Omitiendo. Error: $e',
          );
          continue;
        }
      }
      if (!pattern.hasMatch(content)) continue;
      hits.add(path.replaceFirst(root.path, ''));
    }

    if (hits.isEmpty) {
      debugPrint('ThemeAudit: OK, sin hardcodes de color fuera del tema.');
      return;
    }

    debugPrint('ThemeAudit: se encontraron hardcodes de color:');
    for (final h in hits) {
      debugPrint(' - $h');
    }
  }
}
