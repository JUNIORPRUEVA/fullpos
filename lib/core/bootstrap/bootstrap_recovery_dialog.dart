import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backup/backup_paths.dart';
import '../config/app_config.dart';
import '../db/app_db.dart';
import '../storage/prefs_safe.dart';
import '../support/support_logs_service.dart';
import '../utils/platform_open.dart';

class BootstrapRecoveryDialog extends StatefulWidget {
  const BootstrapRecoveryDialog({
    super.key,
    required this.errorMessage,
    required this.onRetry,
  });

  final String errorMessage;
  final VoidCallback onRetry;

  static Future<void> show(
    BuildContext context, {
    required String errorMessage,
    required VoidCallback onRetry,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          BootstrapRecoveryDialog(errorMessage: errorMessage, onRetry: onRetry),
    );
  }

  @override
  State<BootstrapRecoveryDialog> createState() =>
      _BootstrapRecoveryDialogState();
}

class _BootstrapRecoveryDialogState extends State<BootstrapRecoveryDialog> {
  bool _busy = false;
  String? _lastAction;

  Future<void> _run(String label, Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _lastAction = label;
    });
    try {
      await action();
    } finally {
      if (!mounted) return;
      setState(() {
        _busy = false;
      });
    }
  }

  Future<void> _repairPrefsAndRetry() async {
    await _run('Reparando almacenamiento local...', () async {
      // Intentar reconstruir SharedPreferences si está corrupto.
      await PrefsSafe.getInstance(attemptRepair: true);
      if (!mounted) return;
      Navigator.of(context).maybePop();
      widget.onRetry();
    });
  }

  Future<void> _openBackups() async {
    await _run('Abriendo backups...', () async {
      final dir = await BackupPaths.backupsBaseDir();
      await PlatformOpen.openFolder(dir.path);
    });
  }

  Future<void> _openLogs() async {
    await _run('Abriendo logs...', () async {
      final docs = await BackupPaths.documentsDir();
      final dir = Directory(p.join(docs.path, 'FULLPOS_LOGS'));
      if (!await dir.exists()) await dir.create(recursive: true);
      await PlatformOpen.openFolder(dir.path);
    });
  }

  Future<void> _copyDiagnostics() async {
    await _run('Copiando diagnóstico...', () async {
      final text = _buildDiagnosticsText();
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Diagnóstico copiado')));
    });
  }

  String _sanitizeWhatsappNumber(String input) {
    return input.replaceAll(RegExp(r'[^0-9]'), '').trim();
  }

  String _buildDiagnosticsText() {
    final now = DateTime.now().toIso8601String();
    final os = Platform.operatingSystem;
    final osVersion = Platform.operatingSystemVersion;
    final db = AppDb.diagnosticsSnapshot();

    final lines = <String>[
      'FULLPOS DIAGNOSTICO',
      'timestamp=$now',
      'appVersion=${AppConfig.appVersion}',
      'os=$os',
      'osVersion=$osVersion',
      'errorMessage=${widget.errorMessage}',
      'dbSnapshot=${db.toString()}',
      'note=Este diagnóstico NO borra BD ni datos.',
    ];

    return lines.join('\n');
  }

  Future<List<File>> _listLatestLogFiles(
    Directory dir, {
    required int limit,
  }) async {
    try {
      if (!await dir.exists()) return const [];
      final files = dir
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((f) {
            final name = p.basename(f.path).toLowerCase();
            return name.endsWith('.log') || name.endsWith('.txt');
          })
          .toList(growable: false);

      files.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });

      if (files.length <= limit) return files;
      return files.sublist(0, limit);
    } catch (_) {
      return const [];
    }
  }

  Future<String> _readFileTail(File file, {int maxBytes = 40 * 1024}) async {
    try {
      final len = await file.length();
      final start = len > maxBytes ? len - maxBytes : 0;
      final raf = await file.open();
      try {
        await raf.setPosition(start);
        final bytes = await raf.read(len - start);
        return utf8.decode(bytes, allowMalformed: true);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return '';
    }
  }

  Future<String> _buildSupportReportText() async {
    final diagnostics = _buildDiagnosticsText();

    final supportDir = await getApplicationSupportDirectory();
    final appLogsDir = Directory(p.join(supportDir.path, 'logs'));

    final docs = await BackupPaths.documentsDir();
    final docsLogsDir = Directory(p.join(docs.path, 'FULLPOS_LOGS'));

    final appFiles = await _listLatestLogFiles(appLogsDir, limit: 2);
    final docsFiles = await _listLatestLogFiles(docsLogsDir, limit: 2);

    final b = StringBuffer();
    b.writeln(diagnostics);
    b.writeln();
    b.writeln('LOGS (extracto/tail)');
    b.writeln('note=El reporte completo NO incluye la base de datos.');

    Future<void> addFiles(String label, List<File> files) async {
      if (files.isEmpty) return;
      b.writeln();
      b.writeln('[$label]');
      for (final f in files) {
        b.writeln('file=${f.path}');
        final tail = await _readFileTail(f);
        if (tail.trim().isEmpty) {
          b.writeln('(sin contenido o no se pudo leer)');
        } else {
          b.writeln('--- tail ---');
          b.writeln(tail.trimRight());
          b.writeln('--- end tail ---');
        }
        b.writeln();
      }
    }

    await addFiles('app_support/logs', appFiles);
    await addFiles('documents/FULLPOS_LOGS', docsFiles);

    return b.toString().trimRight();
  }

  String _truncateForWhatsApp(String input, {int maxChars = 2500}) {
    final text = input.trim();
    if (text.length <= maxChars) return text;
    return '${text.substring(0, maxChars)}\n\n[...recortado por límite de WhatsApp...]';
  }

  Future<void> _sendLogsToSupportWhatsApp() async {
    await _run('Preparando reporte para soporte...', () async {
      final report = await _buildSupportReportText();

      // ZIP local con logs (sin subir a backend).
      final zipPath = await SupportLogsService.instance.createZipOnly(
        errorMessage: widget.errorMessage,
      );

      final docs = await BackupPaths.documentsDir();
      final outDir = Directory(p.join(docs.path, 'FULLPOS_LOGS'));
      if (!await outDir.exists()) await outDir.create(recursive: true);

      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final reportPath = p.join(outDir.path, 'support_report_$stamp.txt');
      await File(reportPath).writeAsString(report);

      await Clipboard.setData(ClipboardData(text: report));

      final rawPhone = AppConfig.supportWhatsappNumber;
      final phone = _sanitizeWhatsappNumber(rawPhone);
      if (phone.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Reporte copiado. Falta configurar el WhatsApp de soporte (FULLPOS_SUPPORT_WHATSAPP).',
            ),
          ),
        );
        return;
      }

      final message = _truncateForWhatsApp(
        'Hola soporte FULLPOS.\n\n${_buildDiagnosticsText()}\n\n'
        'ZIP logs (adjuntar en WhatsApp): $zipPath\n'
        'Nota: el reporte completo fue copiado al portapapeles y guardado en FULLPOS_LOGS.\n\n'
        '${report.split('\n\nLOGS (extracto/tail)\n').length > 1 ? 'LOGS (extracto/tail)\n${report.split('\n\nLOGS (extracto/tail)\n').last}' : ''}',
      );

      final base = Uri.parse(AppConfig.whatsappBaseUrl);
      final uri = base.replace(
        path: phone,
        queryParameters: <String, String>{'text': message},
      );

      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo abrir WhatsApp. El reporte quedó copiado y guardado en: $reportPath',
            ),
          ),
        );
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'WhatsApp abierto. Reporte copiado y guardado en FULLPOS_LOGS.',
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.health_and_safety,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('Opciones de recuperación')),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estas opciones NO borran la base de datos ni datos del cliente.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              widget.errorMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_lastAction ?? 'Procesando...')),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
          child: const Text('Cerrar'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : _sendLogsToSupportWhatsApp,
          icon: const Icon(Icons.support_agent),
          label: const Text('Enviar a soporte (WhatsApp)'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : _copyDiagnostics,
          icon: const Icon(Icons.copy),
          label: const Text('Copiar diagnóstico'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : _openLogs,
          icon: const Icon(Icons.folder_open),
          label: const Text('Abrir logs'),
        ),
        TextButton.icon(
          onPressed: _busy ? null : _openBackups,
          icon: const Icon(Icons.folder_open),
          label: const Text('Abrir backups'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _repairPrefsAndRetry,
          icon: const Icon(Icons.build),
          label: const Text('Reparar y reintentar'),
        ),
      ],
    );
  }
}
