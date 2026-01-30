import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../errors/app_exception.dart';

enum AppLogLevel { info, warn, error }

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const int _maxFileBytes = 5 * 1024 * 1024; // 5MB

  Directory? _dir;
  File? _file;
  Future<void> _queue = Future<void>.value();

  bool get isInitialized => _dir != null && _file != null;

  Future<void> init() async {
    if (isInitialized) return;

    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(baseDir.path, 'logs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _dir = dir;
    _file = await _resolveTodayFile();
  }

  Future<File> _resolveTodayFile() async {
    final dir = _dir;
    if (dir == null) {
      throw StateError('AppLogger.init() must be called first.');
    }

    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Rotación por tamaño: app_YYYY-MM-DD.log, app_YYYY-MM-DD_2.log, ...
    var index = 1;
    while (true) {
      final name = index == 1 ? 'app_$date.log' : 'app_${date}_$index.log';
      final file = File(p.join(dir.path, name));
      if (!await file.exists()) {
        await file.create(recursive: true);
        return file;
      }
      final len = await file.length();
      if (len < _maxFileBytes) return file;
      index++;
    }
  }

  Future<void> _write(Map<String, dynamic> entry) async {
    await init();
    final file = _file!;

    _queue = _queue.then((_) async {
      try {
        // Si cambió el día o el archivo creció, recalcular.
        final now = DateTime.now();
        final currentDate =
            '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        if (!p.basename(file.path).contains(currentDate) ||
            await file.length() >= _maxFileBytes) {
          _file = await _resolveTodayFile();
        }

        final line = jsonEncode(entry);
        // `flush: true` en cada línea puede causar stutter/jank (especialmente en Windows).
        // Dejamos que el SO haga el flush de forma eficiente.
        await _file!.writeAsString(
          '$line\n',
          mode: FileMode.append,
          flush: false,
        );
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('AppLogger write failed: $e');
        }
      }
    });

    return _queue;
  }

  Future<void> logInfo(String message, {String? module}) {
    return _write({
      'ts': DateTime.now().toIso8601String(),
      'level': describeEnum(AppLogLevel.info),
      'module': module,
      'message': message,
    });
  }

  Future<void> logWarn(String message, {String? module}) {
    return _write({
      'ts': DateTime.now().toIso8601String(),
      'level': describeEnum(AppLogLevel.warn),
      'module': module,
      'message': message,
    });
  }

  Future<void> logError(AppException ex, {String? module}) {
    return _write({
      'ts': DateTime.now().toIso8601String(),
      'level': describeEnum(AppLogLevel.error),
      'module': module,
      'type': describeEnum(ex.type),
      'code': ex.code,
      'messageUser': ex.messageUser,
      'messageDev': ex.messageDev,
      'stackTrace': ex.stackTrace?.toString(),
      'originalError': ex.originalError?.toString(),
    });
  }

  Future<String?> exportLatestLogs() async {
    await init();
    return _file?.path;
  }
}
