import 'dart:io';

/// Utilidad mínima para abrir carpetas/archivos en el sistema.
///
/// No requiere plugins y es suficiente para Windows/Linux/macOS.
class PlatformOpen {
  PlatformOpen._();

  static Future<void> openFolder(String folderPath) async {
    // Nota: no lanzar al UI; si falla, simplemente no abre.
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [folderPath], runInShell: true);
        return;
      }
      if (Platform.isMacOS) {
        await Process.start('open', [folderPath]);
        return;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', [folderPath]);
        return;
      }
    } catch (_) {
      // Ignorar.
    }
  }
}
