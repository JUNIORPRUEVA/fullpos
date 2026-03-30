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
  bool _showDetailsPanel = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadClients();
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
            _showDetailsPanel = false;
          } else {
            final currentId = _selectedClientId;
            if (currentId != null) {
              final match = clients.firstWhere(
                (c) => c.id == currentId,
                orElse: () => clients.first,
              );
              _selectedClient = match;
              _selectedClientId = match.id;
            } else if (_selectedClient != null) {
              final fallback = clients.firstWhere(
                (c) => c.id == _selectedClient?.id,
                orElse: () => clients.first,
              );
              _selectedClient = fallback;
              _selectedClientId = fallback.id;
            } else {
              _selectedClient = null;
              _selectedClientId = null;
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

  Widget _buildClientsTopHeaderLine({
    required double minWidth,
    required bool isWide,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final total = _clients.length;
    final activeCount = _clients.where((c) => c.isActive).length;
    final creditCount = _clients.where((c) => c.hasCredit).length;

    Widget summaryBadge({
      required String label,
      required String value,
      required Color borderColor,
      Color? backgroundColor,
      Color? textColor,
    }) {
      return Expanded(
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor ?? scheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: textColor ?? scheme.onSurface.withOpacity(0.72),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: textColor ?? scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final searchField = SizedBox(
      height: 48,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar cliente por nombre, teléfono o RNC...',
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

    final selectedName = _selectedClient?.nombre;

    Widget panelButton() {
      return SizedBox(
        height: 48,
        child: OutlinedButton.icon(
          onPressed: isWide && _selectedClient != null
              ? () {
                  setState(() {
                    _showDetailsPanel = !_showDetailsPanel;
                  });
                }
              : null,
          icon: Icon(
            _showDetailsPanel
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            size: 18,
          ),
          label: Text(_showDetailsPanel ? 'Ocultar ficha' : 'Abrir ficha'),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
    }

    Widget selectedBadge() {
      return Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.primary.withOpacity(0.20)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                selectedName ?? 'Sin selección',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selectedName != null
                      ? scheme.primary
                      : scheme.onSurface.withOpacity(0.62),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: LayoutBuilder(
          builder: (context, headerConstraints) {
            final stacked = headerConstraints.maxWidth < 1080;
            final searchRow = Row(
              children: [
                Expanded(child: searchField),
                if (!stacked && isWide) ...[
                  const SizedBox(width: 10),
                  selectedBadge(),
                ],
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _showFiltersDialog,
                    icon: const Icon(Icons.filter_list, size: 18),
                    label: const Text('Filtros'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (isWide) ...[const SizedBox(width: 8), panelButton()],
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _exportClientsToExcel,
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Exportar'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => _showClientDialog(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nuevo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            );

            final summaryRow = Row(
              children: [
                summaryBadge(
                  label: 'Clientes',
                  value: '$total',
                  borderColor: scheme.outlineVariant,
                ),
                const SizedBox(width: 8),
                summaryBadge(
                  label: 'Activos',
                  value: '$activeCount',
                  borderColor: scheme.tertiary.withOpacity(0.28),
                  backgroundColor: scheme.tertiary.withOpacity(0.10),
                ),
                const SizedBox(width: 8),
                summaryBadge(
                  label: 'Crédito',
                  value: '$creditCount',
                  borderColor: scheme.primary.withOpacity(0.26),
                  backgroundColor: scheme.primary.withOpacity(0.10),
                  textColor: scheme.primary,
                ),
              ],
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isWide) ...[
                    SizedBox(width: double.infinity, child: selectedBadge()),
                    const SizedBox(height: 10),
                  ],
                  searchRow,
                  const SizedBox(height: 10),
                  summaryRow,
                ],
              );
            }

            return ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth),
              child: Column(
                children: [searchRow, const SizedBox(height: 10), summaryRow],
              ),
            );
          },
        ),
      ),
    );
  }

  void _selectClient(ClientModel client, {required bool showDetails}) {
    if (!mounted) return;
    setState(() {
      _selectedClient = client;
      _selectedClientId = client.id;
      if (showDetails) {
        _showDetailsPanel = true;
      }
    });
    if (!showDetails) {
      _showClientDetails(client);
    }
  }

  void _hideDetailsPanel() {
    if (!mounted) return;
    setState(() {
      _showDetailsPanel = false;
    });
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
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
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
    final dateLabel = DateFormat('dd/MM/yy');

    if (client == null) {
      return const SizedBox.shrink();
    }

    final createdAt = DateTime.fromMillisecondsSinceEpoch(client.createdAtMs);
    final createdLabel = DateFormat('dd/MM/yy HH:mm').format(createdAt);
    final initials = client.nombre.trim().isNotEmpty
        ? client.nombre.trim().substring(0, 1).toUpperCase()
        : '?';
    final activeColor = client.isActive ? scheme.tertiary : scheme.outline;
    final creditColor = client.hasCredit ? scheme.primary : scheme.outline;
    final phone = (client.telefono?.isNotEmpty == true)
        ? client.telefono!
        : '-';
    final rnc = (client.rnc?.isNotEmpty == true) ? client.rnc! : '-';
    final cedula = (client.cedula?.isNotEmpty == true) ? client.cedula! : '-';
    final direccion = (client.direccion?.isNotEmpty == true)
        ? client.direccion!
        : '-';

    Future<Map<String, dynamic>> loadActivityData() =>
        SalesRepository.getCustomerPurchaseSummary(client.id!);

    Widget badge(String label, String value, Color color, {IconData? icon}) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.28)),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: muted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget infoCard(String label, String value, {IconData? icon}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                if (icon != null) ...[
                  Icon(icon, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    Widget miniStat({
      required String label,
      required String value,
      required IconData icon,
    }) {
      return Container(
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
                Icon(icon, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    Widget buildActivityPanel(Map<String, dynamic> data) {
      final purchasesCount = (data['count'] as int?) ?? 0;
      final lastAtMs = (data['lastAtMs'] as int?) ?? 0;
      final hasLastDate = lastAtMs > 0;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Actividad',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: miniStat(
                  label: 'Compras registradas',
                  value: purchasesCount.toString(),
                  icon: Icons.receipt_long,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: miniStat(
                  label: 'Última compra',
                  value: hasLastDate
                      ? dateLabel.format(
                          DateTime.fromMillisecondsSinceEpoch(lastAtMs),
                        )
                      : 'Sin actividad',
                  icon: Icons.history_toggle_off,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: miniStat(
                  label: 'Cliente desde',
                  value: createdLabel,
                  icon: Icons.credit_card,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              badge(
                'Estado',
                client.isActive ? 'Operativo' : 'Inactivo',
                scheme.primary,
              ),
              const SizedBox(width: 8),
              badge(
                'Crédito',
                client.hasCredit ? 'Habilitado' : 'No disponible',
                scheme.tertiary,
                icon: client.hasCredit
                    ? Icons.credit_card
                    : Icons.block_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              hasLastDate
                  ? 'Última interacción registrada el ${dateLabel.format(DateTime.fromMillisecondsSinceEpoch(lastAtMs))}.'
                  : 'Sin actividad comercial registrada todavía.',
              style: theme.textTheme.labelMedium?.copyWith(
                color: muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ficha operativa',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Detalle activo del cliente seleccionado.',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ocultar ficha',
                onPressed: _hideDetailsPanel,
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: scheme.primary.withOpacity(0.18),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 20,
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cliente activo',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: muted,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    client.nombre,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Editar cliente',
                              onPressed: () => _showClientDialog(client),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            badge(
                              'Estado',
                              client.isActive ? 'Activo' : 'Inactivo',
                              activeColor,
                            ),
                            const SizedBox(width: 8),
                            badge(
                              'Crédito',
                              client.hasCredit ? 'Sí' : 'No',
                              creditColor,
                              icon: client.hasCredit
                                  ? Icons.credit_card
                                  : Icons.block,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.45,
                    children: [
                      infoCard('Teléfono', phone, icon: Icons.phone_outlined),
                      infoCard('RNC', rnc, icon: Icons.business_outlined),
                      infoCard('Cédula', cedula, icon: Icons.badge_outlined),
                      infoCard(
                        'Creado',
                        createdLabel,
                        icon: Icons.event_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  infoCard(
                    'Dirección',
                    direccion,
                    icon: Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<Map<String, dynamic>>(
                    future: loadActivityData(),
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
                            border: Border.all(
                              color: scheme.error.withOpacity(0.28),
                            ),
                          ),
                          child: Text(
                            'No se pudo cargar la actividad del cliente.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      }

                      return buildActivityPanel(
                        snapshot.data ?? const <String, dynamic>{},
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  EdgeInsets _contentPadding(BoxConstraints constraints) {
    const maxContentWidth = 1280.0;
    final contentWidth = math.min(constraints.maxWidth, maxContentWidth);
    final side = ((constraints.maxWidth - contentWidth) / 2)
        .clamp(12.0, 40.0)
        .toDouble();
    return EdgeInsets.fromLTRB(side, 12, side, 24);
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
        final detailWidth = (constraints.maxWidth * 0.33)
            .clamp(340.0, 460.0)
            .toDouble();
        final headerMinWidth = math
            .max(0.0, constraints.maxWidth - padding.left - padding.right)
            .toDouble();

        final listCard = Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              children: [
                if (_clients.isNotEmpty) ...[
                  _buildClientsListHeader(),
                  const SizedBox(height: 8),
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
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                          itemCount: _clients.length,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1, color: scheme.outlineVariant),
                          itemBuilder: (context, index) {
                            final client = _clients[index];
                            final isSelected = client.id != null
                                ? client.id == _selectedClientId
                                : identical(client, _selectedClient);
                            return ClientRowTile(
                              client: client,
                              isSelected: isSelected,
                              onViewDetails: () =>
                                  _selectClient(client, showDetails: true),
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
              _buildClientsTopHeaderLine(
                minWidth: headerMinWidth,
                isWide: isWide,
              ),
              const SizedBox(height: AppSizes.spaceL),
              Expanded(
                child: isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: listCard),
                          if (_showDetailsPanel && _selectedClient != null) ...[
                            const SizedBox(width: AppSizes.spaceL),
                            SizedBox(
                              width: detailWidth,
                              child: SizedBox.expand(
                                child: _buildClientDetailsPanel(
                                  _selectedClient,
                                ),
                              ),
                            ),
                          ],
                        ],
                      )
                    : Column(
                        children: [
                          Flexible(
                            flex: _showDetailsPanel && _selectedClient != null
                                ? 2
                                : 1,
                            child: listCard,
                          ),
                          if (isNarrow &&
                              _showDetailsPanel &&
                              _selectedClient != null) ...[
                            const SizedBox(height: AppSizes.spaceM),
                            Flexible(
                              flex: 3,
                              child: _buildClientDetailsPanel(_selectedClient),
                            ),
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
