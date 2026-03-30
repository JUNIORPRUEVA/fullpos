import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/business_settings_model.dart';
import '../providers/business_settings_provider.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/cloud_sync_service.dart';
import '../../../core/sync/product_sync_service.dart';
import 'settings_layout.dart';

class CloudSettingsPage extends ConsumerStatefulWidget {
  const CloudSettingsPage({super.key});

  @override
  ConsumerState<CloudSettingsPage> createState() => _CloudSettingsPageState();
}

class _CloudSettingsPageState extends ConsumerState<CloudSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  late BusinessSettings _settings;
  bool _loading = true;
  late Future<List<Map<String, dynamic>>> _syncStatusFuture;
  late Future<Map<String, dynamic>> _productSyncDebugFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(businessSettingsProvider);
      _settings = settings;
      _syncStatusFuture = CloudSyncService.instance.readSyncStatusRows();
      _productSyncDebugFuture = _loadProductSyncDebug();
      setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _save() async {
    final notifier = ref.read(businessSettingsProvider.notifier);
    final updated = _settings.copyWith(cloudEnabled: _settings.cloudEnabled);
    await notifier.saveSettings(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración de nube guardada')),
      );
    }
  }

  Future<void> _reloadSyncStatus() async {
    setState(() {
      _syncStatusFuture = CloudSyncService.instance.readSyncStatusRows();
      _productSyncDebugFuture = _loadProductSyncDebug();
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

  Future<Map<String, dynamic>> _loadProductSyncDebug() async {
    final rows = await ProductSyncService.instance.readStatusRows();
    final pendingCount = await ProductSyncService.instance.pendingCount();
    final lastSuccessAtMs = await ProductSyncService.instance.lastSuccessAtMs();
    final failedItems = rows
        .where((row) => (row['status'] as String?) == 'failed')
        .toList(growable: false);
    return {
      'rows': rows,
      'pendingCount': pendingCount,
      'lastSuccessAtMs': lastSuccessAtMs,
      'failedItems': failedItems,
    };
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

    final buildFullposApiUrl = const String.fromEnvironment(
      'FULLPOS_API_URL',
      defaultValue: '',
    ).trim();
    final buildLegacyApiUrl = const String.fromEnvironment(
      'BACKEND_BASE_URL',
      defaultValue: '',
    ).trim();
    final resolvedApiUrl = AppConfig.apiBaseUrl;
    final rawCloudEndpoint = (_settings.cloudEndpoint ?? '').trim();
    final effectiveCloudUrl = CloudSyncService.instance
        .debugResolveCloudBaseUrl(_settings);

    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nube y Accesos'),
          actions: [
            OutlinedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save, color: Colors.black),
              label: const Text(
                'Guardar',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.black,
                side: const BorderSide(color: Colors.black, width: 1.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
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
                      SwitchListTile(
                        title: const Text('Sincronización en la nube'),
                        subtitle: const Text(
                          'Habilita el acceso a la app FULLPOS Owner',
                        ),
                        value: _settings.cloudEnabled,
                        onChanged: (v) {
                          setState(
                            () =>
                                _settings = _settings.copyWith(cloudEnabled: v),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      if (kDebugMode) ...[
                        Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Debug sync de productos',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                ValueListenableBuilder<String>(
                                  valueListenable:
                                      ProductSyncService.instance.connectionState,
                                  builder: (context, connectionState, _) {
                                    return Text(
                                      'WebSocket: $connectionState',
                                      style: const TextStyle(fontSize: 12),
                                    );
                                  },
                                ),
                                const SizedBox(height: 10),
                                FutureBuilder<Map<String, dynamic>>(
                                  future: _productSyncDebugFuture,
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: CircularProgressIndicator(),
                                      );
                                    }

                                    final data = snapshot.data ?? const {};
                                    final pendingCount =
                                        (data['pendingCount'] as int?) ?? 0;
                                    final lastSuccessAtMs =
                                        data['lastSuccessAtMs'] as int?;
                                    final failedItems =
                                        (data['failedItems'] as List?) ?? const [];
                                    final rows =
                                        (data['rows'] as List?) ?? const [];

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Pendientes en outbox: $pendingCount',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Último sync exitoso: ${_formatTs(lastSuccessAtMs)}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Fallidos: ${failedItems.length}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        const SizedBox(height: 8),
                                        if (rows.isEmpty)
                                          const Text(
                                            'No hay ítems de productos en el outbox.',
                                            style: TextStyle(fontSize: 12),
                                          )
                                        else
                                          ...rows.take(8).map((item) {
                                            final status =
                                                (item['status'] as String?) ??
                                                'unknown';
                                            final entityId =
                                                item['entity_id']?.toString() ??
                                                '-';
                                            final operation =
                                                (item['operation_type']
                                                        as String?) ??
                                                'n/a';
                                            final error =
                                                (item['last_error'] as String?) ??
                                                '-';
                                            return Container(
                                              width: double.infinity,
                                              margin: const EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: Colors.black12,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                'Producto local: $entityId\nOperación: $operation\nEstado: $status\nError: $error',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            );
                                          }),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Monitor de sincronización',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _reloadSyncStatus,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Actualizar'),
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
                              FutureBuilder<List<Map<String, dynamic>>>(
                                future: _syncStatusFuture,
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: CircularProgressIndicator(),
                                    );
                                  }

                                  final rows = snapshot.data ?? const [];
                                  if (rows.isEmpty) {
                                    return const Text(
                                      'No hay trabajos de sync en outbox todavía.',
                                      style: TextStyle(fontSize: 12),
                                    );
                                  }

                                  return Column(
                                    children: rows.map((row) {
                                      final target =
                                          (row['target'] as String?) ?? 'n/a';
                                      final status =
                                          (row['status'] as String?) ??
                                          'unknown';
                                      final attempts =
                                          (row['attempt_count'] as int?) ?? 0;
                                      final lastError =
                                          (row['last_error'] as String?) ?? '-';
                                      final lastSuccess =
                                          row['last_success_at_ms'] as int?;

                                      return Container(
                                        width: double.infinity,
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.black12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          'Tabla: $target\nEstado: $status\nIntentos: $attempts\nÚltimo éxito: ${_formatTs(lastSuccess)}\nÚltimo error: $lastError',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),
                            ],
                          ),
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
                                'URL de nube (actual)',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                resolvedApiUrl,
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (rawCloudEndpoint.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'cloudEndpoint guardado: $rawCloudEndpoint',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    onPressed: () async {
                                      setState(() {
                                        // Guardar vacío => se considera "no configurado".
                                        _settings = _settings.copyWith(
                                          cloudEndpoint: '',
                                        );
                                      });
                                      await _save();
                                    },
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Usar URL por defecto'),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                'URL efectiva usada para nube: $effectiveCloudUrl',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                buildFullposApiUrl.isNotEmpty
                                    ? 'Override FULLPOS_API_URL: $buildFullposApiUrl'
                                    : (buildLegacyApiUrl.isNotEmpty
                                          ? 'Override BACKEND_BASE_URL: $buildLegacyApiUrl'
                                          : 'Sin override de build (usando default del proyecto).'),
                                style: const TextStyle(fontSize: 12),
                              ),
                              if ((_settings.rnc ?? '').trim().isEmpty) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  'Nota: falta RNC en la empresa; es requerido para validar usuarios en la nube.',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'FULLPOS Owner',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Costo: \$15 USD por usuario/mes. Para activar la nube y obtener la app FULLPOS Owner, escribe a soporte.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Accesos a la nube',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Los accesos para FULLPOS Owner se crean desde Usuarios en el POS. Solo usuarios con rol Admin pueden iniciar sesión en la app Owner.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save),
                        label: const Text('Guardar'),
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
