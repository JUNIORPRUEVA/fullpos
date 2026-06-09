import 'dart:io';

class WindowsProtocolService {
  WindowsProtocolService._();

  static Future<void> ensureRegistered() async {
    if (!Platform.isWindows) return;

    final exePath = Platform.resolvedExecutable;
    if (exePath.trim().isEmpty) return;

    final commandValue = '"$exePath" "%1"';
    final baseKey = r'HKCU\Software\Classes\fullpos';

    try {
      await _regAdd(baseKey, null, 'URL:FULLPOS Protocol');
      await _regAdd(baseKey, 'URL Protocol', '');
      await _regAdd('$baseKey\\DefaultIcon', null, '"$exePath",0');
      await _regAdd('$baseKey\\shell\\open\\command', null, commandValue);
    } catch (_) {
      // No bloquear arranque si Windows impide registrar el protocolo.
    }
  }

  static Future<void> _regAdd(
    String key,
    String? valueName,
    String value,
  ) async {
    final args = <String>[
      'add',
      key,
      if (valueName == null) '/ve' else ...['/v', valueName],
      '/t',
      'REG_SZ',
      '/d',
      value,
      '/f',
    ];
    await Process.run('reg', args);
  }
}
