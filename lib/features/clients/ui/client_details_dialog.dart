import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../data/client_model.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/data/sales_model.dart';
// import '../../sales/data/sale_kind.dart'; // Removed due to URI doesn't exist

/// Diálogo para mostrar los detalles completos de un cliente
class ClientDetailsDialog extends StatefulWidget {
  final ClientModel client;

  const ClientDetailsDialog({super.key, required this.client});

  @override
  State<ClientDetailsDialog> createState() => _ClientDetailsDialogState();
}

class _ClientDetailsDialogState extends State<ClientDetailsDialog> {
  late Future<Map<String, dynamic>> _summaryFuture;
  late Future<List<SaleModel>> _salesFuture;
  late Future<List<SaleModel>> _quotesFuture;
  late Future<List<SaleModel>> _returnsFuture;

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

    _salesFuture = id == null
        ? Future.value(<SaleModel>[])
        : SalesRepository.listCustomerPurchases(
            id,
            limit: 30,
          ).catchError((_) => <SaleModel>[]);

    _quotesFuture = id == null
        ? Future.value(<SaleModel>[])
        : SalesRepository.listCustomerSalesByKind(
            id,
            kind: SaleKind.quote,
            limit: 30,
          ).catchError((_) => <SaleModel>[]);

    _returnsFuture = id == null
        ? Future.value(<SaleModel>[])
        : SalesRepository.listCustomerSalesByKind(
            id,
            kind: SaleKind.returnSale,
            limit: 30,
            includePartialRefund: true,
          ).catchError((_) => <SaleModel>[]);
  }

  String _paymentMethodLabel(String? method) {
    switch (method) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      case 'mixed':
        return 'Mixto';
      default:
        return method ?? 'N/A';
    }
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

  Widget _buildTimelineCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String amount,
    required Color accent,
    String? trailing,
  }) {
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
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurface.withOpacity(0.68),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (trailing != null && trailing.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    trailing,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withOpacity(0.68),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            amount,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateOnlyFormat = DateFormat('dd/MM/yyyy');
    final money = NumberFormat.currency(symbol: 'RD\$ ', decimalDigits: 2);
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
                          final total =
                              (data['total'] as num?)?.toDouble() ?? 0.0;
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
                                    icon: Icons.directions_walk,
                                    label: 'Visitas',
                                    value: isLoading ? '...' : '$count',
                                  ),
                                  const SizedBox(width: 8),
                                  _buildMetricCard(
                                    icon: Icons.payments,
                                    label: 'Invertido',
                                    value: isLoading
                                        ? '...'
                                        : money.format(total),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _buildSummaryTile(
                                    label: 'Ultima compra',
                                    value: isLoading ? '...' : lastText,
                                    color: scheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  _buildSummaryTile(
                                    label: 'Total invertido',
                                    value: isLoading
                                        ? '...'
                                        : money.format(total),
                                    color: AppColors.success,
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    if (client.rnc?.isNotEmpty == true ||
                        client.cedula?.isNotEmpty == true) ...[
                      const SizedBox(height: 12),
                      _buildSectionCard(
                        title: 'Datos comerciales',
                        child: Column(
                          children: [
                            if (client.rnc?.isNotEmpty == true)
                              _buildInfoRow(
                                Icons.business_outlined,
                                'RNC',
                                client.rnc!,
                              ),
                            if (client.rnc?.isNotEmpty == true &&
                                client.cedula?.isNotEmpty == true)
                              const SizedBox(height: 8),
                            if (client.cedula?.isNotEmpty == true)
                              _buildInfoRow(
                                Icons.badge_outlined,
                                'Cedula',
                                client.cedula!,
                              ),
                          ],
                        ),
                      ),
                    ],
                    FutureBuilder<List<SaleModel>>(
                      future: _salesFuture,
                      builder: (context, snapshot) {
                        final sales = snapshot.data ?? <SaleModel>[];
                        if (sales.isEmpty &&
                            snapshot.connectionState !=
                                ConnectionState.waiting) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _buildSectionCard(
                            title: 'Ventas',
                            child:
                                snapshot.connectionState ==
                                    ConnectionState.waiting
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : snapshot.hasError
                                ? Text(
                                    'Error cargando ventas: ${snapshot.error}',
                                  )
                                : _buildDetailedSalesContent(sales),
                          ),
                        );
                      },
                    ),
                    FutureBuilder<List<SaleModel>>(
                      future: _quotesFuture,
                      builder: (context, snapshot) {
                        final quotes = snapshot.data ?? <SaleModel>[];
                        if (quotes.isEmpty &&
                            snapshot.connectionState !=
                                ConnectionState.waiting) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _buildSectionCard(
                            title: 'Cotizaciones',
                            child:
                                snapshot.connectionState ==
                                    ConnectionState.waiting
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : snapshot.hasError
                                ? Text(
                                    'Error cargando cotizaciones: ${snapshot.error}',
                                  )
                                : _buildDetailedQuotesContent(quotes),
                          ),
                        );
                      },
                    ),
                    FutureBuilder<List<SaleModel>>(
                      future: _returnsFuture,
                      builder: (context, snapshot) {
                        final returns = snapshot.data ?? <SaleModel>[];
                        if (returns.isEmpty &&
                            snapshot.connectionState !=
                                ConnectionState.waiting) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _buildSectionCard(
                            title: 'Devoluciones',
                            child:
                                snapshot.connectionState ==
                                    ConnectionState.waiting
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
                                : snapshot.hasError
                                ? Text(
                                    'Error cargando devoluciones: ${snapshot.error}',
                                  )
                                : _buildDetailedReturnsContent(returns),
                          ),
                        );
                      },
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

  Widget _buildDetailedSalesContent(List<SaleModel> sales) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final money = NumberFormat.currency(symbol: 'RD\$ ', decimalDigits: 2);

    // Calcular totales
    double totalVentas = 0;
    for (final sale in sales) {
      totalVentas += sale.total;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSummaryTile(
              label: 'Compras',
              value: '${sales.length}',
              color: AppColors.teal700,
            ),
            const SizedBox(width: 8),
            _buildSummaryTile(
              label: 'Visitas',
              value: '${sales.length}',
              color: AppColors.gold,
            ),
            const SizedBox(width: 8),
            _buildSummaryTile(
              label: 'Total',
              value: money.format(totalVentas),
              color: AppColors.success,
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sales.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final s = sales[i];
            final saleDate = DateTime.fromMillisecondsSinceEpoch(s.createdAtMs);

            return _buildTimelineCard(
              icon: Icons.receipt_long_outlined,
              title: s.localCode,
              subtitle:
                  '${dateFormat.format(saleDate)} • ${_paymentMethodLabel(s.paymentMethod)}',
              amount: money.format(s.total),
              accent: AppColors.teal700,
              trailing: (s.electronicInvoiceCode ?? '').isNotEmpty
                  ? 'e-CF: ${s.electronicInvoiceCode}'
                  : null,
            );
          },
        ),
      ],
    );
  }

  Widget _buildDetailedQuotesContent(List<SaleModel> quotes) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final money = NumberFormat.currency(symbol: 'RD\$ ', decimalDigits: 2);
    final totalQuotes = quotes.fold(0.0, (sum, sale) => sum + sale.total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSummaryTile(
              label: 'Cotizaciones',
              value: '${quotes.length}',
              color: AppColors.gold,
            ),
            const SizedBox(width: 8),
            _buildSummaryTile(
              label: 'Total',
              value: money.format(totalQuotes),
              color: AppColors.gold,
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: quotes.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final s = quotes[i];
            final saleDate = DateTime.fromMillisecondsSinceEpoch(s.createdAtMs);

            return _buildTimelineCard(
              icon: Icons.request_quote_outlined,
              title: s.localCode,
              subtitle:
                  '${dateFormat.format(saleDate)} • ${_paymentMethodLabel(s.paymentMethod)}',
              amount: money.format(s.total),
              accent: AppColors.gold,
              trailing: (s.electronicInvoiceCode ?? '').isNotEmpty
                  ? 'e-CF: ${s.electronicInvoiceCode}'
                  : null,
            );
          },
        ),
      ],
    );
  }

  Widget _buildDetailedReturnsContent(List<SaleModel> returnsList) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final money = NumberFormat.currency(symbol: 'RD\$ ', decimalDigits: 2);
    final totalReturns = returnsList.fold(0.0, (sum, sale) => sum + sale.total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildSummaryTile(
              label: 'Devoluciones',
              value: '${returnsList.length}',
              color: AppColors.error,
            ),
            const SizedBox(width: 8),
            _buildSummaryTile(
              label: 'Total',
              value: money.format(totalReturns),
              color: AppColors.error,
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: returnsList.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final s = returnsList[i];
            final saleDate = DateTime.fromMillisecondsSinceEpoch(s.createdAtMs);

            return _buildTimelineCard(
              icon: Icons.assignment_return_outlined,
              title: s.localCode,
              subtitle:
                  '${dateFormat.format(saleDate)} • ${_paymentMethodLabel(s.paymentMethod)}',
              amount: money.format(s.total),
              accent: AppColors.error,
              trailing: (s.electronicInvoiceCode ?? '').isNotEmpty
                  ? 'e-CF: ${s.electronicInvoiceCode}'
                  : null,
            );
          },
        ),
      ],
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
