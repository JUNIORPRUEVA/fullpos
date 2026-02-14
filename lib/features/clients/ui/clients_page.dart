import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../data/client_model.dart';
import '../data/clients_repository.dart';
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
        border: Border.all(color: AppColors.bgDark),
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
        border: Border.all(color: AppColors.bgDark),
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

    if (client == null) {
      return Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.all(16),
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

    Widget fieldRow(String label, String value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
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
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: scheme.primary.withOpacity(0.12),
                  foregroundColor: scheme.primary,
                  child: Text(
                    initials,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    client.nombre,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Abrir detalle',
                  onPressed: () => _showClientDetails(client),
                  icon: const Icon(Icons.open_in_new, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 10),
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
            const SizedBox(height: 12),
            fieldRow(
              'Teléfono',
              (client.telefono?.isNotEmpty == true) ? client.telefono! : '-',
            ),
            fieldRow(
              'RNC',
              (client.rnc?.isNotEmpty == true) ? client.rnc! : '-',
            ),
            fieldRow(
              'Cédula',
              (client.cedula?.isNotEmpty == true) ? client.cedula! : '-',
            ),
            fieldRow(
              'Dirección',
              (client.direccion?.isNotEmpty == true) ? client.direccion! : '-',
            ),
            fieldRow('Creado', createdLabel),
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
            border: Border.all(color: AppColors.bgDark),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSizes.paddingM),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre, telefono, RNC o cedula...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusM),
                      borderSide: const BorderSide(color: AppColors.bgDark),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppSizes.radiusM),
                      borderSide: const BorderSide(color: AppColors.bgDark),
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              _filters.query = '';
                              _loadClients();
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    _filters.query = value;
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (!mounted) return;
                      if (_filters.query == value) {
                        _loadClients();
                      }
                    });
                  },
                ),
                const SizedBox(height: AppSizes.spaceM),
                if (_clients.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSizes.spaceM),
                    child: Row(
                      children: [
                        Text(
                          '${_clients.length} cliente(s) encontrado(s)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: mutedText,
                          ),
                        ),
                      ],
                    ),
                  ),
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
              SizedBox(
                height: 44,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: headerMinWidth),
                    child: Row(
                      children: [
                        Icon(Icons.people, size: 28, color: scheme.primary),
                        const SizedBox(width: 10),
                        Text(
                          'Clientes',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        ElevatedButton.icon(
                          onPressed: _exportClientsToExcel,
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Exportar'),
                        ),
                        const SizedBox(width: AppSizes.spaceM),
                        OutlinedButton.icon(
                          onPressed: _showFiltersDialog,
                          icon: const Icon(Icons.filter_list, size: 18),
                          label: const Text('Filtros'),
                        ),
                        const SizedBox(width: AppSizes.spaceM),
                        ElevatedButton.icon(
                          onPressed: () => _showClientDialog(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Nuevo cliente'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: scheme.tertiary,
                            foregroundColor: scheme.onTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
