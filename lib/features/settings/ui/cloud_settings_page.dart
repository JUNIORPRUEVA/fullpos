import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/business_settings_model.dart';
import '../providers/business_settings_provider.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/sync/product_sync_service.dart';
import 'settings_layout.dart';

class CloudSettingsPage extends ConsumerStatefulWidget {
  const CloudSettingsPage({super.key});

  @override
  ConsumerState<CloudSettingsPage> createState() => _CloudSettingsPageState();
}

class _CloudSettingsPageState extends ConsumerState<CloudSettingsPage> {
  static const Set<String> _visibleTargets = {
    'products',
    'categories',
    'clients',
    'company_config',
    'users',
    'sales',
  };

  final _formKey = GlobalKey<FormState>();
  late BusinessSettings _settings;
  bool _loading = true;
  bool _savingCloudEnabled = false;
  late Future<Map<String, dynamic>> _cloudHealthFuture;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = ref.read(businessSettingsProvider);
      _settings = settings;
      _cloudHealthFuture = _loadCloudHealth();
      if (!mounted) return;
      setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _persistCloudEnabled(bool enabled) async {
    if (_savingCloudEnabled) return;
    final notifier = ref.read(businessSettingsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final previous = _settings;
    final updated = _settings.copyWith(cloudEnabled: enabled);

    setState(() {
      _savingCloudEnabled = true;
      _settings = updated;
    });

    try {
      await notifier.saveSettings(updated);
      if (enabled) {
        ProductSyncService.instance.start();
        await CloudSyncService.instance.syncRequiredTargetsNow(
          reason: 'cloud_enabled_from_settings',
        );
        CloudSyncService.instance.startRealtimeSyncEngine();
        await ProductSyncService.instance.retryFailedNow();
        await ProductSyncService.instance.flushNow();
      }
      await _reloadSyncStatus();
    } catch (_) {
      if (!mounted) return;
      setState(() => _settings = previous);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No se pudo guardar el estado de la nube'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingCloudEnabled = false);
      }
    }
  }

  Future<void> _triggerFullSyncNow() async {
    final notifier = ref.read(businessSettingsProvider.notifier);
    await notifier.saveSettings(_settings);
    await CloudSyncService.instance.syncRequiredTargetsNow(
      reason: 'cloud_settings_manual_sync',
    );
    await ProductSyncService.instance.retryFailedNow();
    await _reloadSyncStatus();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sincronización ejecutada')));
    }
  }

  Future<void> _reloadSyncStatus() async {
    if (!mounted) return;
    setState(() {
      _cloudHealthFuture = _loadCloudHealth();
    });
  }

  Future<void> _retryFailedSyncJobs() async {
    await CloudSyncService.instance.retryAllFailedSyncNow();
    await ProductSyncService.instance.retryFailedNow();
    await _reloadSyncStatus();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reintento de sincronización encolado')),
    );
  }

  Future<Map<String, dynamic>> _loadCloudHealth() async {
    final loggedIn = await SessionManager.isLoggedIn();
    final companyId = await SessionManager.companyId();
    final syncRows = await CloudSyncService.instance.readSyncStatusRows();
    final productRows = await ProductSyncService.instance.readStatusRows();
    final filteredRows = syncRows
        .where((row) {
          final target = (row['target'] as String?)?.trim() ?? '';
          return _visibleTargets.contains(target);
        })
        .toList(growable: false);
    final productsStatus = _resolveTargetStatus(filteredRows, 'products');
    final salesStatus = _resolveTargetStatus(filteredRows, 'sales');
    final rnc = (_settings.rnc ?? '').trim();
    final cloudCompanyId = (_settings.cloudCompanyId ?? '').trim();
    final hasCloudIdentity = rnc.isNotEmpty || cloudCompanyId.isNotEmpty;
    final wsState = ProductSyncService.instance.connectionState.value;
    final pendingCount = await ProductSyncService.instance.pendingCount();
    final productLastSuccessAtMs = await ProductSyncService.instance
        .lastSuccessAtMs();
    final hasProductFailures = productRows.any(
      (row) => (row['status'] as String?) == 'failed',
    );

    final issues = <String>[];
    if (!_settings.cloudEnabled) {
      issues.add('Nube desactivada');
    }
    if (!loggedIn) {
      issues.add('Sin sesión iniciada');
    }
    if (companyId == null) {
      issues.add('Sin companyId local');
    }
    if (!hasCloudIdentity) {
      issues.add('Falta RNC o cloudCompanyId');
    }
    if (wsState != 'connected') {
      issues.add('WebSocket de productos no conectado');
    }
    if (hasProductFailures) {
      issues.add('Hay fallos pendientes en sync de productos');
    }

    return {
      'loggedIn': loggedIn,
      'companyId': companyId,
      'hasCloudIdentity': hasCloudIdentity,
      'productsStatus': productsStatus,
      'salesStatus': salesStatus,
      'websocketState': wsState,
      'pendingProducts': pendingCount,
      'productLastSuccessAtMs': productLastSuccessAtMs,
      'issues': issues,
      'isHealthy': issues.isEmpty,
    };
  }

  Map<String, dynamic> _resolveTargetStatus(
    List<Map<String, dynamic>> rows,
    String target,
  ) {
    final row = rows.cast<Map<String, dynamic>?>().firstWhere(
      (candidate) => (candidate?['target'] as String?) == target,
      orElse: () => null,
    );

    if (row == null) {
      return {
        'target': target,
        'status': 'idle',
        'attempts': 0,
        'lastSuccessAtMs': null,
        'lastError': '-',
      };
    }

    return {
      'target': target,
      'status': (row['status'] as String?) ?? 'unknown',
      'attempts': (row['attempt_count'] as int?) ?? 0,
      'lastSuccessAtMs': row['last_success_at_ms'] as int?,
      'lastError': (row['last_error'] as String?) ?? '-',
    };
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'synced':
      case 'connected':
        return Colors.green;
      case 'syncing':
      case 'connecting':
        return Colors.orange;
      case 'failed':
      case 'error':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  String _targetLabel(String target) {
    switch (target) {
      case 'products':
        return 'Productos';
      case 'sales':
        return 'Ventas, reportes y ganancias';
      default:
        return target;
    }
  }

  Widget _buildHealthBadge({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetStatusCard(Map<String, dynamic> status) {
    final target = (status['target'] as String?) ?? 'n/a';
    final state = (status['status'] as String?) ?? 'unknown';
    final attempts = (status['attempts'] as int?) ?? 0;
    final lastError = (status['lastError'] as String?) ?? '-';
    final lastSuccessAtMs = status['lastSuccessAtMs'] as int?;
    final color = _statusColor(state);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.22)),
        borderRadius: BorderRadius.circular(10),
        color: color.withOpacity(0.03),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'FULLPOS ${_targetLabel(target)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                state,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Intentos: $attempts', style: const TextStyle(fontSize: 12)),
          Text(
            'Último éxito: ${_formatTs(lastSuccessAtMs)}',
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            'Último error: $lastError',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatTs(int? value) {
    if (value == null || value <= 0) return '-';
    final date = DateTime.fromMillisecondsSinceEpoch(value);
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(title: const Text('Nube y Accesos')),
        body: Form(
          key: _formKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final padding = SettingsLayout.contentPadding(constraints);
              return Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: SettingsLayout.maxWidth(constraints),
                  child: ListView(
                    padding: padding,
                    children: [
                      Card(
                        margin: EdgeInsets.zero,
                        child: SwitchListTile(
                          title: const Text(
                            'Sincronización FULLPOS en la nube',
                          ),
                          subtitle: Text(
                            _savingCloudEnabled
                                ? 'Guardando cambio...'
                                : 'Se guarda automáticamente y sincroniza productos y ventas.',
                          ),
                          value: _settings.cloudEnabled,
                          onChanged: _savingCloudEnabled
                              ? null
                              : _persistCloudEnabled,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Estado FULLPOS nube',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Solo se sincronizan productos y ventas. Aquí puedes ver si FULLPOS está realmente conectado y si esas dos tablas están subiendo bien.',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 12),
                              FutureBuilder<Map<String, dynamic>>(
                                future: _cloudHealthFuture,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: CircularProgressIndicator(),
                                    );
                                  }

                                  final health = snapshot.data ?? const {};
                                  final isHealthy =
                                      (health['isHealthy'] as bool?) ?? false;
                                  final productsStatus =
                                      health['productsStatus']
                                          as Map<String, dynamic>? ??
                                      const {};
                                  final salesStatus =
                                      health['salesStatus']
                                          as Map<String, dynamic>? ??
                                      const {};
                                  final websocketState =
                                      (health['websocketState'] as String?) ??
                                      'unknown';
                                  final pendingProducts =
                                      (health['pendingProducts'] as int?) ?? 0;
                                  final productLastSuccessAtMs =
                                      health['productLastSuccessAtMs'] as int?;
                                  final issues =
                                      (health['issues'] as List?)
                                          ?.whereType<String>()
                                          .toList() ??
                                      const <String>[];

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _buildHealthBadge(
                                            label: 'Conexión general',
                                            value: isHealthy ? 'OK' : 'Revisar',
                                            color: isHealthy
                                                ? Colors.green
                                                : Colors.orange,
                                          ),
                                          _buildHealthBadge(
                                            label: 'Productos',
                                            value:
                                                (productsStatus['status']
                                                    as String?) ??
                                                'idle',
                                            color: _statusColor(
                                              (productsStatus['status']
                                                      as String?) ??
                                                  'idle',
                                            ),
                                          ),
                                          _buildHealthBadge(
                                            label: 'Ventas',
                                            value:
                                                (salesStatus['status']
                                                    as String?) ??
                                                'idle',
                                            color: _statusColor(
                                              (salesStatus['status']
                                                      as String?) ??
                                                  'idle',
                                            ),
                                          ),
                                          _buildHealthBadge(
                                            label: 'WebSocket productos',
                                            value: websocketState,
                                            color: _statusColor(websocketState),
                                          ),
                                        ],
                                      ),
                                      if (issues.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(
                                              0.06,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: Colors.orange.withOpacity(
                                                0.24,
                                              ),
                                            ),
                                          ),
                                          child: Text(
                                            'Puntos a revisar: ${issues.join(' | ')}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      _buildTargetStatusCard(productsStatus),
                                      _buildTargetStatusCard(salesStatus),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Pendientes por subir: $pendingProducts',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Último sync de productos: ${_formatTs(productLastSuccessAtMs)}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Acciones',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _triggerFullSyncNow,
                                    icon: const Icon(Icons.cloud_sync_outlined),
                                    label: const Text('Sincronizar ahora'),
                                  ),
                                  const SizedBox(width: 8),
                                  OutlinedButton.icon(
                                    onPressed: _retryFailedSyncJobs,
                                    icon: const Icon(Icons.replay),
                                    label: const Text('Reintentar fallidos'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Al iniciar sesión o abrir la app con una sesión activa, FULLPOS intenta subir productos y ventas automáticamente.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
