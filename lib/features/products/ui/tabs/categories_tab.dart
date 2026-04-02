import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../data/categories_repository.dart';
import '../../models/category_model.dart';
import '../../../../core/security/app_actions.dart';
import '../../../../core/security/authorization_guard.dart';
import '../dialogs/category_form_dialog.dart';
import '../widgets/products_surface.dart';
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

  List<CategoryModel> _categories = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
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
        const maxContentWidth = 1280.0;
        final contentWidth = math.min(constraints.maxWidth, maxContentWidth);
        final side = ((constraints.maxWidth - contentWidth) / 2).clamp(
          12.0,
          40.0,
        );
        final padding = EdgeInsets.fromLTRB(side, 8, side, 12);
        final compact = constraints.maxWidth < 840;
        final activeCount = _categories
            .where((category) => category.isActive && !category.isDeleted)
            .length;
        final inactiveCount = _categories
            .where((category) => !category.isActive && !category.isDeleted)
            .length;
        final deletedCount = _categories
            .where((category) => category.isDeleted)
            .length;

        return Padding(
          padding: padding,
          child: Column(
            children: [
              ProductsSurface(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: widget.onBackToCatalog,
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: const Text('Volver al catálogo'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              ProductsStatChip(
                                label: 'Total',
                                value: _categories.length.toString(),
                                icon: Icons.category_outlined,
                              ),
                              ProductsStatChip(
                                label: 'Activas',
                                value: activeCount.toString(),
                                icon: Icons.check_circle_outline,
                                color: scheme.tertiary,
                              ),
                              ProductsStatChip(
                                label: 'Inactivas',
                                value: inactiveCount.toString(),
                                icon: Icons.pause_circle_outline,
                                color: const Color(0xFFF59E0B),
                              ),
                              ProductsStatChip(
                                label: 'Archivadas',
                                value: deletedCount.toString(),
                                icon: Icons.delete_outline,
                                color: scheme.error,
                              ),
                            ],
                          ),
                        ),
                        if (!compact) ...[
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: () => _showCategoryForm(),
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Nueva'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Inter',
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (compact) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _showCategoryForm(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Nueva'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Inter',
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ProductsSurface(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                        child: Row(
                          children: [
                            Text(
                              '${_categories.length} categorías',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!compact)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
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
                                width: 120,
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
                      Divider(height: 1, color: AppColors.borderSoft),
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _categories.isEmpty
                            ? ProductsEmptyState(
                                icon: Icons.category_outlined,
                                title: 'Sin categorías',
                                message: '',
                                action: FilledButton.icon(
                                  onPressed: () => _showCategoryForm(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Crear categoría'),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _loadCategories,
                                child: ListView.separated(
                                  padding: const EdgeInsets.all(12),
                                  itemCount: _categories.length,
                                  separatorBuilder: (_, index) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (context, index) {
                                    final category = _categories[index];
                                    final isActive =
                                        category.isActive &&
                                        !category.isDeleted;
                                    final badgeColor = category.isDeleted
                                        ? scheme.error
                                        : (isActive
                                              ? scheme.tertiary
                                              : const Color(0xFFF59E0B));

                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: scheme.surface,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: AppColors.borderSoft,
                                        ),
                                      ),
                                      child: compact
                                          ? Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    _buildCategoryAvatar(
                                                      badgeColor,
                                                    ),
                                                    const SizedBox(width: 12),
                                                    Expanded(
                                                      child: Text(
                                                        category.name,
                                                        style: theme
                                                            .textTheme
                                                            .titleSmall
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              fontFamily:
                                                                  'Inter',
                                                              decoration:
                                                                  category
                                                                      .isDeleted
                                                                  ? TextDecoration
                                                                        .lineThrough
                                                                  : null,
                                                            ),
                                                      ),
                                                    ),
                                                    _buildStatusBadge(
                                                      category.isDeleted
                                                          ? 'Eliminada'
                                                          : (category.isActive
                                                                ? 'Activa'
                                                                : 'Inactiva'),
                                                      badgeColor,
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 12),
                                                Row(
                                                  children: [
                                                    const Spacer(),
                                                    Switch.adaptive(
                                                      value: category.isActive,
                                                      onChanged: (_) =>
                                                          _toggleActive(
                                                            category,
                                                          ),
                                                      activeColor:
                                                          AppColors.primaryBlue,
                                                    ),
                                                  ],
                                                ),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.end,
                                                  children: [
                                                    _buildActionIcon(
                                                      icon: Icons.edit_outlined,
                                                      color:
                                                          AppColors.primaryBlue,
                                                      tooltip: 'Editar',
                                                      onPressed: () =>
                                                          _showCategoryForm(
                                                            category,
                                                          ),
                                                    ),
                                                    _buildActionIcon(
                                                      icon: category.isDeleted
                                                          ? Icons
                                                                .restore_from_trash_outlined
                                                          : Icons
                                                                .delete_outline,
                                                      color: category.isDeleted
                                                          ? scheme.tertiary
                                                          : scheme.error,
                                                      tooltip:
                                                          category.isDeleted
                                                          ? 'Restaurar'
                                                          : 'Eliminar',
                                                      onPressed: () =>
                                                          _softDelete(category),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            )
                                          : Row(
                                              children: [
                                                Expanded(
                                                  flex: 4,
                                                  child: Row(
                                                    children: [
                                                      _buildCategoryAvatar(
                                                        badgeColor,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Text(
                                                          category.name,
                                                          style: theme
                                                              .textTheme
                                                              .bodyLarge
                                                              ?.copyWith(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                fontFamily:
                                                                    'Inter',
                                                                decoration:
                                                                    category
                                                                        .isDeleted
                                                                    ? TextDecoration
                                                                          .lineThrough
                                                                    : null,
                                                              ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: _buildStatusBadge(
                                                      category.isDeleted
                                                          ? 'Eliminada'
                                                          : (category.isActive
                                                                ? 'Activa'
                                                                : 'Inactiva'),
                                                      badgeColor,
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 90,
                                                  child: Center(
                                                    child: Switch.adaptive(
                                                      value: category.isActive,
                                                      onChanged: (_) =>
                                                          _toggleActive(
                                                            category,
                                                          ),
                                                      activeColor:
                                                          AppColors.primaryBlue,
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(
                                                  width: 120,
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.end,
                                                    children: [
                                                      _buildActionIcon(
                                                        icon:
                                                            Icons.edit_outlined,
                                                        color: AppColors
                                                            .primaryBlue,
                                                        tooltip: 'Editar',
                                                        onPressed: () =>
                                                            _showCategoryForm(
                                                              category,
                                                            ),
                                                      ),
                                                      _buildActionIcon(
                                                        icon: category.isDeleted
                                                            ? Icons
                                                                  .restore_from_trash_outlined
                                                            : Icons
                                                                  .delete_outline,
                                                        color:
                                                            category.isDeleted
                                                            ? scheme.tertiary
                                                            : scheme.error,
                                                        tooltip:
                                                            category.isDeleted
                                                            ? 'Restaurar'
                                                            : 'Eliminar',
                                                        onPressed: () =>
                                                            _softDelete(
                                                              category,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
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
        );
      },
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
