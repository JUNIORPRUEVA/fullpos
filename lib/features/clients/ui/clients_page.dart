import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../data/client_model.dart';
import '../data/clients_repository.dart';
import '../../sales/data/sale_model.dart' as legacy_sales;
import '../../sales/data/sales_model.dart';
import '../../sales/data/sales_repository.dart';
import 'client_details_dialog.dart';
import 'client_form_dialog.dart';
import 'package:fullpos/features/clients/ui/widgets/client_row_tile.dart';

/// Filtros para la lista de clientes
class ClientFilters {
  String query;
  bool? isActive;
  bool? hasCredit;
  DateTime? fromDate;
  DateTime? toDate;
  bool includeDeleted;
  String orderBy;

  ClientFilters({
    this.query = '',
    this.isActive,
    this.hasCredit,
    this.fromDate,
    this.toDate,
    this.includeDeleted = false,
    this.orderBy = 'recent',
  });

  ClientFilters copyWith({
    String? query,
    bool? isActive,
    bool? hasCredit,
    DateTime? fromDate,
    DateTime? toDate,
    bool? includeDeleted,
    String? orderBy,
  }) {
    return ClientFilters(
      query: query ?? this.query,
      isActive: isActive ?? this.isActive,
      hasCredit: hasCredit ?? this.hasCredit,
      fromDate: fromDate ?? this.fromDate,
      toDate: toDate ?? this.toDate,
      includeDeleted: includeDeleted ?? this.includeDeleted,
      orderBy: orderBy ?? this.orderBy,
    );
  }

  void reset() {
    query = '';
    isActive = null;
    hasCredit = null;
    fromDate = null;
    toDate = null;
    includeDeleted = false;
    orderBy = 'recent';
  }
}

/// Pantalla de clientes
class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final _searchController = TextEditingController();
  final _filters = ClientFilters();

  List<ClientModel> _clients = [];
  ClientModel? _selectedClient;
  int? _selectedClientId;
  bool _isLoading = false;

  DateTime? _statsFromDate;
  DateTime? _statsToDate;
  late Future<Map<String, dynamic>> _statsFuture;

  @override
  void initState() {
    super.initState();
    _loadClients();
    _refreshStats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final clients = await ClientsRepository.list(
        query: _filters.query.isEmpty ? null : _filters.query,
        isActive: _filters.isActive,
        hasCredit: _filters.hasCredit,
        createdFromMs: _filters.fromDate?.millisecondsSinceEpoch,
        createdToMs: _filters.toDate != null
            ? DateTime(
                _filters.toDate!.year,
                _filters.toDate!.month,
                _filters.toDate!.day,
                23,
                59,
                59,
              ).millisecondsSinceEpoch
            : null,
        includeDeleted: _filters.includeDeleted,
        orderBy: _filters.orderBy,
      );

      if (mounted) {
        setState(() {
          _clients = clients;
          if (clients.isEmpty) {
            _selectedClient = null;
            _selectedClientId = null;
          } else {
            final currentId = _selectedClientId;
            if (currentId == null) {
              _selectedClient = clients.first;
              _selectedClientId = clients.first.id;
            } else {
              final match = clients.firstWhere(
                (c) => c.id == currentId,
                orElse: () => clients.first,
              );
              _selectedClient = match;
              _selectedClientId = match.id;
            }
          }
          _isLoading = false;
        });
      }
    } catch (e, st) {
      if (mounted) {
        setState(() => _isLoading = false);
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _loadClients,
          module: 'clients/list',
        );
      }
    }
  }

  void _refreshStats() {
    _statsFuture = SalesRepository.getClientsKpis(
      dateFrom: _statsFromDate,
      dateTo: _statsToDate,
    );
  }

  List<SaleModel> _normalizeSalesList(Iterable<dynamic> rawSales) {
    return rawSales
        .map<SaleModel?>((rawSale) {
          if (rawSale is SaleModel) {
            return rawSale;
          }
          if (rawSale is legacy_sales.SaleModel) {
            return SaleModel(
              id: rawSale.id,
              localCode: rawSale.localCode,
              kind: rawSale.kind,
              status: rawSale.status,
              customerId: rawSale.customerId,
              customerNameSnapshot: rawSale.customerNameSnapshot,
              customerPhoneSnapshot: rawSale.customerPhoneSnapshot,
              customerRncSnapshot: rawSale.customerRncSnapshot,
              itbisEnabled: rawSale.itbisEnabled ? 1 : 0,
              itbisRate: rawSale.itbisRate,
              discountTotal: rawSale.discountTotal,
              subtotal: rawSale.subtotal,
              itbisAmount: rawSale.itbisAmount,
              total: rawSale.total,
              paymentMethod: rawSale.paymentMethod,
              paidAmount: rawSale.paidAmount,
              changeAmount: rawSale.changeAmount,
              creditInterestRate: rawSale.creditInterestRate,
              creditTermDays: rawSale.creditTermDays,
              creditDueDateMs: rawSale.creditDueDateMs,
              creditInstallments: rawSale.creditInstallments,
              creditNote: rawSale.creditNote,
              fiscalEnabled: rawSale.fiscalEnabled ? 1 : 0,
              ncfFull: rawSale.ncfFull,
              ncfType: rawSale.ncfType,
              sessionId: rawSale.sessionId,
              createdAtMs: rawSale.createdAtMs,
              updatedAtMs: rawSale.updatedAtMs,
              deletedAtMs: rawSale.deletedAtMs,
            );
          }
          return null;
        })
        .whereType<SaleModel>()
        .toList(growable: false);
  }

  Future<void> _selectStatsDate(bool isFrom) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_statsFromDate ?? DateTime.now())
          : (_statsToDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date == null) return;
    if (!mounted) return;
    setState(() {
      if (isFrom) {
        _statsFromDate = date;
      } else {
        _statsToDate = date;
      }
      _refreshStats();
    });
  }

  Widget _buildKpiTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutedText = scheme.onSurface.withOpacity(0.7);

    return Container(
      padding: const EdgeInsets.all(AppSizes.paddingM),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
            child: Icon(icon, color: scheme.primary, size: 18),
          ),
          const SizedBox(width: AppSizes.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsPanel() {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final money = NumberFormat.currency(symbol: 'RD\$ ', decimalDigits: 2);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.paddingL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resumen de Clientes',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: AppSizes.spaceM),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectStatsDate(true),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _statsFromDate != null
                          ? dateFormat.format(_statsFromDate!)
                          : 'Desde',
                    ),
                  ),
                ),
                const SizedBox(width: AppSizes.spaceM),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectStatsDate(false),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(
                      _statsToDate != null
                          ? dateFormat.format(_statsToDate!)
                          : 'Hasta',
                    ),
                  ),
                ),
              ],
            ),
            if (_statsFromDate != null || _statsToDate != null) ...[
              const SizedBox(height: AppSizes.spaceS),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _statsFromDate = null;
                    _statsToDate = null;
                    _refreshStats();
                  });
                },
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Limpiar fechas'),
              ),
            ],
            const SizedBox(height: AppSizes.spaceL),
            FutureBuilder<Map<String, dynamic>>(
              future: _statsFuture,
              builder: (context, snapshot) {
                final loading =
                    snapshot.connectionState == ConnectionState.waiting;
                if (snapshot.hasError) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSizes.paddingM),
                    decoration: BoxDecoration(
                      color: scheme.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(AppSizes.radiusM),
                      border: Border.all(color: scheme.error.withOpacity(0.35)),
                    ),
                    child: Text(
                      'Error cargando resumen: ${snapshot.error}',
                      style: TextStyle(color: scheme.onSurface),
                    ),
                  );
                }

                final data = snapshot.data ?? const <String, dynamic>{};
                final clientsTotal = (data['clientsTotal'] as int?) ?? 0;
                final visitsCount = (data['visitsCount'] as int?) ?? 0;
                final totalPurchased =
                    (data['totalPurchased'] as num?)?.toDouble() ?? 0.0;

                return Column(
                  children: [
                    _buildKpiTile(
                      icon: Icons.people,
                      label: 'Clientes registrados',
                      value: loading ? '...' : clientsTotal.toString(),
                    ),
                    const SizedBox(height: AppSizes.spaceM),
                    _buildKpiTile(
                      icon: Icons.receipt_long,
                      label: 'Visitas (tickets)',
                      value: loading ? '...' : visitsCount.toString(),
                    ),
                    const SizedBox(height: AppSizes.spaceM),
                    _buildKpiTile(
                      icon: Icons.payments,
                      label: 'Total comprado',
                      value: loading ? '...' : money.format(totalPurchased),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showClientDialog([ClientModel? client]) async {
    final scheme = Theme.of(context).colorScheme;
    final result = await showDialog<ClientModel>(
      context: context,
      builder: (context) => ClientFormDialog(client: client),
    );

    if (result != null) {
      _loadClients();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              client == null
                  ? 'Cliente creado exitosamente'
                  : 'Cliente actualizado exitosamente',
            ),
            backgroundColor: scheme.tertiary,
          ),
        );
      }
    }
  }

  void _showClientDetails(ClientModel client) {
    showDialog(
      context: context,
      builder: (context) => ClientDetailsDialog(client: client),
    );
  }

  Future<void> _toggleActive(ClientModel client) async {
    final scheme = Theme.of(context).colorScheme;
    try {
      await ClientsRepository.toggleActive(client.id!, !client.isActive);
      _loadClients();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              client.isActive ? 'Cliente desactivado' : 'Cliente activado',
            ),
            backgroundColor: scheme.tertiary,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _toggleActive(client),
          module: 'clients/toggle_active',
        );
      }
    }
  }

  Future<void> _toggleCredit(ClientModel client) async {
    final scheme = Theme.of(context).colorScheme;
    try {
      await ClientsRepository.toggleCredit(client.id!, !client.hasCredit);
      _loadClients();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              client.hasCredit ? 'Crédito desactivado' : 'Crédito activado',
            ),
            backgroundColor: scheme.tertiary,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _toggleCredit(client),
          module: 'clients/toggle_credit',
        );
      }
    }
  }

  Future<void> _deleteClient(ClientModel client) async {
    final scheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminación'),
        content: Text('¿Está seguro de eliminar a ${client.nombre}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: scheme.error),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final authorized = await requireAuthorizationIfNeeded(
          context: context,
          action: AppActions.deleteClient,
          resourceType: 'client',
          resourceId: client.id?.toString(),
          reason: 'Eliminar cliente',
        );
        if (!authorized) return;

        await ClientsRepository.delete(client.id!);
        _loadClients();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Cliente eliminado'),
              backgroundColor: scheme.tertiary,
            ),
          );
        }
      } catch (e, st) {
        if (mounted) {
          await ErrorHandler.instance.handle(
            e,
            stackTrace: st,
            context: context,
            onRetry: () => _deleteClient(client),
            module: 'clients/delete',
          );
        }
      }
    }
  }

  Future<void> _exportClientsToExcel() async {
    final scheme = Theme.of(context).colorScheme;
    try {
      // Crear contenido CSV
      final StringBuffer csvBuffer = StringBuffer();

      // Encabezados
      csvBuffer.writeln(
        'ID,Nombre,Teléfono,Dirección,RNC,Cédula,Estado,Crédito,Fecha Registro',
      );

      // Datos de clientes
      final dateFormat = DateFormat('dd/MM/yyyy');
      for (final client in _clients) {
        final status = client.isActive ? 'Activo' : 'Inactivo';
        final credit = client.hasCredit ? 'Sí' : 'No';
        final createdDate = dateFormat.format(
          DateTime.fromMillisecondsSinceEpoch(client.createdAtMs),
        );

        // Escapar comillas en valores
        final nombre = '"${client.nombre.replaceAll('"', '""')}"';
        final direccion = '"${(client.direccion ?? '').replaceAll('"', '""')}"';

        csvBuffer.writeln(
          '${client.id},$nombre,${client.telefono ?? ''},$direccion,${client.rnc ?? ''},${client.cedula ?? ''},$status,$credit,$createdDate',
        );
      }

      // Obtener directorio de descargas
      final Directory? downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'No se pudo acceder al directorio de descargas',
              ),
              backgroundColor: scheme.error,
            ),
          );
        }
        return;
      }

      // Crear archivo
      final String timestamp = DateFormat(
        'yyyyMMdd_HHmmss',
      ).format(DateTime.now());
      final File file = File('${downloadsDir.path}/Clientes_$timestamp.csv');

      await file.writeAsString(csvBuffer.toString());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archivo exportado: ${file.path}'),
            backgroundColor: scheme.tertiary,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _exportClientsToExcel,
          module: 'clients/export',
        );
      }
    }
  }

  void _showFiltersDialog() {
    showDialog(
      context: context,
      builder: (context) => _FiltersDialog(
        filters: _filters,
        onApply: () {
          Navigator.pop(context);
          _loadClients();
        },
        onClear: () {
          setState(() {
            _filters.reset();
            _searchController.clear();
          });
          Navigator.pop(context);
          _loadClients();
        },
      ),
    );
  }

  Widget _buildClientsTopHeaderLine({required double minWidth}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final total = _clients.length;
    final activeCount = _clients.where((c) => c.isActive).length;
    final creditCount = _clients.where((c) => c.hasCredit).length;

    final summary = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              'Clientes: $total',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: scheme.tertiary.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.tertiary.withOpacity(0.28)),
            ),
            child: Text(
              'Activos: $activeCount',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: scheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.primary.withOpacity(0.26)),
            ),
            child: Text(
              'Crédito: $creditCount',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ),
        ],
      ),
    );

    final searchField = SizedBox(
      width: 320,
      height: 42,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar (nombre, teléfono, RNC, cédula...)',
          prefixIcon: const Icon(Icons.search, size: 18),
          isDense: true,
          filled: true,
          fillColor: scheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          suffixIcon: _searchController.text.trim().isNotEmpty
              ? IconButton(
                  tooltip: 'Limpiar búsqueda',
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _filters.query = '';
                    });
                    _loadClients();
                  },
                  icon: const Icon(Icons.clear, size: 18),
                )
              : null,
        ),
        onChanged: (value) {
          setState(() {
            _filters.query = value;
          });
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted) return;
            if (_filters.query == value) {
              _loadClients();
            }
          });
        },
      ),
    );

    return Container(
      width: double.infinity,
      color: scheme.surfaceVariant.withOpacity(0.22),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: minWidth),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.people, size: 22, color: scheme.primary),
                const SizedBox(width: 10),
                Text(
                  'Clientes',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(width: 12),
                searchField,
                const SizedBox(width: 12),
                summary,
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _showFiltersDialog,
                  icon: const Icon(Icons.filter_list, size: 18),
                  label: const Text('Filtros'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _exportClientsToExcel,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Exportar'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () => _showClientDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nuevo cliente'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _selectClient(ClientModel client, {required bool showDetails}) {
    if (!mounted) return;
    setState(() {
      _selectedClient = client;
      _selectedClientId = client.id;
    });
    if (showDetails) {
      _showClientDetails(client);
    }
  }

  Widget _buildClientsListHeader() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withOpacity(0.70);

    Text label(String text, {TextAlign? align}) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: theme.textTheme.labelSmall?.copyWith(
          color: muted,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.15,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.paddingM),
      height: 34,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppSizes.radiusM),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(flex: 2, child: label('Nombre')),
          const SizedBox(width: AppSizes.paddingM),
          Expanded(flex: 1, child: label('Teléfono')),
          const SizedBox(width: AppSizes.paddingS),
          Expanded(flex: 1, child: label('RNC')),
          const SizedBox(width: AppSizes.paddingS),
          Expanded(flex: 1, child: label('Cédula')),
          const SizedBox(width: AppSizes.paddingS),
          SizedBox(width: 64, child: label('Estado', align: TextAlign.center)),
          const SizedBox(width: AppSizes.paddingS),
          SizedBox(width: 88, child: label('Crédito', align: TextAlign.center)),
          const SizedBox(width: AppSizes.paddingS),
          SizedBox(width: 86, child: label('Creado', align: TextAlign.center)),
          const SizedBox(width: AppSizes.paddingS),
          SizedBox(width: 28, child: label('', align: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildClientDetailsPanel(ClientModel? client) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withOpacity(0.7);
    final money = NumberFormat.currency(symbol: 'RD\$ ', decimalDigits: 2);
    final dateLabel = DateFormat('dd/MM/yy HH:mm');

    if (client == null) {
      return Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detalle de cliente',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Selecciona un cliente para ver sus detalles.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      );
    }

    final createdAt = DateTime.fromMillisecondsSinceEpoch(client.createdAtMs);
    final createdLabel = DateFormat('dd/MM/yy HH:mm').format(createdAt);
    final initials = client.nombre.trim().isNotEmpty
        ? client.nombre.trim().substring(0, 1).toUpperCase()
        : '?';
    final activeColor = client.isActive ? scheme.tertiary : scheme.outline;
    final creditColor = client.hasCredit ? scheme.primary : scheme.outline;
    final phone = (client.telefono?.isNotEmpty == true) ? client.telefono! : '-';
    final rnc = (client.rnc?.isNotEmpty == true) ? client.rnc! : '-';
    final cedula = (client.cedula?.isNotEmpty == true) ? client.cedula! : '-';
    final direccion = (client.direccion?.isNotEmpty == true) ? client.direccion! : '-';

    Future<Map<String, dynamic>> loadPurchasesData() async {
      final summary = await SalesRepository.getCustomerPurchaseSummary(client.id!);
      final rawPurchases = await SalesRepository.listCustomerPurchases(
        client.id!,
        limit: 15,
      );
      final purchases = _normalizeSalesList(rawPurchases);
      final creditAmount = purchases
          .where((sale) => (sale.paymentMethod ?? '').toLowerCase() == 'credit')
          .fold<double>(0.0, (sum, sale) => sum + sale.total);
      return {
        'summary': summary,
        'purchases': purchases,
        'creditAmount': creditAmount,
      };
    }

    Widget chip(String text, Color color, {IconData? icon}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: scheme.onSurface),
              const SizedBox(width: 6),
            ],
            Text(
              text,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
                letterSpacing: 0.2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    Widget infoCard(String label, String value) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceVariant.withOpacity(0.28),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primary.withOpacity(0.12),
                  foregroundColor: scheme.primary,
                  child: Text(
                    initials,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    client.nombre,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Editar cliente',
                  onPressed: () => _showClientDialog(client),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                chip(client.isActive ? 'Activo' : 'Inactivo', activeColor),
                chip(
                  client.hasCredit ? 'Crédito' : 'Sin crédito',
                  creditColor,
                  icon: client.hasCredit ? Icons.credit_card : Icons.block,
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.2,
              children: [
                infoCard('Teléfono', phone),
                infoCard('RNC', rnc),
                infoCard('Cédula', cedula),
                infoCard('Creado', createdLabel),
              ],
            ),
            const SizedBox(height: 10),
            infoCard('Dirección', direccion),
            const SizedBox(height: 14),
            FutureBuilder<Map<String, dynamic>>(
              future: loadPurchasesData(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.error.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.error.withOpacity(0.28)),
                    ),
                    child: Text(
                      'No se pudo cargar compras del cliente.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }

                final data = snapshot.data ?? const <String, dynamic>{};
                final summary =
                    (data['summary'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
                final purchases = _normalizeSalesList(
                  (data['purchases'] as List?) ?? const <dynamic>[],
                );
                final creditAmount = (data['creditAmount'] as num?)?.toDouble() ?? 0.0;
                final purchasesCount = (summary['count'] as int?) ?? 0;
                final totalPurchased = (summary['total'] as num?)?.toDouble() ?? 0.0;
                final lastAtMs = (summary['lastAtMs'] as int?) ?? 0;
                final hasLastDate = lastAtMs > 0;

                Widget miniStat({
                  required String label,
                  required String value,
                  required IconData icon,
                }) {
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceVariant.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: scheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(icon, size: 16, color: scheme.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resumen comercial',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    miniStat(
                      label: 'Cantidad de ventas',
                      value: purchasesCount.toString(),
                      icon: Icons.receipt_long,
                    ),
                    const SizedBox(height: 8),
                    miniStat(
                      label: 'Total comprado',
                      value: money.format(totalPurchased),
                      icon: Icons.payments,
                    ),
                    const SizedBox(height: 8),
                    miniStat(
                      label: 'Monto en ventas a crédito',
                      value: money.format(creditAmount),
                      icon: Icons.credit_card,
                    ),
                    const SizedBox(height: 8),
                    miniStat(
                      label: 'Última compra',
                      value: hasLastDate
                          ? dateLabel.format(
                              DateTime.fromMillisecondsSinceEpoch(lastAtMs),
                            )
                          : '-',
                      icon: Icons.schedule,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Facturas compradas',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (purchases.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceVariant.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Este cliente no tiene facturas registradas.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      ...purchases.take(8).map((sale) {
                        final saleDate = DateTime.fromMillisecondsSinceEpoch(
                          sale.createdAtMs,
                        );
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceVariant.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sale.localCode,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      dateLabel.format(saleDate),
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: muted,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                money.format(sale.total),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
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
    );
  }

  EdgeInsets _contentPadding(BoxConstraints constraints) {
    const maxContentWidth = 1280.0;
    final contentWidth = math.min(constraints.maxWidth, maxContentWidth);
    final side = ((constraints.maxWidth - contentWidth) / 2)
        .clamp(12.0, 40.0)
        .toDouble();
    return EdgeInsets.fromLTRB(side, 16, side, 16);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mutedText = scheme.onSurface.withOpacity(0.6);

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = _contentPadding(constraints);
        final isWide = constraints.maxWidth >= 1200;
        final isNarrow = constraints.maxWidth < 980;
        final detailWidth = (constraints.maxWidth * 0.28)
            .clamp(320.0, 420.0)
            .toDouble();
        final headerMinWidth = math
            .max(0.0, constraints.maxWidth - padding.left - padding.right)
            .toDouble();

        final listCard = Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(AppSizes.radiusL),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.paddingM),
            child: Column(
              children: [
                if (_clients.isNotEmpty) ...[
                  _buildClientsListHeader(),
                  const SizedBox(height: AppSizes.spaceS),
                ],
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _clients.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.people_outline,
                                size: 64,
                                color: mutedText,
                              ),
                              const SizedBox(height: AppSizes.spaceM),
                              Text(
                                'No hay clientes',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: mutedText,
                                ),
                              ),
                              const SizedBox(height: AppSizes.spaceS),
                              Text(
                                _filters.query.isNotEmpty ||
                                        _filters.isActive != null ||
                                        _filters.hasCredit != null
                                    ? 'Intenta cambiar los filtros'
                                    : 'Haz clic en "Nuevo cliente" para agregar uno',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: mutedText,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _clients.length,
                          itemBuilder: (context, index) {
                            final client = _clients[index];
                            final isSelected = client.id != null
                                ? client.id == _selectedClientId
                                : identical(client, _selectedClient);
                            return ClientRowTile(
                              client: client,
                              isSelected: isSelected,
                              onViewDetails: () =>
                                  _selectClient(client, showDetails: !isWide),
                              onEdit: () => _showClientDialog(client),
                              onToggleActive: () => _toggleActive(client),
                              onToggleCredit: () => _toggleCredit(client),
                              onDelete: () => _deleteClient(client),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );

        return Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildClientsTopHeaderLine(minWidth: headerMinWidth),
              const SizedBox(height: AppSizes.spaceL),
              Expanded(
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: listCard),
                          const SizedBox(width: AppSizes.spaceL),
                          SizedBox(
                            width: detailWidth,
                            child: SizedBox.expand(
                              child: _buildClientDetailsPanel(_selectedClient),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          Flexible(flex: 3, child: listCard),
                          if (isNarrow) ...[
                            const SizedBox(height: AppSizes.spaceM),
                            Flexible(flex: 2, child: _buildAnalyticsPanel()),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Dialog para configurar filtros
class _FiltersDialog extends StatefulWidget {
  final ClientFilters filters;
  final VoidCallback onApply;
  final VoidCallback onClear;

  const _FiltersDialog({
    required this.filters,
    required this.onApply,
    required this.onClear,
  });

  @override
  State<_FiltersDialog> createState() => _FiltersDialogState();
}

class _FiltersDialogState extends State<_FiltersDialog> {
  late bool? _isActive;
  late bool? _hasCredit;
  late DateTime? _fromDate;
  late DateTime? _toDate;
  late bool _includeDeleted;
  late String _orderBy;

  @override
  void initState() {
    super.initState();
    _isActive = widget.filters.isActive;
    _hasCredit = widget.filters.hasCredit;
    _fromDate = widget.filters.fromDate;
    _toDate = widget.filters.toDate;
    _includeDeleted = widget.filters.includeDeleted;
    _orderBy = widget.filters.orderBy;
  }

  Future<void> _selectDate(bool isFrom) async {
    final date = await showDatePicker(
      context: context,
      initialDate: isFrom
          ? (_fromDate ?? DateTime.now())
          : (_toDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date == null) return;
    if (!mounted) return;
    setState(() {
      if (isFrom) {
        _fromDate = date;
      } else {
        _toDate = date;
      }
    });
  }

  void _applyFilters() {
    widget.filters.isActive = _isActive;
    widget.filters.hasCredit = _hasCredit;
    widget.filters.fromDate = _fromDate;
    widget.filters.toDate = _toDate;
    widget.filters.includeDeleted = _includeDeleted;
    widget.filters.orderBy = _orderBy;
    widget.onApply();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.paddingXL),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Título
              Row(
                children: [
                  Icon(Icons.filter_list, color: scheme.primary, size: 28),
                  const SizedBox(width: AppSizes.spaceM),
                  Text(
                    'Filtros',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSizes.spaceXL),

              // Estado
              const Text(
                'Estado',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSizes.spaceS),
              SegmentedButton<bool?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('Todos')),
                  ButtonSegment(value: true, label: Text('Activos')),
                  ButtonSegment(value: false, label: Text('Inactivos')),
                ],
                selected: {_isActive},
                onSelectionChanged: (Set<bool?> newSelection) {
                  setState(() => _isActive = newSelection.first);
                },
              ),
              const SizedBox(height: AppSizes.spaceL),

              // Crédito
              const Text(
                'Crédito',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSizes.spaceS),
              SegmentedButton<bool?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('Todos')),
                  ButtonSegment(value: true, label: Text('Con crédito')),
                  ButtonSegment(value: false, label: Text('Sin crédito')),
                ],
                selected: {_hasCredit},
                onSelectionChanged: (Set<bool?> newSelection) {
                  setState(() => _hasCredit = newSelection.first);
                },
              ),
              const SizedBox(height: AppSizes.spaceL),

              // Rango de fechas
              const Text(
                'Fecha de ingreso',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSizes.spaceS),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selectDate(true),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        _fromDate != null
                            ? dateFormat.format(_fromDate!)
                            : 'Desde',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSizes.spaceM),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _selectDate(false),
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(
                        _toDate != null ? dateFormat.format(_toDate!) : 'Hasta',
                      ),
                    ),
                  ),
                ],
              ),
              if (_fromDate != null || _toDate != null) ...[
                const SizedBox(height: AppSizes.spaceS),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _fromDate = null;
                      _toDate = null;
                    });
                  },
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Limpiar fechas'),
                ),
              ],
              const SizedBox(height: AppSizes.spaceL),

              // Orden
              const Text(
                'Ordenar por',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSizes.spaceS),
              DropdownButtonFormField<String>(
                initialValue: _orderBy,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSizes.paddingM,
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'recent',
                    child: Text('Más recientes'),
                  ),
                  DropdownMenuItem(value: 'old', child: Text('Más antiguos')),
                  DropdownMenuItem(value: 'name', child: Text('Nombre A-Z')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _orderBy = value);
                  }
                },
              ),
              const SizedBox(height: AppSizes.spaceL),

              // Incluir eliminados
              SwitchListTile(
                title: const Text('Mostrar clientes eliminados'),
                value: _includeDeleted,
                onChanged: (value) {
                  setState(() => _includeDeleted = value);
                },
                activeThumbColor: scheme.primary,
              ),
              const SizedBox(height: AppSizes.spaceXL),

              // Botones
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: widget.onClear,
                    child: const Text('Limpiar todo'),
                  ),
                  const SizedBox(width: AppSizes.spaceM),
                  ElevatedButton.icon(
                    onPressed: _applyFilters,
                    icon: const Icon(Icons.check),
                    label: const Text('Aplicar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
