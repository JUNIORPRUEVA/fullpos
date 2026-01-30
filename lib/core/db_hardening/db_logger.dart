import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const String _kAppVersion =
    String.fromEnvironment('FULLPOS_APP_VERSION', defaultValue: '1.0.0+1');

class DbLogger {
  DbLogger._();

  static final DbLogger instance = DbLogger._();

  Future<void> _queue = Future<void>.value();
  File? _file;

  Future<void> log({
    required String stage,
    required String status,
    String? detail,
    String? error,
    int? schemaVersion,
  }) async {
    final file = await _resolveLogFile();

    final entry = <String, Object?>{
      'ts': DateTime.now().toIso8601String(),
      'stage': stage,
      'status': status,
      'appVersion': _kAppVersion,
      'schemaVersion': schemaVersion,
      if (detail != null) 'detail': detail,
      if (error != null) 'error': error,
    };

    _queue = _queue.then((_) async {
      await file.writeAsString(
        '${jsonEncode(entry)}\n',
        mode: FileMode.append,
        flush: true,
      );
    });

    return _queue;
  }

  Future<File> _resolveLogFile() async {
    if (_file != null) return _file!;
    final supportDir = await getApplicationSupportDirectory();
    final logDir = Directory(p.join(supportDir.path, 'logs'));
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    final target = File(p.join(logDir.path, 'db_hardening.log'));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    _file = target;
    return _file!;
  }
}
