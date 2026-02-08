import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/backup/backup_repository.dart';
import '../../../core/backup/backup_models.dart';
import '../../../core/backup/danger_actions_service.dart';
import '../../../core/backup/backup_paths.dart';
import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/theme/app_status_theme.dart';
import 'backup/confirm_phrase_dialog.dart';

class DatabaseSettingsPage extends StatefulWidget {
  const DatabaseSettingsPage({super.key});

  @override
  State<DatabaseSettingsPage> createState() => _DatabaseSettingsPageState();
}

class _DatabaseSettingsPageState extends State<DatabaseSettingsPage> {
  bool _loading = true;
  _DatabaseInfo? _info;
  List<DangerActionLogEntry> _logs = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
    });

    final info = await _loadDatabaseInfo();
    final logs = await BackupRepository.instance.listDangerActions(limit: 6);

    if (!mounted) return;
    setState(() {
      _info = info;
      _logs = logs;
      _loading = false;
    });
  }

  Future<_DatabaseInfo> _loadDatabaseInfo() async {
    final path = await BackupPaths.databaseFilePath();
    final file = File(path);
    final exists = await file.exists();
    final size = exists ? await file.length() : 0;
    final modified = exists ? await file.lastModified() : null;

    final db = await AppDb.database;
    final userVersionRow = await db.rawQuery('PRAGMA user_version;');
    final pageCountRow = await db.rawQuery('PRAGMA page_count;');
    final tableRow = await db.rawQuery(
      "SELECT COUNT(*) AS total FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';",
    );
    final countRow = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM ${DbTables.posTickets};',
    );

    final userVersion = (userVersionRow.first['user_version'] as int?) ?? 0;
    final pageCount = (pageCountRow.first['page_count'] as int?) ?? 0;
    final tables = (tableRow.first['total'] as int?) ?? 0;
    final pendingTickets = (countRow.first['total'] as int?) ?? 0;

    return _DatabaseInfo(
      path: path,
      exists: exists,
      sizeBytes: size,
      modifiedAt: modified,
      userVersion: userVersion,
      pageCount: pageCount,
      tableCount: tables,
      pendingTickets: pendingTickets,
    );
  }

  Future<void> _performDangerAction({
    required String title,
    required String message,
    required String phraseHint,
    required String confirmText,
    required Future<DangerActionResult> Function({
      required String confirmedPhrase,
      required String pin,
    })
    action,
  }) async {
    final res = await showDialog<ConfirmPhraseResult>(
      context: context,
      builder: (_) => ConfirmPhraseDialog(
        title: title,
        message: message,
        phraseHint: phraseHint,
        confirmText: confirmText,
      ),
    );
    if (res == null || res.phrase.isEmpty || res.pin.isEmpty) return;

    if (!mounted) return;
    setState(() => _isProcessing = true);
    final result = await action(confirmedPhrase: res.phrase, pin: res.pin);
    if (!mounted) return;
    setState(() => _isProcessing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.messageUser),
        backgroundColor: result.ok ? Colors.green : Colors.redAccent,
      ),
    );
    await _refresh();
  }

  Widget _infoRow(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(
            '$label:',
            style: TextStyle(
              color: scheme.onSurface.withOpacity(0.75),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dangerLogTile(DangerActionLogEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = entry.result == 'SUCCESS'
        ? scheme.tertiary
        : scheme.error;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(entry.action, style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        'Resultado: ${entry.result} · ${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(entry.createdAtMs))}',
      ),
      trailing: Icon(Icons.report_problem, color: statusColor),
    );
  }

  Future<void> _resetLocalData() async {
    await _performDangerAction(
      title: 'Restablecer empresa',
      message:
          'Esto limpia todas las tablas del negocio y reinicia el contador de datos.',
      phraseHint: 'RESETEAR EMPRESA',
      confirmText: 'Restablecer',
      action: DangerActionsService.instance.resetLocal,
    );
  }

  Future<void> _deleteAllData() async {
    await _performDangerAction(
      title: 'Eliminar todo',
      message:
          'Borra la base de datos local, preferencias y backups. Requiere reiniciar.',
      phraseHint: 'BORRAR TODO FULLPOS',
      confirmText: 'Eliminar',
      action: DangerActionsService.instance.deleteAllLocal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Base de datos'),
        backgroundColor: scheme.surfaceVariant,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: scheme.surface,
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Detalles de la base de datos',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            if (_info != null) ...[
                              _infoRow('Ruta', _info!.path),
                              _infoRow(
                                'Tamaño',
                                _formatBytes(_info!.sizeBytes),
                              ),
                              _infoRow(
                                'Actualizado',
                                _info!.modifiedAt == null
                                    ? 'No disponible'
                                    : DateFormat(
                                        'dd/MM/yyyy HH:mm',
                                      ).format(_info!.modifiedAt!),
                              ),
                              _infoRow('Versión', '${_info!.userVersion}'),
                              _infoRow('Tablas', '${_info!.tableCount}'),
                              _infoRow('Páginas', '${_info!.pageCount}'),
                              _infoRow(
                                'Tickets pendientes',
                                '${_info!.pendingTickets}',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.restore_page),
                            label: const Text('Resetear esquema'),
                            onPressed: _isProcessing ? null : _resetLocalData,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.delete_forever),
                            label: const Text('Eliminar todo'),
                            onPressed: _isProcessing ? null : _deleteAllData,
                            style: FilledButton.styleFrom(
                              backgroundColor: scheme.error,
                              foregroundColor: scheme.onError,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      color: scheme.surfaceVariant,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Alertas de base de datos',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const Spacer(),
                                if (status != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: status.warning,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${_logs.where((entry) => entry.result != "SUCCESS").length} errores',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_logs.isEmpty)
                              Text(
                                'Sin incidencias registradas recientemente.',
                                style: theme.textTheme.bodySmall,
                              )
                            else
                              Column(
                                children: _logs.map(_dangerLogTile).toList(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String _formatBytes(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var index = 0;
    while (size >= 1024 && index < suffixes.length - 1) {
      size /= 1024;
      index++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[index]}';
  }
}

class _DatabaseInfo {
  _DatabaseInfo({
    required this.path,
    required this.exists,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.userVersion,
    required this.pageCount,
    required this.tableCount,
    required this.pendingTickets,
  });

  final String path;
  final bool exists;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final int userVersion;
  final int pageCount;
  final int tableCount;
  final int pendingTickets;
}
