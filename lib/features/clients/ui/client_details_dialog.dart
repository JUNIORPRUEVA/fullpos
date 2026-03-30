import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_sizes.dart';
import '../data/client_model.dart';
import '../../sales/data/sales_repository.dart';

/// Diálogo para mostrar los detalles completos de un cliente
class ClientDetailsDialog extends StatefulWidget {
  final ClientModel client;

  const ClientDetailsDialog({super.key, required this.client});

  @override
  State<ClientDetailsDialog> createState() => _ClientDetailsDialogState();
}

class _ClientDetailsDialogState extends State<ClientDetailsDialog> {
  late Future<Map<String, dynamic>> _summaryFuture;

  @override
  void initState() {
    super.initState();
    final id = widget.client.id;

    // Inicializar futures con manejo de errores
    _summaryFuture = id == null
        ? Future.value({'count': 0, 'total': 0.0, 'lastAtMs': null})
        : SalesRepository.getCustomerPurchaseSummary(
            id,
          ).catchError((_) => {'count': 0, 'total': 0.0, 'lastAtMs': null});
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildSummaryTile({
    required String label,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateOnlyFormat = DateFormat('dd/MM/yyyy');
    final createdDate = DateTime.fromMillisecondsSinceEpoch(client.createdAtMs);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    final initial = client.nombre.trim().isNotEmpty
        ? client.nombre.trim().substring(0, 1).toUpperCase()
        : '?';

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 900, maxHeight: maxHeight),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppSizes.radiusM),
                  topRight: Radius.circular(AppSizes.radiusM),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: scheme.primary.withOpacity(0.12),
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client.nombre,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (client.telefono?.isNotEmpty == true) ...[
                              const Icon(Icons.phone, size: 14),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  client.telefono!,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            const Icon(Icons.calendar_today_outlined, size: 14),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Ingreso: ${dateOnlyFormat.format(createdDate)}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        if (client.direccion?.isNotEmpty == true) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.location_on_outlined, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  client.direccion!,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionCard(
                      title: 'Actividad',
                      child: FutureBuilder<Map<String, dynamic>>(
                        future: _summaryFuture,
                        builder: (context, snapshot) {
                          final isLoading =
                              snapshot.connectionState ==
                              ConnectionState.waiting;
                          final data =
                              snapshot.data ?? const <String, dynamic>{};
                          final count = (data['count'] as int?) ?? 0;
                          final lastAtMs = data['lastAtMs'] as int?;
                          final lastText = lastAtMs == null || lastAtMs == 0
                              ? 'Sin compras'
                              : dateOnlyFormat.format(
                                  DateTime.fromMillisecondsSinceEpoch(lastAtMs),
                                );

                          if (snapshot.hasError) {
                            return Text(
                              'Error cargando estadísticas: ${snapshot.error}',
                            );
                          }

                          return Column(
                            children: [
                              Row(
                                children: [
                                  _buildMetricCard(
                                    icon: Icons.receipt_long,
                                    label: 'Compras',
                                    value: isLoading ? '...' : '$count',
                                  ),
                                  const SizedBox(width: 8),
                                  _buildMetricCard(
                                    icon: Icons.history_toggle_off,
                                    label: 'Última compra',
                                    value: isLoading ? '...' : lastText,
                                  ),
                                  const SizedBox(width: 8),
                                  _buildMetricCard(
                                    icon: Icons.person_outline,
                                    label: 'Estado',
                                    value: client.isActive
                                        ? 'Activo'
                                        : 'Inactivo',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _buildSummaryTile(
                                    label: 'Crédito',
                                    value: client.hasCredit
                                        ? 'Disponible'
                                        : 'No disponible',
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  _buildSummaryTile(
                                    label: 'Cliente desde',
                                    value: dateOnlyFormat.format(createdDate),
                                    color: scheme.tertiary,
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSectionCard(
                      title: 'Datos comerciales',
                      child: Column(
                        children: [
                          _buildInfoRow(
                            Icons.phone_outlined,
                            'Teléfono',
                            client.telefono?.isNotEmpty == true
                                ? client.telefono!
                                : '-',
                          ),
                          const SizedBox(height: 8),
                          _buildInfoRow(
                            Icons.business_outlined,
                            'RNC',
                            client.rnc?.isNotEmpty == true ? client.rnc! : '-',
                          ),
                          const SizedBox(height: 8),
                          _buildInfoRow(
                            Icons.badge_outlined,
                            'Cédula',
                            client.cedula?.isNotEmpty == true
                                ? client.cedula!
                                : '-',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSectionCard(
                      title: 'Dirección',
                      child: _buildInfoRow(
                        Icons.location_on_outlined,
                        'Ubicación',
                        client.direccion?.isNotEmpty == true
                            ? client.direccion!
                            : '-',
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Cerrar'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withOpacity(0.68),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
