import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../core/backup/backup_models.dart';
import '../../../core/backup/backup_paths.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/window/window_service.dart';
import 'settings_layout.dart';

class BackupSettingsPage extends StatefulWidget {
  const BackupSettingsPage({super.key});

  @override
  State<BackupSettingsPage> createState() => _BackupSettingsPageState();
}

class _BackupSettingsPageState extends State<BackupSettingsPage> {
  bool _loading = true;
  bool _busy = false;
  String? _baseDirPath;
  int _retention = 15;
  List<File> _backups = const [];

  ColorScheme get scheme => Theme.of(context).colorScheme;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final base = await BackupPaths.backupsBaseDir();
    final retention = await BackupService.instance.getRetentionCount();
    final backups = (await BackupService.instance.listBackups())
        .whereType<File>()
        .toList(growable: false);

    if (!mounted) return;
    setState(() {
      _baseDirPath = base.path;
      _retention = retention;
      _backups = backups;
      _loading = false;
    });
  }

  Future<void> _createBackupNow() async {
    if (_busy) return;
    setState(() => _busy = true);

    final messenger = ScaffoldMessenger.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(
        message: 'Guardando copia de seguridad… (puede tardar)',
      ),
    );

    try {
      final result = await BackupService.instance.createBackup(
        trigger: BackupTrigger.manual,
        maxWait: const Duration(minutes: 2),
      );

      if (mounted && rootNavigator.canPop()) {
        rootNavigator.pop();
      }

      if (!mounted) return;
      setState(() => _busy = false);
      await _load();

      if (result.ok && result.path != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Backup creado: ${result.path}'),
            backgroundColor: scheme.tertiary,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content: Text(result.messageUser ?? 'No se pudo crear el backup.'),
          backgroundColor: scheme.error,
        ),
      );
    } finally {
      if (mounted && rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pickAndRestoreBackup() async {
    if (_busy) return;

    final result = await WindowService.runWithSystemDialog(
      () => FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      ),
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) return;
    await _restoreFromPath(path);
  }

  Future<void> _restoreFromPath(String zipPath) async {
    if (_busy) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restaurar backup'),
        content: const Text(
          'Esto reemplazará los datos actuales.\n\n¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sí, restaurar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;

    setState(() => _busy = true);

    showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => const _BusyDialog(message: 'Restaurando backup…'),
    );

    try {
      final restore =
          await BackupService.instance.restoreBackup(zipPath: zipPath);

      if (mounted && rootNavigator.canPop()) {
        rootNavigator.pop();
      }

      if (!mounted) return;
      setState(() => _busy = false);

      if (restore.ok) {
        await _load();
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
              'Backup restaurado. Recomendado: reinicia la app para recargar todo.',
            ),
            backgroundColor: scheme.tertiary,
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      messenger.showSnackBar(
        SnackBar(
          content:
              Text(restore.messageUser ?? 'No se pudo restaurar el backup.'),
          backgroundColor: scheme.error,
        ),
      );
    } finally {
      if (mounted && rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openFolder() async {
    final dirPath = _baseDirPath;
    if (dirPath == null) return;

    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [dirPath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [dirPath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dirPath]);
      }
    } catch (_) {
      // Ignorar.
    }
  }

  Future<void> _copyPath(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Ruta copiada.'),
        backgroundColor: scheme.tertiary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareBackup(File file) async {
    try {
      await Share.shareXFiles([XFile(file.path)]);
    } catch (_) {
      // Ignorar.
    }
  }

  Future<void> _setRetention(int value) async {
    await BackupService.instance.setRetentionCount(value);
    if (!mounted) return;
    setState(() => _retention = value);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final baseDir = _baseDirPath;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Backups'),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = SettingsLayout.contentPadding(constraints);
          return _loading
              ? const Center(child: CircularProgressIndicator())
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: SettingsLayout.maxWidth(constraints),
                    child: Padding(
                      padding: padding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                  Container(
                    padding: const EdgeInsets.all(AppSizes.paddingM),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(AppSizes.radiusM),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Carpeta de backups',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          baseDir ?? '-',
                          style: const TextStyle(fontSize: 12, height: 1.25),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: _busy ? null : _createBackupNow,
                              icon: const Icon(Icons.save),
                              label: const Text('Crear backup ahora'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _pickAndRestoreBackup,
                              icon: const Icon(Icons.restore),
                              label: const Text('Restaurar backup'),
                            ),
                            OutlinedButton.icon(
                              onPressed: (baseDir == null ||
                                      !(Platform.isWindows ||
                                          Platform.isMacOS ||
                                          Platform.isLinux))
                                  ? null
                                  : _openFolder,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('Abrir carpeta'),
                            ),
                            if (baseDir != null)
                              OutlinedButton.icon(
                                onPressed: () => _copyPath(baseDir),
                                icon: const Icon(Icons.copy),
                                label: const Text('Copiar ruta'),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSizes.spaceM),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Retención (cantidad de backups)',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            DropdownButton<int>(
                              value: _retention,
                              onChanged: _busy ? null : (v) => _setRetention(v!),
                              items: const [5, 10, 15, 20, 30]
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text('$v'),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Se mantienen los backups más recientes y se borran los antiguos automáticamente.',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSizes.spaceM),
                  const Text(
                    'Últimos backups',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: _backups.isEmpty
                        ? Center(
                            child: Text(
                              'Aún no hay backups.',
                              style: TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          )
                        : ListView.separated(
                            itemCount: _backups.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final f = _backups[index];
                              final name = p.basename(f.path);
                              final modified = f.lastModifiedSync();
                              final sizeKb = (f.lengthSync() / 1024).round();
                              return Container(
                                padding:
                                    const EdgeInsets.all(AppSizes.paddingM),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius:
                                      BorderRadius.circular(AppSizes.radiusM),
                                  border: Border.all(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.archive, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          '${sizeKb}KB',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Fecha: ${modified.toLocal()}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () => _restoreFromPath(f.path),
                                          icon: const Icon(Icons.restore),
                                          label: const Text('Restaurar'),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () => _copyPath(f.path),
                                          icon: const Icon(Icons.copy),
                                          label: const Text('Copiar ruta'),
                                        ),
                                        if (Platform.isAndroid)
                                          OutlinedButton.icon(
                                            onPressed: () => _shareBackup(f),
                                            icon: const Icon(Icons.share),
                                            label: const Text('Compartir'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                        ],
                      ),
                    ),
                  ),
                );
        },
      ),
    );
  }
}

class _BusyDialog extends StatelessWidget {
  const _BusyDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
