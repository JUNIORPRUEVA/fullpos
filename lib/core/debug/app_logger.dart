import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Nivel de log para diagnosticar arranques/render.
enum DebugLogLevel { info, warning, error }

/// Logger peque単o y aislado para diagnosticos de render.
/// Es independiente del logger de negocio para evitar dependencias cíclicas
/// al capturar fallos muy tempranos del pipeline de render.
class DebugAppLogger {
  DebugAppLogger._();

  static final DebugAppLogger instance = DebugAppLogger._();

  static const int _maxFileBytes = 2 * 1024 * 1024; // 2MB

  Directory? _dir;
  File? _file;
  Future<void> _queue = Future<void>.value();

  String? get logFilePath => _file?.path;

  bool get isReady => _dir != null && _file != null;

  Future<void> init() async {
    if (isReady) return;

    final baseDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(baseDir.path, 'logs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    _dir = dir;
    final file = File(p.join(dir.path, 'app.log'));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    _file = file;
  }

  Future<void> log(
    String message, {
    String module = 'render',
    DebugLogLevel level = DebugLogLevel.info,
    Map<String, Object?>? data,
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final now = DateTime.now();
    final entry = <String, Object?>{
      'ts': now.toIso8601String(),
      'level': describeEnum(level),
      'module': module,
      'message': message,
      if (data != null) 'data': data,
      if (error != null) 'error': '$error',
      if (stackTrace != null) 'stackTrace': '$stackTrace',
    };

    final consolePrefix = '[${entry['level']}] [$module]';
    debugPrint('$consolePrefix $message ${data ?? ''}'.trim());

    await _enqueue(jsonEncode(entry));
  }

  Future<void> info(
    String message, {
    String module = 'render',
    Map<String, Object?>? data,
  }) {
    return log(message, module: module, level: DebugLogLevel.info, data: data);
  }

  Future<void> warn(
    String message, {
    String module = 'render',
    Map<String, Object?>? data,
  }) {
    return log(
      message,
      module: module,
      level: DebugLogLevel.warning,
      data: data,
    );
  }

  Future<void> error(
    String message, {
    String module = 'render',
    Map<String, Object?>? data,
    Object? error,
    StackTrace? stackTrace,
  }) {
    return log(
      message,
      module: module,
      level: DebugLogLevel.error,
      data: data,
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<void> _enqueue(String line) async {
    await init();
    _queue = _queue.then((_) async {
      try {
        final file = _file!;
        // Limpiar si el archivo crece demasiado (rotación simple).
        if (await file.length() >= _maxFileBytes) {
          await file.writeAsString('');
        }
        await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
      } catch (e) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('DebugAppLogger write failed: $e');
        }
      }
    });
    return _queue;
  }

  @visibleForTesting
  void resetForTesting() {
    _dir = null;
    _file = null;
    _queue = Future<void>.value();
  }

  @visibleForTesting
  Future<void> drainQueue() => _queue;
}
