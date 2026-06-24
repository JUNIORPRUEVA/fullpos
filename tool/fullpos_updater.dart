import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  final log = _UpdaterLog(File(options['log'] ?? _defaultLogPath()));
  await log.write('Updater started');
  await log.write('Received arguments: ${jsonEncode(_redactNothing(options))}');

  try {
    final installerPath = _required(options, 'installer');
    final appPath = _required(options, 'app');
    final pid = int.parse(_required(options, 'pid'));
    final silent = options.containsKey('silent');
    final restart = options.containsKey('restart');

    final installer = File(installerPath);
    final app = File(appPath);
    await _validateInstallerLocation(installer);
    if (!await app.exists()) {
      throw StateError('App executable does not exist: ${app.path}');
    }

    await log.write('Waiting for FullPOS PID $pid to exit');
    var closed = await _waitForExit(pid, const Duration(seconds: 30));
    if (!closed) {
      await log.write(
        'FullPOS close timeout; attempting graceful close PID $pid',
      );
      await _taskKill(pid, force: false, log: log);
      closed = await _waitForExit(pid, const Duration(seconds: 10));
    }
    if (!closed) {
      await log.write('Force kill attempted only for provided PID $pid');
      await _taskKill(pid, force: true, log: log);
      closed = await _waitForExit(pid, const Duration(seconds: 10));
    }
    if (!closed) {
      throw StateError('FullPOS PID $pid did not exit');
    }
    await log.write('FullPOS closed successfully');

    final installerArgs = silent
        ? const ['/VERYSILENT', '/NORESTART', '/SUPPRESSMSGBOXES']
        : const <String>[];
    await log.write(
      'Running installer silently command="${installer.path}" args=${installerArgs.join(' ')}',
    );
    final process = await Process.start(
      installer.path,
      installerArgs,
      runInShell: false,
    );
    process.stdout.transform(utf8.decoder).listen((line) {
      log.write('installer stdout: $line');
    });
    process.stderr.transform(utf8.decoder).listen((line) {
      log.write('installer stderr: $line');
    });
    final exitCode = await process.exitCode;
    await log.write('Installer exit code: $exitCode');
    if (exitCode != 0) {
      await log.write('Installation failure');
      await _showFailureMessage();
      exit(exitCode);
    }

    await log.write('Installation success');
    if (restart) {
      await log.write('Relaunching FullPOS "${app.path}"');
      await Process.start(
        app.path,
        const <String>[],
        workingDirectory: app.parent.path,
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
    }
    await log.write('Updater finished');
  } catch (error, stack) {
    await log.write('Updater failed: $error');
    await log.write(stack.toString());
    await _showFailureMessage();
    exit(1);
  }
}

Map<String, String> _parseArgs(List<String> args) {
  final parsed = <String, String>{};
  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (!arg.startsWith('--')) continue;
    final key = arg.substring(2);
    if (key == 'silent' || key == 'restart') {
      parsed[key] = 'true';
      continue;
    }
    if (index + 1 >= args.length) {
      throw FormatException('Missing value for --$key');
    }
    parsed[key] = args[++index];
  }
  return parsed;
}

String _required(Map<String, String> options, String key) {
  final value = options[key];
  if (value == null || value.trim().isEmpty) {
    throw FormatException('Missing --$key');
  }
  return value;
}

Map<String, String> _redactNothing(Map<String, String> options) {
  return Map<String, String>.from(options);
}

Future<void> _validateInstallerLocation(File installer) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('FullPOSUpdater is only supported on Windows');
  }
  if (!await installer.exists()) {
    throw StateError('Installer does not exist: ${installer.path}');
  }
  if (await installer.length() <= 0) {
    throw StateError('Installer is empty: ${installer.path}');
  }
  final localAppData = Platform.environment['LOCALAPPDATA'];
  if (localAppData == null || localAppData.trim().isEmpty) {
    throw StateError('LOCALAPPDATA is not available');
  }
  final allowedRoot = Directory('$localAppData\\FullPOS\\updates');
  final rootPath = await allowedRoot
      .create(recursive: true)
      .then((dir) => dir.resolveSymbolicLinks());
  final installerPath = await installer.resolveSymbolicLinks();
  final normalizedRoot = _normalizeForCompare(rootPath);
  final normalizedInstaller = _normalizeForCompare(installerPath);
  if (normalizedInstaller != normalizedRoot &&
      !normalizedInstaller.startsWith('$normalizedRoot\\')) {
    throw StateError('Installer path is outside the official updates folder');
  }
}

String _normalizeForCompare(String value) {
  return value
      .replaceAll('/', '\\')
      .replaceAll(RegExp(r'\\+$'), '')
      .toLowerCase();
}

Future<bool> _waitForExit(int pid, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (!await _isProcessRunning(pid)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return !await _isProcessRunning(pid);
}

Future<bool> _isProcessRunning(int pid) async {
  final result = await Process.run('tasklist.exe', [
    '/FI',
    'PID eq $pid',
    '/NH',
  ]);
  final output = '${result.stdout}\n${result.stderr}'.toLowerCase();
  return result.exitCode == 0 && output.contains(pid.toString());
}

Future<void> _taskKill(
  int pid, {
  required bool force,
  required _UpdaterLog log,
}) async {
  final args = <String>['/PID', pid.toString()];
  if (force) args.add('/F');
  final result = await Process.run('taskkill.exe', args);
  await log.write(
    'taskkill force=$force exitCode=${result.exitCode} stdout=${result.stdout} stderr=${result.stderr}',
  );
}

Future<void> _showFailureMessage() async {
  const message =
      'No se pudo completar la actualización de FullPOS. Intenta abrir FullPOS nuevamente o contacta soporte.';
  await Process.run('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('$message','FullPOS') | Out-Null",
  ]);
}

String _defaultLogPath() {
  final localAppData =
      Platform.environment['LOCALAPPDATA'] ?? Directory.current.path;
  return '$localAppData\\FullPOS\\updates\\FullPOSUpdater.log';
}

class _UpdaterLog {
  _UpdaterLog(this.file);

  final File file;

  Future<void> write(String message) async {
    await file.parent.create(recursive: true);
    final line = jsonEncode({
      'ts': DateTime.now().toUtc().toIso8601String(),
      'message': message,
    });
    await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
  }
}
