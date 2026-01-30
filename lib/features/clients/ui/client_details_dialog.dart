import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../data/client_model.dart';
import '../../sales/data/sales_repository.dart';
import '../../sales/data/sales_model.dart';
import '../../sales/data/sale_model.dart' show SaleKind;
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
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSizes.paddingM),
        decoration: BoxDecoration(
          color: AppColors.bgLight,
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
          border: Border.all(color: AppColors.teal700.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.teal700.withOpacity(0.25),
                borderRadius: BorderRadius.circular(AppSizes.radiusM),
              ),
              child: Icon(icon, color: AppColors.gold, size: 18),
            ),
            const SizedBox(width: AppSizes.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
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
    final dateOnlyFormat = DateFormat('dd/MM/yyyy');
    final money = NumberFormat.currency(symbol: 'RD\$ ', decimalDigits: 2);

    final createdDate = DateTime.fromMillisecondsSinceEpoch(client.createdAtMs);

    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 900, maxHeight: maxHeight),
        child: Column(
          children: [
            // Encabezado
            Container(
              padding: const EdgeInsets.all(AppSizes.paddingXL),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.teal900, AppColors.teal700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppSizes.radiusM),
                  topRight: Radius.circular(AppSizes.radiusM),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.gold,
                    child: Text(
                      (client.nombre.trim().isNotEmpty
                              ? client.nombre.trim().substring(0, 1)
                              : '?')
                          .toUpperCase(),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSizes.spaceL),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client.nombre,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSizes.spaceS),
                        if (client.telefono?.isNotEmpty == true)
                          Row(
                            children: [
                              const Icon(
                                Icons.phone,
                                size: 14,
                                color: AppColors.textPrimary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  client.telefono!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        if (client.telefono?.isNotEmpty == true)
                          const SizedBox(height: 6),
                        if (client.direccion?.isNotEmpty == true)
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on,
                                size: 14,
                                color: AppColors.textPrimary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  client.direccion!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        if (client.direccion?.isNotEmpty == true)
                          const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today,
                              size: 14,
                              color: AppColors.textPrimary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Ingreso: ${dateOnlyFormat.format(createdDate)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSizes.spaceS),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSizes.paddingM,
                                vertical: AppSizes.paddingS,
                              ),
                              decoration: BoxDecoration(
                                color: client.isActive
                                    ? AppColors.success
                                    : AppColors.error,
                                borderRadius: BorderRadius.circular(
                                  AppSizes.radiusS,
                                ),
                              ),
                              child: Text(
                                client.isActive ? 'ACTIVO' : 'INACTIVO',
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (client.hasCredit) ...[
                              const SizedBox(width: AppSizes.spaceS),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSizes.paddingM,
                                  vertical: AppSizes.paddingS,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.gold,
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.radiusS,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.credit_card,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'CRÉDITO',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (client.isDeleted) ...[
                              const SizedBox(width: AppSizes.spaceS),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSizes.paddingM,
                                  vertical: AppSizes.paddingS,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.error,
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.radiusS,
                                  ),
                                ),
                                child: const Text(
                                  'ELIMINADO',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppColors.textPrimary),
                  ),
                ],
              ),
            ),

            // Contenido
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSizes.paddingXL),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Resumen de compras - Estadísticas principales
                    const Text(
                      'Estadísticas del Cliente',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                    ),
                    const SizedBox(height: AppSizes.spaceM),
                    FutureBuilder<Map<String, dynamic>>(
                      future: _summaryFuture,
                      builder: (context, snapshot) {
                        final isLoading =
                            snapshot.connectionState == ConnectionState.waiting;

                        // Extraer datos con valores por defecto
                        Map<String, dynamic> data = snapshot.data ?? {};
                        if (data.isEmpty && !isLoading && !snapshot.hasError) {
                          data = {'count': 0, 'total': 0.0, 'lastAtMs': null};
                        }

                        final count = (data['count'] as int?) ?? 0;
                        final total =
                            (data['total'] as num?)?.toDouble() ?? 0.0;
                        final lastAtMs = data['lastAtMs'] as int?;
                        final lastText = lastAtMs == null || lastAtMs == 0
                            ? 'Sin compras'
                            : dateOnlyFormat.format(
                                DateTime.fromMillisecondsSinceEpoch(lastAtMs),
                              );

                        // Mostrar error si lo hay
                        if (snapshot.hasError) {
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(AppSizes.paddingM),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(
                                AppSizes.radiusM,
                              ),
                              border: Border.all(
                                color: AppColors.error.withOpacity(0.35),
                              ),
                            ),
                            child: Text(
                              'Error cargando estadísticas: ${snapshot.error}',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: [
                            Row(
                              children: [
                                _buildMetricCard(
                                  icon: Icons.receipt_long,
                                  label: 'Total de Compras',
                                  value: isLoading ? '...' : '$count',
                                ),
                                const SizedBox(width: AppSizes.spaceM),
                                _buildMetricCard(
                                  icon: Icons.directions_walk,
                                  label: 'Visitas',
                                  value: isLoading ? '...' : '$count',
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSizes.spaceM),
                            Row(
                              children: [
                                _buildMetricCard(
                                  icon: Icons.payments,
                                  label: 'Total Invertido',
                                  value: isLoading
                                      ? '...'
                                      : money.format(total),
                                ),
                                const SizedBox(width: AppSizes.spaceM),
                                _buildMetricCard(
                                  icon: Icons.event,
                                  label: 'Última Compra',
                                  value: isLoading ? '...' : lastText,
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: AppSizes.spaceXL),

                    // Información fiscal - solo si hay datos
                    if (client.rnc?.isNotEmpty == true ||
                        client.cedula?.isNotEmpty == true)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Información Fiscal',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.gold,
                            ),
                          ),
                          const SizedBox(height: AppSizes.spaceM),
                          if (client.rnc?.isNotEmpty == true)
                            _buildInfoRow(Icons.business, 'RNC', client.rnc!),
                          if (client.cedula?.isNotEmpty == true)
                            _buildInfoRow(
                              Icons.badge,
                              'Cédula',
                              client.cedula!,
                            ),
                          const SizedBox(height: AppSizes.spaceL),
                        ],
                      ),

                    // Historial de ventas
                    FutureBuilder<List<SaleModel>>(
                      future: _salesFuture,
                      builder: (context, snapshot) {
                        final sales = snapshot.data ?? <SaleModel>[];
                        final isEmpty =
                            sales.isEmpty &&
                            snapshot.connectionState != ConnectionState.waiting;

                        if (isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Historial de Ventas (Compras)',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold,
                              ),
                            ),
                            const SizedBox(height: AppSizes.spaceM),
                            if (snapshot.connectionState ==
                                ConnectionState.waiting)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (snapshot.hasError)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(
                                  AppSizes.paddingL,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.radiusM,
                                  ),
                                  border: Border.all(
                                    color: AppColors.error.withOpacity(0.35),
                                  ),
                                ),
                                child: Text(
                                  'Error cargando ventas: ${snapshot.error}',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              )
                            else
                              _buildDetailedSalesContent(sales),
                            const SizedBox(height: AppSizes.spaceXL),
                          ],
                        );
                      },
                    ),

                    // Historial de cotizaciones
                    FutureBuilder<List<SaleModel>>(
                      future: _quotesFuture,
                      builder: (context, snapshot) {
                        final quotes = snapshot.data ?? <SaleModel>[];
                        final isEmpty =
                            quotes.isEmpty &&
                            snapshot.connectionState != ConnectionState.waiting;

                        if (isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Historial de Cotizaciones',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold,
                              ),
                            ),
                            const SizedBox(height: AppSizes.spaceM),
                            if (snapshot.connectionState ==
                                ConnectionState.waiting)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (snapshot.hasError)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(
                                  AppSizes.paddingL,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.radiusM,
                                  ),
                                  border: Border.all(
                                    color: AppColors.error.withOpacity(0.35),
                                  ),
                                ),
                                child: Text(
                                  'Error cargando cotizaciones: ${snapshot.error}',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              )
                            else
                              _buildDetailedQuotesContent(quotes),
                            const SizedBox(height: AppSizes.spaceXL),
                          ],
                        );
                      },
                    ),

                    // Historial de devoluciones
                    FutureBuilder<List<SaleModel>>(
                      future: _returnsFuture,
                      builder: (context, snapshot) {
                        final returns = snapshot.data ?? <SaleModel>[];
                        final isEmpty =
                            returns.isEmpty &&
                            snapshot.connectionState != ConnectionState.waiting;

                        if (isEmpty) {
                          return const SizedBox.shrink();
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Historial de Devoluciones',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.gold,
                              ),
                            ),
                            const SizedBox(height: AppSizes.spaceM),
                            if (snapshot.connectionState ==
                                ConnectionState.waiting)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else if (snapshot.hasError)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(
                                  AppSizes.paddingL,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.radiusM,
                                  ),
                                  border: Border.all(
                                    color: AppColors.error.withOpacity(0.35),
                                  ),
                                ),
                                child: Text(
                                  'Error cargando devoluciones: ${snapshot.error}',
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              )
                            else
                              _buildDetailedReturnsContent(returns),
                            const SizedBox(height: AppSizes.spaceXL),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Footer - solo cerrar
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.paddingXL,
                0,
                AppSizes.paddingXL,
                AppSizes.paddingXL,
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  label: const Text('Cerrar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: AppColors.teal900,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSizes.paddingL,
                    ),
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
      children: [
        // Resumen de ventas
        Container(
          padding: const EdgeInsets.all(AppSizes.paddingM),
          decoration: BoxDecoration(
            color: AppColors.teal700.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            border: Border.all(color: AppColors.teal700.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  Text(
                    'Total de Compras',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${sales.length}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.teal700,
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  Text(
                    'Visitas',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${sales.length}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.gold,
                    ),
                  ),
                ],
              ),
              Column(
                children: [
                  Text(
                    'Total Invertido',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    money.format(totalVentas),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSizes.spaceL),
        // Lista detallada de ventas
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            border: Border.all(color: AppColors.teal700.withOpacity(0.2)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sales.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (context, i) {
              final s = sales[i];
              final saleDate = DateTime.fromMillisecondsSinceEpoch(
                s.createdAtMs,
              );

              return Container(
                padding: const EdgeInsets.all(AppSizes.paddingM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ticket: ${s.localCode}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Fecha: ${dateFormat.format(saleDate)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.teal700.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                money.format(s.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppColors.teal700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.payment,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Pago: ${_paymentMethodLabel(s.paymentMethod)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        if ((s.ncfFull ?? '').isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '• NCF: ${s.ncfFull}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
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
        // Resumen de cotizaciones
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(AppSizes.paddingM),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total de Cotizaciones',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${quotes.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSizes.spaceM),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(AppSizes.paddingM),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  border: Border.all(color: AppColors.gold.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Cotizado',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      money.format(totalQuotes),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.gold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.spaceL),
        // Lista detallada de cotizaciones
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            border: Border.all(color: AppColors.teal700.withOpacity(0.2)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: quotes.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (context, i) {
              final s = quotes[i];
              final saleDate = DateTime.fromMillisecondsSinceEpoch(
                s.createdAtMs,
              );

              return Container(
                padding: const EdgeInsets.all(AppSizes.paddingM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cotización: ${s.localCode}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Fecha: ${dateFormat.format(saleDate)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                money.format(s.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppColors.gold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.payment,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Pago: ${_paymentMethodLabel(s.paymentMethod)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        if ((s.ncfFull ?? '').isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '• NCF: ${s.ncfFull}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
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
        // Resumen de devoluciones
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(AppSizes.paddingM),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total de Devoluciones',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${returnsList.length}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSizes.spaceM),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(AppSizes.paddingM),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Devuelto',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      money.format(totalReturns),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.error,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.spaceL),
        // Lista detallada de devoluciones
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusM),
            border: Border.all(color: AppColors.teal700.withOpacity(0.2)),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: returnsList.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: Colors.grey.shade200),
            itemBuilder: (context, i) {
              final s = returnsList[i];
              final saleDate = DateTime.fromMillisecondsSinceEpoch(
                s.createdAtMs,
              );

              return Container(
                padding: const EdgeInsets.all(AppSizes.paddingM),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Devolución: ${s.localCode}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Fecha: ${dateFormat.format(saleDate)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                money.format(s.total),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: AppColors.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.payment,
                          size: 14,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Pago: ${_paymentMethodLabel(s.paymentMethod)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                        if ((s.ncfFull ?? '').isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            '• NCF: ${s.ncfFull}',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.spaceM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.gold),
          const SizedBox(width: AppSizes.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
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
