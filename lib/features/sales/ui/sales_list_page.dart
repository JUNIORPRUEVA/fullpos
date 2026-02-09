import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/sales_model.dart';
import '../data/sales_repository.dart';
import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/session/session_manager.dart';
import '../../../core/errors/error_handler.dart';
import '../../settings/data/printer_settings_repository.dart';

/// Página de lista de ventas realizadas (Historial completo)
class SalesListPage extends StatefulWidget {
  const SalesListPage({super.key});

  @override
  State<SalesListPage> createState() => _SalesListPageState();
}

class _SalesListPageState extends State<SalesListPage> {
  List<SaleModel> _sales = [];
  List<SaleModel> _filteredSales = [];
  bool _loading = true;

  // Filtros
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedPaymentMethod;
  String? _selectedStatus;
  final TextEditingController _searchController = TextEditingController();

  // Estadísticas
  double _totalVentas = 0;
  int _cantidadVentas = 0;

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  Future<void> _loadSales() async {
    _safeSetState(() => _loading = true);

    try {
      final sales = await DbHardening.instance.runDbSafe<List<SaleModel>>(
        () => SalesRepository.getAllSales(),
        stage: 'sales/history/load',
      );

      _safeSetState(() {
        _sales = sales;
        _applyFilters();
        _loading = false;
      });
    } catch (e, st) {
      _safeSetState(() => _loading = false);
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadSales,
        module: 'sales/history/load',
      );
    }
  }

  void _applyFilters() {
    var filtered = _sales.where((sale) {
      // Filtro por búsqueda
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!sale.localCode.toLowerCase().contains(query) &&
            !(sale.customerNameSnapshot?.toLowerCase().contains(query) ??
                false)) {
          return false;
        }
      }

      // Filtro por fecha
      if (_startDate != null) {
        final saleDate = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
        if (saleDate.isBefore(_startDate!)) return false;
      }
      if (_endDate != null) {
        final saleDate = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
        if (saleDate.isAfter(_endDate!.add(const Duration(days: 1)))) {
          return false;
        }
      }

      // Filtro por método de pago
      if (_selectedPaymentMethod != null &&
          sale.paymentMethod != _selectedPaymentMethod) {
        return false;
      }

      // Filtro por estado
      if (_selectedStatus != null && sale.status != _selectedStatus) {
        return false;
      }

      return true;
    }).toList();

    // Ordenar por fecha descendente
    filtered.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));

    _filteredSales = filtered;
    _totalVentas = filtered.fold(0.0, (sum, sale) => sum + sale.total);
    _cantidadVentas = filtered.length;
  }

  void _onSearchChanged(String value) {
    _safeSetState(() {
      _searchQuery = value;
      _applyFilters();
    });
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      locale: const Locale('es', 'DO'),
    );

    if (!mounted) return;
    if (picked != null) {
      _safeSetState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _applyFilters();
      });
    }
  }

  void _clearFilters() {
    _safeSetState(() {
      _searchQuery = '';
      _searchController.clear();
      _startDate = null;
      _endDate = null;
      _selectedPaymentMethod = null;
      _selectedStatus = null;
      _applyFilters();
    });
  }

  Future<void> _showSaleDetails(SaleModel sale) async {
    final items = await SalesRepository.getItemsBySaleId(sale.id!);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => _SaleDetailDialog(
        sale: sale,
        items: items,
        onReprint: () => _reprintTicket(sale, items),
        // En Historial de Ventas NO se permite anular/reembolsar.
        // Eso se gestiona únicamente desde la pantalla de Devoluciones.
        onCancel: null,
      ),
    );
  }

  Future<void> _reprintTicket(SaleModel sale, List<SaleItemModel> items) async {
    try {
      final settings = await PrinterSettingsRepository.getOrCreate();

      if (settings.selectedPrinterName == null ||
          settings.selectedPrinterName!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay impresora configurada'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Obtener nombre del cajero desde la sesión
      final cashierName = await SessionManager.displayName() ?? 'Cajero';

      final result = await UnifiedTicketPrinter.reprintSale(
        sale: sale,
        items: items,
        cashierName: cashierName,
        copies: 1,
      );
      final success = result.success;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success ? '✅ Ticket reimpreso' : '❌ Error al reimprimir',
            ),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _reprintTicket(sale, items),
          module: 'sales/history/reprint',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      // Deja ver el fondo global (AppFrame) para el degradado claro.
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Header con título y estadísticas
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              children: [
                // Título y botones
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.receipt_long,
                        color: Colors.teal,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'HISTORIAL DE VENTAS',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            'Registro completo de facturación',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    // Botón refrescar
                    IconButton(
                      onPressed: _loadSales,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Actualizar',
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Barra de búsqueda y filtros
                Row(
                  children: [
                    // Búsqueda
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Buscar por código o cliente...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade50,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Filtro de fecha
                    OutlinedButton.icon(
                      onPressed: _selectDateRange,
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        _startDate != null
                            ? '${DateFormat('dd/MM').format(_startDate!)} - ${DateFormat('dd/MM').format(_endDate!)}'
                            : 'FECHAS',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _startDate != null
                            ? Colors.teal
                            : Colors.grey.shade700,
                        side: BorderSide(
                          color: _startDate != null
                              ? Colors.teal
                              : Colors.grey.shade300,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Filtro método de pago
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        setState(() {
                          _selectedPaymentMethod = value == 'all'
                              ? null
                              : value;
                          _applyFilters();
                        });
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'all', child: Text('Todos')),
                        const PopupMenuItem(
                          value: 'cash',
                          child: Text('Efectivo'),
                        ),
                        const PopupMenuItem(
                          value: 'card',
                          child: Text('Tarjeta'),
                        ),
                        const PopupMenuItem(
                          value: 'transfer',
                          child: Text('Transferencia'),
                        ),
                        const PopupMenuItem(
                          value: 'mixed',
                          child: Text('Mixto'),
                        ),
                        const PopupMenuItem(
                          value: 'credit',
                          child: Text('Crédito'),
                        ),
                        const PopupMenuItem(
                          value: 'layaway',
                          child: Text('Apartado'),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _selectedPaymentMethod != null
                                ? Colors.teal
                                : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.payment,
                              size: 18,
                              color: _selectedPaymentMethod != null
                                  ? Colors.teal
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _getPaymentMethodLabel(_selectedPaymentMethod),
                              style: TextStyle(
                                fontSize: 12,
                                color: _selectedPaymentMethod != null
                                    ? Colors.teal
                                    : Colors.grey.shade700,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 18),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Filtro estado
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        setState(() {
                          _selectedStatus = value == 'all' ? null : value;
                          _applyFilters();
                        });
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'all', child: Text('Todos')),
                        const PopupMenuItem(
                          value: 'completed',
                          child: Text('✅ Completadas'),
                        ),
                        const PopupMenuItem(
                          value: 'cancelled',
                          child: Text('❌ Anuladas'),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _selectedStatus != null
                                ? Colors.teal
                                : Colors.grey.shade300,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.flag,
                              size: 18,
                              color: _selectedStatus != null
                                  ? Colors.teal
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _selectedStatus == 'completed'
                                  ? 'Activas'
                                  : _selectedStatus == 'cancelled'
                                  ? 'Anuladas'
                                  : 'Estado',
                              style: TextStyle(
                                fontSize: 12,
                                color: _selectedStatus != null
                                    ? Colors.teal
                                    : Colors.grey.shade700,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down, size: 18),
                          ],
                        ),
                      ),
                    ),

                    // Limpiar filtros
                    if (_searchQuery.isNotEmpty ||
                        _startDate != null ||
                        _selectedPaymentMethod != null ||
                        _selectedStatus != null)
                      IconButton(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.clear_all),
                        tooltip: 'Limpiar filtros',
                        color: Colors.red,
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                // Estadísticas
                Row(
                  children: [
                    _buildStatCard(
                      'VENTAS',
                      _cantidadVentas.toString(),
                      Icons.shopping_cart,
                      Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      'TOTAL',
                      '\$${NumberFormat('#,##0.00', 'en_US').format(_totalVentas)}',
                      Icons.attach_money,
                      Colors.green,
                    ),
                    const SizedBox(width: 12),
                    _buildStatCard(
                      'PROMEDIO',
                      _cantidadVentas > 0
                          ? '\$${(_totalVentas / _cantidadVentas).toStringAsFixed(2)}'
                          : '\$0.00',
                      Icons.analytics,
                      Colors.orange,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Lista de ventas
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSales.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No hay ventas registradas',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredSales.length,
                    itemBuilder: (context, index) {
                      final sale = _filteredSales[index];
                      return _buildSaleCard(sale);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: color,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSaleCard(SaleModel sale) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final muted = onSurface.withOpacity(0.68);

    final date = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
    final isCancelled = sale.status == 'cancelled';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        onTap: () => _showSaleDetails(sale),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: isCancelled
                ? Border.all(color: scheme.error.withOpacity(0.35), width: 2)
                : null,
          ),
          child: Row(
            children: [
              // Icono de estado
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isCancelled
                      ? scheme.error.withOpacity(0.10)
                      : scheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isCancelled ? Icons.cancel : Icons.receipt,
                  color: isCancelled ? scheme.error : scheme.primary,
                ),
              ),
              const SizedBox(width: 12),

              // Info principal
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          sale.localCode,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: onSurface,
                            decoration: isCancelled
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        if (isCancelled) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'ANULADA',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      sale.customerNameSnapshot ?? 'Cliente general',
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              // Método de pago
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getPaymentColor(sale.paymentMethod).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getPaymentIcon(sale.paymentMethod),
                      size: 14,
                      color: _getPaymentColor(sale.paymentMethod),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getPaymentMethodLabel(sale.paymentMethod),
                      style: TextStyle(
                        fontSize: 10,
                        color: _getPaymentColor(sale.paymentMethod),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Total y fecha
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '\$${sale.total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isCancelled ? muted : onSurface,
                      decoration: isCancelled
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  Text(
                    DateFormat('dd/MM/yy HH:mm').format(date),
                    style: TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: muted),
            ],
          ),
        ),
      ),
    );
  }

  String _getPaymentMethodLabel(String? method) {
    switch (method) {
      case 'cash':
        return 'EFECTIVO';
      case 'card':
        return 'TARJETA';
      case 'transfer':
        return 'TRANSF';
      case 'mixed':
        return 'MIXTO';
      case 'credit':
        return 'CRÉDITO';
      case 'layaway':
        return 'APARTADO';
      default:
        return 'PAGO';
    }
  }

  IconData _getPaymentIcon(String? method) {
    switch (method) {
      case 'cash':
        return Icons.money;
      case 'card':
        return Icons.credit_card;
      case 'transfer':
        return Icons.account_balance;
      case 'mixed':
        return Icons.payments;
      case 'credit':
        return Icons.request_quote;
      case 'layaway':
        return Icons.bookmark;
      default:
        return Icons.payment;
    }
  }

  Color _getPaymentColor(String? method) {
    switch (method) {
      case 'cash':
        return Colors.green;
      case 'card':
        return Colors.blue;
      case 'transfer':
        return Colors.purple;
      case 'mixed':
        return Colors.orange;
      case 'credit':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

/// Diálogo de detalle de venta
class _SaleDetailDialog extends StatelessWidget {
  final SaleModel sale;
  final List<SaleItemModel> items;
  final VoidCallback onReprint;
  final VoidCallback? onCancel;

  const _SaleDetailDialog({
    required this.sale,
    required this.items,
    required this.onReprint,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateTime.fromMillisecondsSinceEpoch(sale.createdAtMs);
    final isCancelled = sale.status == 'cancelled';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isCancelled ? Colors.red : Colors.teal,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isCancelled ? Icons.cancel : Icons.receipt_long,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sale.localCode,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(date),
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  if (isCancelled)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'ANULADA',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cliente
                    if (sale.customerNameSnapshot != null) ...[
                      _buildInfoRow('Cliente', sale.customerNameSnapshot!),
                      if (sale.customerPhoneSnapshot != null)
                        _buildInfoRow('Teléfono', sale.customerPhoneSnapshot!),
                      const Divider(height: 24),
                    ],

                    // Items
                    const Text(
                      'PRODUCTOS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...items.map(
                      (item) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.teal.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: Text(
                                  '${item.qty.toInt()}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal.shade700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productNameSnapshot,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    item.productCodeSnapshot,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '\$${item.unitPrice.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                Text(
                                  '\$${item.totalLine.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Divider(height: 24),

                    // Totales
                    _buildTotalRow(
                      'Subtotal',
                      '\$${sale.subtotal.toStringAsFixed(2)}',
                    ),
                    if (sale.discountTotal > 0)
                      _buildTotalRow(
                        'Descuento',
                        '-\$${sale.discountTotal.toStringAsFixed(2)}',
                        color: Colors.red,
                      ),
                    if (sale.itbisEnabled == 1)
                      _buildTotalRow(
                        'ITBIS (${(sale.itbisRate * 100).toInt()}%)',
                        '\$${sale.itbisAmount.toStringAsFixed(2)}',
                      ),
                    const Divider(height: 16),
                    _buildTotalRow(
                      'TOTAL',
                      '\$${sale.total.toStringAsFixed(2)}',
                      isBold: true,
                      fontSize: 18,
                    ),

                    const SizedBox(height: 12),

                    // Pago
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _buildTotalRow(
                            'Método',
                            _getPaymentMethodLabel(sale.paymentMethod),
                          ),
                          _buildTotalRow(
                            'Recibido',
                            '\$${sale.paidAmount.toStringAsFixed(2)}',
                          ),
                          if (sale.changeAmount > 0)
                            _buildTotalRow(
                              'Cambio',
                              '\$${sale.changeAmount.toStringAsFixed(2)}',
                            ),
                        ],
                      ),
                    ),

                    // NCF si existe
                    if (sale.ncfFull != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.receipt, color: Colors.amber),
                            const SizedBox(width: 8),
                            Text(
                              'NCF: ${sale.ncfFull}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Footer con acciones
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  if (onCancel != null && !isCancelled)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.cancel),
                        label: const Text('ANULAR'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  if (onCancel != null && !isCancelled)
                    const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onReprint,
                      icon: const Icon(Icons.print),
                      label: const Text('REIMPRIMIR'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text('$label: ', style: TextStyle(color: Colors.grey.shade600)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildTotalRow(
    String label,
    String value, {
    bool isBold = false,
    double fontSize = 14,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              fontSize: fontSize,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              fontSize: fontSize,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _getPaymentMethodLabel(String? method) {
    switch (method) {
      case 'cash':
        return 'Efectivo';
      case 'card':
        return 'Tarjeta';
      case 'transfer':
        return 'Transferencia';
      case 'mixed':
        return 'Mixto';
      case 'credit':
        return 'Crédito';
      case 'layaway':
        return 'Apartado';
      default:
        return 'N/A';
    }
  }
}
