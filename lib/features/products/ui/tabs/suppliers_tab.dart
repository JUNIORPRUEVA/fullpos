import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../data/suppliers_repository.dart';
import '../../models/supplier_model.dart';
import '../dialogs/supplier_form_dialog.dart';

/// Tab de Suplidores
class SuppliersTab extends StatefulWidget {
  const SuppliersTab({super.key});

  @override
  State<SuppliersTab> createState() => _SuppliersTabState();
}

class _SuppliersTabState extends State<SuppliersTab> {
  final SuppliersRepository _suppliersRepo = SuppliersRepository();
  final TextEditingController _searchController = TextEditingController();

  List<SupplierModel> _suppliers = [];
  List<SupplierModel> _filteredSuppliers = [];
  bool _isLoading = false;

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    _searchController.addListener(_filterSuppliers);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    if (!mounted) return;
    _safeSetState(() => _isLoading = true);
    try {
      final suppliers = await _suppliersRepo.getAll(includeInactive: true);
      if (!mounted) return;
      _safeSetState(() {
        _suppliers = suppliers;
        _filteredSuppliers = suppliers;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar suplidores: $e')),
        );
      }
    } finally {
      if (mounted) _safeSetState(() => _isLoading = false);
    }
  }

  void _filterSuppliers() {
    if (!mounted) return;
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredSuppliers = query.isEmpty
          ? _suppliers
          : _suppliers
              .where((s) =>
                  s.name.toLowerCase().contains(query) ||
                  (s.phone?.toLowerCase().contains(query) ?? false))
              .toList();
    });
  }

  Future<void> _showSupplierForm([SupplierModel? supplier]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => SupplierFormDialog(supplier: supplier),
    );

    if (!mounted) return;
    if (result == true) {
      _loadSuppliers();
    }
  }

  Future<void> _toggleActive(SupplierModel supplier) async {
    try {
      await _suppliersRepo.toggleActive(supplier.id!, !supplier.isActive);
      _loadSuppliers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              supplier.isActive
                  ? 'Suplidor desactivado'
                  : 'Suplidor activado',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _softDelete(SupplierModel supplier) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(supplier.isDeleted
            ? 'Restaurar Suplidor'
            : 'Eliminar Suplidor'),
        content: Text(
          supplier.isDeleted
              ? '¿Desea restaurar "${supplier.name}"?'
              : '¿Está seguro de eliminar "${supplier.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(supplier.isDeleted ? 'Restaurar' : 'Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        if (supplier.isDeleted) {
          await _suppliersRepo.restore(supplier.id!);
        } else {
          await _suppliersRepo.softDelete(supplier.id!);
        }
        _loadSuppliers();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                supplier.isDeleted
                    ? 'Suplidor restaurado'
                    : 'Suplidor eliminado',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final mutedText = scheme.onSurface.withOpacity(0.7);
        const maxContentWidth = 1280.0;
        final contentWidth = math.min(constraints.maxWidth, maxContentWidth);
        final side =
            ((constraints.maxWidth - contentWidth) / 2).clamp(12.0, 40.0);
        final padding = EdgeInsets.fromLTRB(side, 12, side, 12);

        return Column(
          children: [
            // Barra de búsqueda y acciones
            Padding(
              padding: padding,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Buscar por nombre o teléfono...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  _filterSuppliers();
                                },
                              )
                            : null,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _showSupplierForm(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nuevo'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Lista de suplidores
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredSuppliers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.business_outlined,
                                  size: 64,
                                  color: scheme.onSurface.withOpacity(0.3)),
                              const SizedBox(height: 16),
                              Text(
                                _searchController.text.isNotEmpty
                                    ? 'No se encontraron suplidores'
                                    : 'No hay suplidores registrados',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: mutedText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () => _showSupplierForm(),
                                icon: const Icon(Icons.add),
                                label: const Text('Crear Primero'),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadSuppliers,
                          child: ListView.builder(
                            padding: padding,
                            itemCount: _filteredSuppliers.length,
                            itemBuilder: (context, index) {
                              final supplier = _filteredSuppliers[index];
                              final isActive =
                                  supplier.isActive && !supplier.isDeleted;
                              final badgeColor = supplier.isDeleted
                                  ? scheme.error
                                  : (isActive ? scheme.tertiary : scheme.outline);
                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: scheme.outlineVariant),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withOpacity(0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.business,
                                        color: badgeColor,
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            supplier.name,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              decoration: supplier.isDeleted
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (supplier.phone != null)
                                            Text(
                                              supplier.phone!,
                                              style:
                                                  theme.textTheme.bodySmall
                                                      ?.copyWith(
                                                color: mutedText,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (supplier.note != null)
                                      Expanded(
                                        child: Text(
                                          supplier.note!,
                                          style:
                                              theme.textTheme.bodySmall?.copyWith(
                                            color: mutedText,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    if (supplier.isDeleted)
                                      _buildStatusBadge('DEL', scheme.error)
                                    else if (!supplier.isActive)
                                      _buildStatusBadge('INA', scheme.outline),
                                    const SizedBox(width: 6),
                                    _buildActionIcon(
                                      icon: supplier.isActive
                                          ? Icons.toggle_on
                                          : Icons.toggle_off,
                                      color: supplier.isActive
                                          ? scheme.tertiary
                                          : mutedText,
                                      tooltip: supplier.isActive
                                          ? 'Desactivar'
                                          : 'Activar',
                                      onPressed: () => _toggleActive(supplier),
                                    ),
                                    _buildActionIcon(
                                      icon: Icons.edit,
                                      color: scheme.primary,
                                      tooltip: 'Editar',
                                      onPressed: () =>
                                          _showSupplierForm(supplier),
                                    ),
                                    _buildActionIcon(
                                      icon: supplier.isDeleted
                                          ? Icons.restore_from_trash
                                          : Icons.delete,
                                      color: supplier.isDeleted
                                          ? scheme.tertiary
                                          : scheme.error,
                                      tooltip: supplier.isDeleted
                                          ? 'Restaurar'
                                          : 'Eliminar',
                                      onPressed: () => _softDelete(supplier),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildActionIcon({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      icon: Icon(icon, size: 20, color: color),
      onPressed: onPressed,
      tooltip: tooltip,
      padding: const EdgeInsets.all(6),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      visualDensity: VisualDensity.compact,
    );
  }
}
