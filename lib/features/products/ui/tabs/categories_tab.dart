import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../data/categories_repository.dart';
import '../../models/category_model.dart';
import '../../../../core/security/app_actions.dart';
import '../../../../core/security/authorization_guard.dart';
import '../dialogs/category_form_dialog.dart';
import '../../../../theme/app_colors.dart';

/// Tab de Categorías
class CategoriesTab extends StatefulWidget {
  const CategoriesTab({super.key});

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _softDelete(CategoryModel category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(category.isDeleted
            ? 'Restaurar Categoría'
            : 'Eliminar Categoría'),
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
          reason: category.isDeleted ? 'Restaurar categoria' : 'Eliminar categoria',
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
            // Barra de acciones
            Padding(
              padding: padding,
              child: Row(
                children: [
                  Text(
                    '${_categories.length} categorías',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Inter',
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () => _showCategoryForm(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nueva'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Inter',
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Lista de categorías
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _categories.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.category_outlined,
                                  size: 64, color: scheme.onSurface.withOpacity(0.3)),
                              const SizedBox(height: 16),
                              Text(
                                'No hay categorías registradas',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: mutedText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () => _showCategoryForm(),
                                icon: const Icon(Icons.add),
                                label: const Text('Crear Primera'),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadCategories,
                          child: ListView.builder(
                            padding: padding,
                            itemCount: _categories.length,
                            itemBuilder: (context, index) {
                              final category = _categories[index];
                              final isActive =
                                  category.isActive && !category.isDeleted;
                              final badgeColor = category.isDeleted
                                  ? scheme.error
                                  : (isActive ? scheme.tertiary : scheme.outline);

                              return Container(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppColors.borderSoft,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: scheme.shadow.withOpacity(0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  hoverColor: AppColors.lightBlueHover.withOpacity(0.55),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: badgeColor.withOpacity(0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.category_outlined,
                                          color: badgeColor,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          category.name,
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontWeight: FontWeight.w500,
                                            fontFamily: 'Inter',
                                            decoration: category.isDeleted
                                                ? TextDecoration.lineThrough
                                                : null,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (category.isDeleted)
                                        _buildStatusBadge('DEL', scheme.error)
                                      else if (!category.isActive)
                                        _buildStatusBadge('INA', scheme.outline),
                                      const SizedBox(width: 8),
                                      Switch.adaptive(
                                        value: category.isActive,
                                        onChanged: (_) => _toggleActive(category),
                                        activeColor: AppColors.primaryBlue,
                                      ),
                                      const SizedBox(width: 4),
                                      _buildActionIcon(
                                        icon: Icons.edit,
                                        color: AppColors.primaryBlue,
                                        tooltip: 'Editar',
                                        onPressed: () =>
                                            _showCategoryForm(category),
                                      ),
                                      _buildActionIcon(
                                        icon: category.isDeleted
                                            ? Icons.restore_from_trash
                                            : Icons.delete,
                                        color: category.isDeleted
                                            ? scheme.tertiary
                                            : scheme.error,
                                        tooltip: category.isDeleted
                                            ? 'Restaurar'
                                            : 'Eliminar',
                                        onPressed: () => _softDelete(category),
                                      ),
                                    ],
                                  ),
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
