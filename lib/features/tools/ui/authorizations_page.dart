import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/security/app_actions.dart';
import '../../../core/session/session_manager.dart';
import '../data/authorization_audit_repository.dart';

class AuthorizationsPage extends StatefulWidget {
  const AuthorizationsPage({super.key});

  @override
  State<AuthorizationsPage> createState() => _AuthorizationsPageState();
}

class _AuthorizationsPageState extends State<AuthorizationsPage> {
  final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');
  bool _loading = true;
  String? _error;
  List<AuthorizationAuditEntry> _entries = [];
  AuthorizationAuditEntry? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final companyId = await SessionManager.companyId() ?? 1;
      final entries = await AuthorizationAuditRepository.listAudits(
        companyId: companyId,
        limit: 400,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _selected = entries.isEmpty ? null : (_selected ?? entries.first);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las autorizaciones.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Autorizaciones'),
        actions: [
          IconButton(
            tooltip: 'Recargar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(scheme),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_entries.isEmpty) {
      return Center(child: Text(_error ?? 'No hay autorizaciones registradas.'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;
        final selected = _selected ?? _entries.first;

        final list = _buildAuditList(scheme, isWide: isWide);
        final details = _AuthorizationDetailPane(
          entry: selected,
          dateFormat: _dateFormat,
        );

        if (!isWide) return list;

        return Row(
          children: [
            SizedBox(width: 520, child: list),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: scheme.outlineVariant.withOpacity(0.65),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: details,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAuditList(ColorScheme scheme, {required bool isWide}) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final isSelected = _selected?.id == entry.id;
        final action = AppActions.findByCode(entry.actionCode);
        final actionName = action?.name ?? entry.actionCode;
        final subtitle = action?.description ?? '';
        final time = _dateFormat.format(
          DateTime.fromMillisecondsSinceEpoch(entry.createdAtMs),
        );
        final method = (entry.method ?? 'unknown').toUpperCase();
        final result = entry.result.toUpperCase();
        final statusColor = _statusColor(result, scheme);

        final card = Card(
          elevation: 0,
          color: isSelected ? scheme.primaryContainer.withOpacity(0.12) : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected ? scheme.primary : scheme.outlineVariant,
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        actionName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        result,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: scheme.onSurface.withOpacity(0.7),
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _infoChip('Metodo', method, scheme),
                    _infoChip('Fecha', time, scheme),
                    _infoChip('Solicita', entry.requestedLabel, scheme),
                    _infoChip('Aprueba', entry.approvedLabel, scheme),
                    if ((entry.terminalId ?? '').trim().isNotEmpty)
                      _infoChip('Terminal', entry.terminalId!.trim(), scheme),
                  ],
                ),
              ],
            ),
          ),
        );

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            setState(() => _selected = entry);
            if (!isWide) {
              await showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  contentPadding: const EdgeInsets.all(16),
                  content: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: _AuthorizationDetailPane(
                      entry: entry,
                      dateFormat: _dateFormat,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              );
            }
          },
          child: card,
        );
      },
    );
  }

  Color _statusColor(String result, ColorScheme scheme) {
    switch (result) {
      case 'APPROVED':
        return scheme.primary;
      case 'ISSUED':
        return scheme.tertiary;
      case 'REQUESTED':
        return scheme.secondary;
      case 'EXPIRED':
        return scheme.error;
      case 'INVALID':
      case 'RESOURCE_MISMATCH':
        return scheme.error;
      default:
        return scheme.outline;
    }
  }

  Widget _infoChip(String label, String value, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              color: scheme.onSurface.withOpacity(0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _AuthorizationDetailPane extends StatelessWidget {
  final AuthorizationAuditEntry entry;
  final DateFormat dateFormat;

  const _AuthorizationDetailPane({
    required this.entry,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final action = AppActions.findByCode(entry.actionCode);
    final actionName = action?.name ?? entry.actionCode;
    final subtitle = action?.description ?? '';
    final when = dateFormat.format(
      DateTime.fromMillisecondsSinceEpoch(entry.createdAtMs),
    );
    final method = (entry.method ?? 'unknown').toUpperCase();
    final result = entry.result.toUpperCase();

    final meta = entry.meta ?? const <String, dynamic>{};

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    actionName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                _statusPill(context, result),
              ],
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withOpacity(0.75),
                    ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _kv(context, 'Fecha/Hora', when),
                _kv(context, 'Método', method),
                _kv(context, 'Resultado', result),
                _kv(context, 'Solicitado por', entry.requestedLabel),
                _kv(context, 'Aprobado por', entry.approvedLabel),
                if ((entry.terminalId ?? '').trim().isNotEmpty)
                  _kv(context, 'Terminal', entry.terminalId!.trim()),
                if ((entry.resourceType ?? '').trim().isNotEmpty)
                  _kv(context, 'Recurso', entry.resourceType!.trim()),
                if ((entry.resourceId ?? '').trim().isNotEmpty)
                  _kv(context, 'ID Recurso', entry.resourceId!.trim()),
              ],
            ),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Detalle',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              ...meta.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _kv(context, e.key, '${e.value}'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusPill(BuildContext context, String result) {
    final scheme = Theme.of(context).colorScheme;
    Color color;
    switch (result) {
      case 'APPROVED':
        color = scheme.primary;
      case 'ISSUED':
      case 'REQUESTED':
        color = scheme.tertiary;
      case 'EXPIRED':
      case 'INVALID':
      case 'RESOURCE_MISMATCH':
        color = scheme.error;
      default:
        color = scheme.outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Text(
        result,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$k: ',
            style: TextStyle(
              color: scheme.onSurface.withOpacity(0.7),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Flexible(
            child: Text(
              v,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
