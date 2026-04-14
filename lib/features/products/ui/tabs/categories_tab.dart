import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../data/categories_repository.dart';
import '../../models/category_model.dart';
import '../../../../core/security/app_actions.dart';
import '../../../../core/security/authorization_guard.dart';
import '../dialogs/category_form_dialog.dart';
import '../widgets/products_surface.dart';
import '../../../../core/sync/product_sync_event_bus.dart';
import '../../../../theme/app_colors.dart';

/// Tab de Categorías
class CategoriesTab extends StatefulWidget {
  const CategoriesTab({super.key, required this.onBackToCatalog});

  final VoidCallback onBackToCatalog;

  @override
  State<CategoriesTab> createState() => _CategoriesTabState();
}

class _CategoriesTabState extends State<CategoriesTab> {
  final CategoriesRepository _categoriesRepo = CategoriesRepository();
  StreamSubscription<ProductSyncChange>? _syncSubscription;
  Timer? _syncRefreshDebounce;

  List<CategoryModel> _categories = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _syncSubscription = ProductSyncEventBus.instance.stream.listen((_) {
      _syncRefreshDebounce?.cancel();
      _syncRefreshDebounce = Timer(
        const Duration(milliseconds: 250),
        _loadCategories,
      );
    });
    _loadCategories();
  }

  @override
  void dispose() {
    _syncRefreshDebounce?.cancel();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final categories = await _categoriesRepo.getAll(includeInactive: true);
      if (mounted) {
        setState(() => _categories = categories);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar categorías: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showCategoryForm([CategoryModel? category]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => CategoryFormDialog(category: category),
    );

    if (!mounted) return;
    if (result == true) {
      _loadCategories();
    }
  }

  Future<void> _toggleActive(CategoryModel category) async {
    try {
      await _categoriesRepo.toggleActive(category.id!, !category.isActive);
      _loadCategories();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              category.isActive
                  ? 'Categoría desactivada'
                  : 'Categoría activada',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _softDelete(CategoryModel category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          category.isDeleted ? 'Restaurar Categoría' : 'Eliminar Categoría',
        ),
        content: Text(
          category.isDeleted
              ? '¿Desea restaurar "${category.name}"?'
              : '¿Está seguro de eliminar "${category.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(category.isDeleted ? 'Restaurar' : 'Eliminar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final authorized = await requireAuthorizationIfNeeded(
          context: context,
          action: AppActions.deleteCategory,
          resourceType: 'category',
          resourceId: category.id?.toString(),
          reason: category.isDeleted
              ? 'Restaurar categoria'
              : 'Eliminar categoria',
        );
        if (!authorized) return;

        if (category.isDeleted) {
          await _categoriesRepo.restore(category.id!);
        } else {
          await _categoriesRepo.softDelete(category.id!);
        }
        _loadCategories();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                category.isDeleted
                    ? 'Categoría restaurada'
                    : 'Categoría eliminada',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
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
        const maxContentWidth = 940.0;
        final contentWidth = math.min(constraints.maxWidth, maxContentWidth);
        final side = ((constraints.maxWidth - contentWidth) / 2).clamp(12.0, 40.0);
        final padding = EdgeInsets.fromLTRB(side, 14, side, 16);
        final compact = contentWidth < 760;
        return Padding(
          padding: padding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ProductsSurface(
                      padding: EdgeInsets.zero,
                      radius: 20,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    compact
                                        ? 'Lista de categorías'
                                        : '${_categories.length} categorías registradas',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontFamily: 'Inter',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton.icon(
                                  onPressed: () => _showCategoryForm(),
                                  icon: const Icon(Icons.add, size: 18),
                                  label: Text(
                                    compact ? 'Nueva' : 'Nueva categoría',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primaryBlue,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: compact ? 14 : 16,
                                      vertical: 12,
                                    ),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontFamily: 'Inter',
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(height: 1, color: AppColors.borderSoft),
                          if (!compact)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      'Categoría',
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Estado',
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 90,
                                    child: Text(
                                      'Activa',
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 112,
                                    child: Text(
                                      'Acciones',
                                      textAlign: TextAlign.right,
                                      style: theme.textTheme.labelMedium?.copyWith(
                                        color: AppColors.textSecondary,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'Inter',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          Expanded(
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator())
                                : _categories.isEmpty
                                ? ProductsEmptyState(
                                    icon: Icons.category_outlined,
                                    title: 'Sin categorías',
                                    message: 'Crea la primera categoría para comenzar a organizar el inventario.',
                                    action: FilledButton.icon(
                                      onPressed: () => _showCategoryForm(),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Crear categoría'),
                                    ),
                                  )
                                : RefreshIndicator(
                                    onRefresh: _loadCategories,
                                    child: ListView.separated(
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      itemCount: _categories.length,
                                      separatorBuilder: (_, _) => Divider(
                                        height: 1,
                                        color: AppColors.borderSoft.withOpacity(0.75),
                                      ),
                                      itemBuilder: (context, index) {
                                        final category = _categories[index];
                                        return _buildCategoryRow(
                                          category,
                                          compact: compact,
                                          theme: theme,
                                          scheme: scheme,
                                        );
                                      },
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryRow(
    CategoryModel category, {
    required bool compact,
    required ThemeData theme,
    required ColorScheme scheme,
  }) {
    final isActive = category.isActive && !category.isDeleted;
    final badgeColor = category.isDeleted
        ? scheme.error
        : (isActive ? scheme.tertiary : const Color(0xFFF59E0B));
    final titleStyle = (compact
            ? theme.textTheme.titleSmall
            : theme.textTheme.bodyLarge)
        ?.copyWith(
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
          decoration: category.isDeleted ? TextDecoration.lineThrough : null,
          color: AppColors.textPrimary,
        );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCategoryAvatar(badgeColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category.name, style: titleStyle),
                      const SizedBox(height: 8),
                      _buildStatusBadge(
                        category.isDeleted
                            ? 'Eliminada'
                            : (category.isActive ? 'Activa' : 'Inactiva'),
                        badgeColor,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Disponible',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Inter',
                  ),
                ),
                const SizedBox(width: 8),
                Switch.adaptive(
                  value: category.isActive,
                  onChanged: category.isDeleted ? null : (_) => _toggleActive(category),
                  activeColor: AppColors.primaryBlue,
                ),
                const Spacer(),
                _buildActionIcon(
                  icon: Icons.edit_outlined,
                  color: AppColors.primaryBlue,
                  tooltip: 'Editar',
                  onPressed: () => _showCategoryForm(category),
                ),
                const SizedBox(width: 6),
                _buildActionIcon(
                  icon: category.isDeleted
                      ? Icons.restore_from_trash_outlined
                      : Icons.delete_outline,
                  color: category.isDeleted ? scheme.tertiary : scheme.error,
                  tooltip: category.isDeleted ? 'Restaurar' : 'Eliminar',
                  onPressed: () => _softDelete(category),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                _buildCategoryAvatar(badgeColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category.name,
                    style: titleStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _buildStatusBadge(
                category.isDeleted
                    ? 'Eliminada'
                    : (category.isActive ? 'Activa' : 'Inactiva'),
                badgeColor,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Center(
              child: Switch.adaptive(
                value: category.isActive,
                onChanged: category.isDeleted ? null : (_) => _toggleActive(category),
                activeColor: AppColors.primaryBlue,
              ),
            ),
          ),
          SizedBox(
            width: 112,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildActionIcon(
                  icon: Icons.edit_outlined,
                  color: AppColors.primaryBlue,
                  tooltip: 'Editar',
                  onPressed: () => _showCategoryForm(category),
                ),
                const SizedBox(width: 6),
                _buildActionIcon(
                  icon: category.isDeleted
                      ? Icons.restore_from_trash_outlined
                      : Icons.delete_outline,
                  color: category.isDeleted ? scheme.tertiary : scheme.error,
                  tooltip: category.isDeleted ? 'Restaurar' : 'Eliminar',
                  onPressed: () => _softDelete(category),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryAvatar(Color color) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.category_outlined, color: color, size: 18),
    );
  }

  Widget _buildStatusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          fontFamily: 'Inter',
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
      style: IconButton.styleFrom(backgroundColor: color.withOpacity(0.08)),
    );
  }
}
