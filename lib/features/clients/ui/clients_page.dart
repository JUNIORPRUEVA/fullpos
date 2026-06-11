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
import 'package:fullpos/features/clients/ui/widgets/client_row_tile.dart';
import 'package:fullpos/features/clients/ui/widgets/client_form_side_panel.dart';

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

      if (!mounted) return;

      setState(() {
        _clients = clients;

        if (clients.isEmpty) {
          _selectedClient = null;
          _selectedClientId = null;
        } else {
          final currentId = _selectedClientId;

          if (currentId != null) {
            final match = clients.firstWhere(
              (client) => client.id == currentId,
              orElse: () => clients.first,
            );
            _selectedClient = match;
            _selectedClientId = match.id;
          } else if (_selectedClient != null) {
            final fallback = clients.firstWhere(
              (client) => client.id == _selectedClient?.id,
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
    } catch (e, st) {
      if (!mounted) return;

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

  Future<void> _showClientDialog([ClientModel? client]) async {
    final scheme = Theme.of(context).colorScheme;
    final result = await showClientFormSidePanel(
      context,
      initialClient: client,
    );

    if (result == null) return;

    await _loadClients();

    if (!mounted) return;
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
      await _loadClients();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            client.isActive ? 'Cliente desactivado' : 'Cliente activado',
          ),
          backgroundColor: scheme.tertiary,
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => _toggleActive(client),
        module: 'clients/toggle_active',
      );
    }
  }

  Future<void> _toggleCredit(ClientModel client) async {
    final scheme = Theme.of(context).colorScheme;

    try {
      await ClientsRepository.toggleCredit(client.id!, !client.hasCredit);
      await _loadClients();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            client.hasCredit ? 'Crédito desactivado' : 'Crédito activado',
          ),
          backgroundColor: scheme.tertiary,
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => _toggleCredit(client),
        module: 'clients/toggle_credit',
      );
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

    if (confirm != true) return;

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
      await _loadClients();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cliente eliminado'),
          backgroundColor: scheme.tertiary,
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => _deleteClient(client),
        module: 'clients/delete',
      );
    }
  }

  Future<void> _exportClientsToExcel() async {
    final scheme = Theme.of(context).colorScheme;

    try {
      final csvBuffer = StringBuffer();

      csvBuffer.writeln(
        'ID,Nombre,Teléfono,Dirección,RNC,Cédula,Estado,Crédito,Fecha Registro',
      );

      final dateFormat = DateFormat('dd/MM/yyyy');

      for (final client in _clients) {
        final status = client.isActive ? 'Activo' : 'Inactivo';
        final credit = client.hasCredit ? 'Sí' : 'No';
        final createdDate = dateFormat.format(
          DateTime.fromMillisecondsSinceEpoch(client.createdAtMs),
        );

        final nombre = '"${client.nombre.replaceAll('"', '""')}"';
        final direccion = '"${(client.direccion ?? '').replaceAll('"', '""')}"';

        csvBuffer.writeln(
          '${client.id},$nombre,${client.telefono ?? ''},$direccion,${client.rnc ?? ''},${client.cedula ?? ''},$status,$credit,$createdDate',
        );
      }

      final downloadsDir = await getDownloadsDirectory();

      if (downloadsDir == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No se pudo acceder al directorio de descargas',
            ),
            backgroundColor: scheme.error,
          ),
        );
        return;
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${downloadsDir.path}/Clientes_$timestamp.csv');

      await file.writeAsString(csvBuffer.toString());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Archivo exportado: ${file.path}'),
          backgroundColor: scheme.tertiary,
        ),
      );
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _exportClientsToExcel,
        module: 'clients/export',
      );
    }
  }

  void _showFiltersSidePanel() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar filtros',
      barrierColor: Colors.black.withOpacity(0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 392,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 28,
                    offset: const Offset(-8, 0),
                  ),
                ],
              ),
              child: _FiltersSidePanel(
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
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  void _showClientDetailsSidePanel(ClientModel client) {
    if (!mounted) return;

    setState(() {
      _selectedClient = client;
      _selectedClientId = client.id;
    });

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar ficha del cliente',
      barrierColor: Colors.black.withOpacity(0.18),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 392,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 28,
                    offset: const Offset(-8, 0),
                  ),
                ],
              ),
              child: _ClientSideDetailsPanel(
                client: client,
                onClose: () => Navigator.of(context).pop(),
                onEdit: () {
                  Navigator.of(context).pop();
                  _showClientDialog(client);
                },
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  Widget _buildClientsActionsMenu() {
    return SizedBox(
      height: 48,
      child: PopupMenuButton<String>(
        tooltip: 'Acciones',
        onSelected: (value) {
          switch (value) {
            case 'new':
              _showClientDialog();
              break;
            case 'export':
              _exportClientsToExcel();
              break;
            case 'details':
              if (_selectedClient != null) {
                _showClientDetailsSidePanel(_selectedClient!);
              }
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'new',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.add_rounded),
              title: Text('Nuevo cliente'),
            ),
          ),
          const PopupMenuItem(
            value: 'export',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.download_rounded),
              title: Text('Exportar clientes'),
            ),
          ),
          PopupMenuItem(
            value: 'details',
            enabled: _selectedClient != null,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Abrir ficha'),
            ),
          ),
        ],
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A56DB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1A56DB)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.more_horiz_rounded, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Acciones',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, color: Colors.white, size: 18),
            ],
          ),
        ),
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
    final activeCount = _clients.where((client) => client.isActive).length;
    final creditCount = _clients.where((client) => client.hasCredit).length;

    Widget summaryBadge({
      required String label,
      required String value,
      required Color borderColor,
      Color? backgroundColor,
      Color? textColor,
    }) {
      return Expanded(
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.white,
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
                  fontWeight: FontWeight.w800,
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
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
        decoration: InputDecoration(
          hintText: 'Buscar cliente, teléfono, RNC o cédula',
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: scheme.onSurface.withOpacity(0.48),
          ),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: scheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF1A56DB), width: 1.6),
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
                  icon: const Icon(Icons.close_rounded, size: 18),
                )
              : null,
        ),
        onChanged: (value) {
          setState(() => _filters.query = value);

          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted) return;
            if (_filters.query == value) _loadClients();
          });
        },
      ),
    );

    final searchRow = Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: 10),
        SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _showFiltersSidePanel,
            icon: const Icon(Icons.filter_list_rounded, size: 18),
            label: const Text('Filtros'),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: scheme.onSurface,
              side: BorderSide(color: scheme.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildClientsActionsMenu(),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, headerConstraints) {
          final stacked = headerConstraints.maxWidth < 760;

          if (stacked) {
            return Column(
              children: [searchRow, const SizedBox(height: 10), summaryRow],
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
    );
  }

  void _selectClient(ClientModel client, {required bool showDetails}) {
    if (!mounted) return;

    setState(() {
      _selectedClient = client;
      _selectedClientId = client.id;
    });

    if (showDetails) {
      _showClientDetailsSidePanel(client);
    } else {
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

  EdgeInsets _contentPadding(BoxConstraints constraints) {
    const maxContentWidth = 1440.0;
    final contentWidth = math.min(constraints.maxWidth * 0.92, maxContentWidth);
    final side = ((constraints.maxWidth - contentWidth) / 2)
        .clamp(24.0, 160.0)
        .toDouble();

    return EdgeInsets.fromLTRB(side, 22, side, 24);
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
        final headerMinWidth = math
            .max(0.0, constraints.maxWidth - padding.left - padding.right)
            .toDouble();

        final listCard = Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outlineVariant.withOpacity(0.85)),
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
              Expanded(child: listCard),
            ],
          ),
        );
      },
    );
  }
}

class _ClientSideDetailsPanel extends StatelessWidget {
  const _ClientSideDetailsPanel({
    required this.client,
    required this.onClose,
    required this.onEdit,
  });

  final ClientModel client;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withOpacity(0.62);
    final border = scheme.outlineVariant.withOpacity(0.85);
    final dateFormat = DateFormat('dd/MM/yyyy');
    final dateTimeFormat = DateFormat('dd/MM/yy HH:mm');

    final createdAt = DateTime.fromMillisecondsSinceEpoch(client.createdAtMs);
    final initials = client.nombre.trim().isNotEmpty
        ? client.nombre.trim().substring(0, 1).toUpperCase()
        : '?';

    final phone = client.telefono?.trim().isNotEmpty == true
        ? client.telefono!.trim()
        : '-';
    final rnc = client.rnc?.trim().isNotEmpty == true
        ? client.rnc!.trim()
        : '-';
    final cedula = client.cedula?.trim().isNotEmpty == true
        ? client.cedula!.trim()
        : '-';
    final address = client.direccion?.trim().isNotEmpty == true
        ? client.direccion!.trim()
        : '-';

    Future<Map<String, dynamic>> loadActivity() {
      final id = client.id;

      if (id == null) {
        return Future.value(const {'count': 0, 'total': 0.0, 'lastAtMs': null});
      }

      return SalesRepository.getCustomerPurchaseSummary(
        id,
      ).catchError((_) => const {'count': 0, 'total': 0.0, 'lastAtMs': null});
    }

    Widget sectionTitle(String title) {
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.1,
          ),
        ),
      );
    }

    Widget cleanDivider() {
      return Divider(height: 1, thickness: 1, color: border);
    }

    Widget infoLine({
      required IconData icon,
      required String label,
      required String value,
      int maxLines = 1,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 16, color: const Color(0xFF1A56DB)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: muted,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    value,
                    maxLines: maxLines,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                      height: 1.18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget pill({
      required String text,
      required bool active,
      required IconData icon,
    }) {
      final color = active
          ? const Color(0xFF1A56DB)
          : scheme.onSurfaceVariant.withOpacity(0.85);

      return Expanded(
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? const Color(0xFFEAF2FF) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? const Color(0xFFBFD1F7) : scheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget activityBlock(Map<String, dynamic> data) {
      final count = (data['count'] as int?) ?? 0;
      final lastAtMs = data['lastAtMs'] as int?;
      final hasLast = lastAtMs != null && lastAtMs > 0;

      return Column(
        children: [
          infoLine(
            icon: Icons.receipt_long_outlined,
            label: 'Compras registradas',
            value: count.toString(),
          ),
          cleanDivider(),
          infoLine(
            icon: Icons.history_rounded,
            label: 'Última compra',
            value: hasLast
                ? dateFormat.format(
                    DateTime.fromMillisecondsSinceEpoch(lastAtMs),
                  )
                : 'Sin actividad',
          ),
          cleanDivider(),
          infoLine(
            icon: Icons.calendar_month_outlined,
            label: 'Cliente desde',
            value: dateTimeFormat.format(createdAt),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: border),
            ),
            child: Text(
              hasLast
                  ? 'Última interacción registrada el ${dateFormat.format(DateTime.fromMillisecondsSinceEpoch(lastAtMs))}.'
                  : 'Sin actividad comercial registrada todavía.',
              style: theme.textTheme.labelMedium?.copyWith(
                color: muted,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: border, width: 1)),
      ),
      child: Column(
        children: [
          Container(
            height: 64,
            padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Ficha del cliente',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.15,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Ocultar ficha',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFEAF2FF),
                        foregroundColor: const Color(0xFF1A56DB),
                        child: Text(
                          initials,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cliente seleccionado',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: muted,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                client.nombre,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Editar cliente',
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      pill(
                        text: client.isActive ? 'Activo' : 'Inactivo',
                        active: client.isActive,
                        icon: client.isActive
                            ? Icons.check_circle_outline_rounded
                            : Icons.pause_circle_outline_rounded,
                      ),
                      const SizedBox(width: 8),
                      pill(
                        text: client.hasCredit ? 'Crédito' : 'Sin crédito',
                        active: client.hasCredit,
                        icon: client.hasCredit
                            ? Icons.credit_card_rounded
                            : Icons.block_rounded,
                      ),
                    ],
                  ),
                  sectionTitle('Datos del cliente'),
                  infoLine(
                    icon: Icons.phone_outlined,
                    label: 'Teléfono',
                    value: phone,
                  ),
                  cleanDivider(),
                  infoLine(
                    icon: Icons.business_outlined,
                    label: 'RNC',
                    value: rnc,
                  ),
                  cleanDivider(),
                  infoLine(
                    icon: Icons.badge_outlined,
                    label: 'Cédula',
                    value: cedula,
                  ),
                  cleanDivider(),
                  infoLine(
                    icon: Icons.location_on_outlined,
                    label: 'Dirección',
                    value: address,
                    maxLines: 3,
                  ),
                  sectionTitle('Actividad'),
                  FutureBuilder<Map<String, dynamic>>(
                    future: loadActivity(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      return activityBlock(
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
}

class _FiltersSidePanel extends StatefulWidget {
  const _FiltersSidePanel({
    required this.filters,
    required this.onApply,
    required this.onClear,
  });

  final ClientFilters filters;
  final VoidCallback onApply;
  final VoidCallback onClear;

  @override
  State<_FiltersSidePanel> createState() => _FiltersSidePanelState();
}

class _FiltersSidePanelState extends State<_FiltersSidePanel> {
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

    return SafeArea(
      child: Column(
        children: [
          Container(
            height: 66,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.filter_list_rounded,
                  color: scheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Filtros de clientes',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Estado',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<bool?>(
                    segments: const [
                      ButtonSegment(value: null, label: Text('Todos')),
                      ButtonSegment(value: true, label: Text('Activos')),
                      ButtonSegment(value: false, label: Text('Inactivos')),
                    ],
                    selected: {_isActive},
                    onSelectionChanged: (value) {
                      setState(() => _isActive = value.first);
                    },
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Crédito',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<bool?>(
                    segments: const [
                      ButtonSegment(value: null, label: Text('Todos')),
                      ButtonSegment(value: true, label: Text('Con crédito')),
                      ButtonSegment(value: false, label: Text('Sin crédito')),
                    ],
                    selected: {_hasCredit},
                    onSelectionChanged: (value) {
                      setState(() => _hasCredit = value.first);
                    },
                  ),
                  const SizedBox(height: 22),
                  Text(
                    'Fecha de ingreso',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _selectDate(true),
                          icon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _fromDate != null
                                ? dateFormat.format(_fromDate!)
                                : 'Desde',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _selectDate(false),
                          icon: const Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                          ),
                          label: Text(
                            _toDate != null
                                ? dateFormat.format(_toDate!)
                                : 'Hasta',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_fromDate != null || _toDate != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _fromDate = null;
                          _toDate = null;
                        });
                      },
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Limpiar fechas'),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Text(
                    'Ordenar por',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _orderBy,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: scheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'recent',
                        child: Text('Más recientes'),
                      ),
                      DropdownMenuItem(
                        value: 'old',
                        child: Text('Más antiguos'),
                      ),
                      DropdownMenuItem(
                        value: 'name',
                        child: Text('Nombre A-Z'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _orderBy = value);
                    },
                  ),
                  const SizedBox(height: 18),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mostrar clientes eliminados'),
                    value: _includeDeleted,
                    onChanged: (value) {
                      setState(() => _includeDeleted = value);
                    },
                    activeThumbColor: scheme.primary,
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(top: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onClear,
                    child: const Text('Limpiar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _applyFilters,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Aplicar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                    ),
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
