import 'package:flutter/material.dart';

import '../../../../core/ui/app_toast.dart';
import '../../models/category_model.dart';
import '../../models/supplier_model.dart';
import '../../../../theme/app_colors.dart' as ui_colors;

/// Resultado del diálogo de edición masiva
class BulkEditResult {
  final int? categoryId;
  final int? supplierId;
  final double? stockMin;
  final bool categoryChanged;
  final bool supplierChanged;
  final bool stockMinChanged;

  const BulkEditResult({
    this.categoryId,
    this.supplierId,
    this.stockMin,
    this.categoryChanged = false,
    this.supplierChanged = false,
    this.stockMinChanged = false,
  });

  bool get hasChanges => categoryChanged || supplierChanged || stockMinChanged;
}

/// Diálogo para editar múltiples productos en lote
class BulkEditDialog extends StatefulWidget {
  final int productCount;
  final List<CategoryModel> categories;
  final List<SupplierModel> suppliers;

  const BulkEditDialog({
    super.key,
    required this.productCount,
    required this.categories,
    required this.suppliers,
  });

  @override
  State<BulkEditDialog> createState() => _BulkEditDialogState();
}

class _BulkEditDialogState extends State<BulkEditDialog> {
  int? _selectedCategoryId;
  int? _selectedSupplierId;
  final _stockMinController = TextEditingController();

  bool _categoryChanged = false;
  bool _supplierChanged = false;
  bool _stockMinChanged = false;

  @override
  void dispose() {
    _stockMinController.dispose();
    super.dispose();
  }

  bool get _hasAnyChange =>
      _categoryChanged || _supplierChanged || _stockMinChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeCategories = widget.categories
        .where((c) => c.isActive)
        .toList();
    final activeSuppliers = widget.suppliers.where((s) => s.isActive).toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.edit_note_rounded,
                      size: 22,
                      color: ui_colors.AppColors.primaryBlue,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Editar ${widget.productCount} productos',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFamily: 'Inter',
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Solo se actualizarán los campos que modifiques',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Categoría ---
                    _buildSectionLabel(
                      context,
                      icon: Icons.category_outlined,
                      label: 'Categoría',
                      subtitle:
                          'Asignar una categoría a todos los productos seleccionados',
                    ),
                    const SizedBox(height: 10),
                    _buildCategorySelector(activeCategories),
                    const SizedBox(height: 24),

                    // --- Suplidor ---
                    _buildSectionLabel(
                      context,
                      icon: Icons.local_shipping_outlined,
                      label: 'Suplidor / Proveedor',
                      subtitle:
                          'Asignar un suplidor a todos los productos seleccionados',
                    ),
                    const SizedBox(height: 10),
                    _buildSupplierSelector(activeSuppliers),
                    const SizedBox(height: 24),

                    // --- Stock mínimo ---
                    _buildSectionLabel(
                      context,
                      icon: Icons.inventory_2_outlined,
                      label: 'Stock mínimo de compra',
                      subtitle:
                          'Establecer el stock mínimo para todos los productos seleccionados',
                    ),
                    const SizedBox(height: 10),
                    _buildStockMinField(),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _hasAnyChange ? _onSave : null,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      'Aplicar a ${widget.productCount} productos',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: ui_colors.AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
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

  Widget _buildSectionLabel(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: ui_colors.AppColors.primaryBlue),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySelector(List<CategoryModel> categories) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD7E1EC)),
      ),
      child: Column(
        children: [
          _buildSelectorOption(
            label: 'Sin categoría',
            icon: Icons.block_outlined,
            isSelected: _categoryChanged && _selectedCategoryId == null,
            onTap: () {
              setState(() {
                _selectedCategoryId = null;
                _categoryChanged = true;
              });
            },
          ),
          if (categories.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No hay categorías disponibles',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
          ...categories.map(
            (cat) => _buildSelectorOption(
              label: cat.name,
              icon: Icons.category_outlined,
              isSelected: _categoryChanged && _selectedCategoryId == cat.id,
              onTap: () {
                setState(() {
                  _selectedCategoryId = cat.id;
                  _categoryChanged = true;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierSelector(List<SupplierModel> suppliers) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD7E1EC)),
      ),
      child: Column(
        children: [
          _buildSelectorOption(
            label: 'Sin suplidor',
            icon: Icons.block_outlined,
            isSelected: _supplierChanged && _selectedSupplierId == null,
            onTap: () {
              setState(() {
                _selectedSupplierId = null;
                _supplierChanged = true;
              });
            },
          ),
          if (suppliers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No hay suplidores disponibles',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ),
          ...suppliers.map(
            (sup) => _buildSelectorOption(
              label: sup.name,
              icon: Icons.local_shipping_outlined,
              isSelected: _supplierChanged && _selectedSupplierId == sup.id,
              onTap: () {
                setState(() {
                  _selectedSupplierId = sup.id;
                  _supplierChanged = true;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectorOption({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.transparent,
          border: Border(
            bottom: BorderSide(color: const Color(0xFFF1F5F9), width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected
                  ? ui_colors.AppColors.primaryBlue
                  : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? ui_colors.AppColors.primaryBlue
                      : const Color(0xFF1F2937),
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: ui_colors.AppColors.primaryBlue,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockMinField() {
    return TextField(
      controller: _stockMinController,
      keyboardType: TextInputType.number,
      onChanged: (value) {
        setState(() {
          _stockMinChanged = value.trim().isNotEmpty;
        });
      },
      decoration: InputDecoration(
        hintText: 'Dejar vacío para no modificar',
        hintStyle: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Color(0xFF94A3B8),
        ),
        prefixIcon: const Icon(
          Icons.exposure_zero_rounded,
          size: 20,
          color: Color(0xFF64748B),
        ),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD7E1EC)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFD7E1EC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: ui_colors.AppColors.primaryBlue.withOpacity(0.85),
            width: 1.8,
          ),
        ),
      ),
    );
  }

  void _onSave() {
    double? stockMin;
    if (_stockMinChanged) {
      final parsed = double.tryParse(_stockMinController.text.trim());
      if (parsed != null && parsed >= 0) {
        stockMin = parsed;
      } else {
        AppToast.show(
          context,
          'El stock mínimo debe ser un número válido mayor o igual a 0',
          type: AppToastType.warning,
        );
        return;
      }
    }

    Navigator.pop(
      context,
      BulkEditResult(
        categoryChanged: _categoryChanged,
        categoryId: _categoryChanged ? _selectedCategoryId : null,
        supplierChanged: _supplierChanged,
        supplierId: _supplierChanged ? _selectedSupplierId : null,
        stockMinChanged: _stockMinChanged,
        stockMin: stockMin,
      ),
    );
  }
}
