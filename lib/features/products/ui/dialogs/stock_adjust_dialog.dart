import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fullpos/core/security/app_actions.dart';
import 'package:fullpos/core/security/authorization_guard.dart';
import 'package:fullpos/core/session/session_manager.dart';
import 'package:fullpos/core/ui/dialog_keyboard_shortcuts.dart';
import 'package:fullpos/core/ui/app_toast.dart';
import '../../data/stock_repository.dart';
import '../../models/product_model.dart';
import '../../models/stock_movement_model.dart';
import '../widgets/products_surface.dart';

/// Diálogo para ajustar stock de un producto
class StockAdjustDialog extends StatefulWidget {
  final ProductModel product;

  const StockAdjustDialog({super.key, required this.product});

  @override
  State<StockAdjustDialog> createState() => _StockAdjustDialogState();
}

class _StockAdjustDialogState extends State<StockAdjustDialog>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _noteController = TextEditingController();
  final StockRepository _stockRepo = StockRepository();

  StockMovementType _selectedType = StockMovementType.input;
  bool _isLoading = false;
  late final AnimationController _entryController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _entryController,
      curve: Curves.easeOutCubic,
    );
    _scaleAnimation = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: _entryController, curve: Curves.easeOutCubic),
    );
    _entryController.forward();
  }

  Future<void> _dismissAnimated([Object? result]) async {
    if (_entryController.isAnimating) return;
    await _entryController.reverse();
    if (!mounted) return;
    Navigator.pop(context, result);
  }

  @override
  void dispose() {
    _entryController.dispose();
    _quantityController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final authorized = await requireAuthorizationIfNeeded(
      context: context,
      action: _actionForType(_selectedType),
      resourceType: 'product',
      resourceId: widget.product.id?.toString(),
      reason: 'Ajustar stock',
    );
    if (!authorized || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final quantity = double.parse(_quantityController.text.trim());
      final note = _noteController.text.trim();
      final currentUserId = await SessionManager.userId();
      final previousStock = widget.product.stock;

      await _stockRepo.adjustStock(
        productId: widget.product.id!,
        type: _selectedType,
        quantity: quantity,
        note: note.isEmpty ? null : note,
        userId: currentUserId,
      );

      final updatedStock = _calculateNewStock() ?? previousStock;

      if (mounted) {
        AppToast.show(
          context,
          'Stock ajustado correctamente',
          type: AppToastType.success,
        );
        await _dismissAnimated({
          'ok': true,
          'productId': widget.product.id,
          'updatedStock': updatedStock,
          'previousStock': previousStock,
          'type': _selectedType.name,
          'quantity': quantity,
        });
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          'Error: $e',
          type: AppToastType.error,
          duration: const Duration(seconds: 10),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double? _calculateNewStock() {
    final quantity = double.tryParse(_quantityController.text.trim());
    if (quantity == null) return null;

    switch (_selectedType) {
      case StockMovementType.input:
        return widget.product.stock + quantity;
      case StockMovementType.output:
        return widget.product.stock - quantity;
      case StockMovementType.adjust:
        return quantity;
    }
  }

  AppAction _actionForType(StockMovementType type) {
    switch (type) {
      case StockMovementType.input:
        return AppActions.addStock;
      case StockMovementType.output:
        return AppActions.removeStock;
      case StockMovementType.adjust:
        return AppActions.adjustInventory;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = (viewport.width * 0.33).clamp(420.0, 520.0);
    final dialogMaxHeight = (viewport.height - 24).clamp(420.0, 760.0);
    final newStock = _calculateNewStock();
    final isInput = _selectedType == StockMovementType.input;
    final typeColor = isInput ? scheme.tertiary : scheme.error;
    final actionLabel = isInput ? 'Agregar stock' : 'Restar stock';
    final actionIcon = isInput ? Icons.add_circle : Icons.remove_circle;

    return DialogKeyboardShortcuts(
      onSubmit: _isLoading ? null : _save,
      onCancel: () {
        if (_isLoading) return;
        _dismissAnimated();
      },
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: SizedBox.expand(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(96, 12, 4, 12),
                child: Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: EdgeInsets.zero,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: dialogWidth,
                      maxHeight: dialogMaxHeight,
                    ),
                    child: ProductsSurface(
                      padding: EdgeInsets.zero,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              border: Border(
                                bottom: BorderSide(
                                  color: scheme.outlineVariant,
                                ),
                              ),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(22),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'AJUSTAR STOCK',
                                    style: theme.textTheme.labelMedium
                                        ?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                  ),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _isLoading
                                      ? null
                                      : () => _dismissAnimated(),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                12,
                                14,
                                14,
                              ),
                              child: Form(
                                key: _formKey,
                                child: SingleChildScrollView(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: scheme.surface,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: scheme.outlineVariant,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.product.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              widget.product.code,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    'Actual ${widget.product.stock.toStringAsFixed(2)}',
                                                    style: theme
                                                        .textTheme
                                                        .bodyMedium
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              widget
                                                                      .product
                                                                      .stock <=
                                                                  0
                                                              ? scheme.error
                                                              : scheme.tertiary,
                                                        ),
                                                  ),
                                                ),
                                                Text(
                                                  'Min ${widget.product.stockMin.toStringAsFixed(2)}',
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      SegmentedButton<StockMovementType>(
                                        segments: const [
                                          ButtonSegment(
                                            value: StockMovementType.input,
                                            icon: Icon(
                                              Icons.add_circle_outline,
                                            ),
                                            label: Text('Agregar'),
                                          ),
                                          ButtonSegment(
                                            value: StockMovementType.output,
                                            icon: Icon(
                                              Icons.remove_circle_outline,
                                            ),
                                            label: Text('Restar'),
                                          ),
                                        ],
                                        selected: {_selectedType},
                                        onSelectionChanged: (selection) {
                                          setState(() {
                                            _selectedType = selection.first;
                                            _quantityController.clear();
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: _quantityController,
                                        enabled: !_isLoading,
                                        decoration: InputDecoration(
                                          labelText: isInput
                                              ? 'Cantidad +'
                                              : 'Cantidad -',
                                          isDense: true,
                                          filled: true,
                                          fillColor: Colors.white,
                                          border: const OutlineInputBorder(),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                          prefixIcon: Icon(
                                            actionIcon,
                                            color: typeColor,
                                          ),
                                        ),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'^\d+\.?\d{0,2}'),
                                          ),
                                        ],
                                        autofocus: true,
                                        onChanged: (_) => setState(() {}),
                                        validator: (value) {
                                          if (value == null ||
                                              value.trim().isEmpty) {
                                            return 'La cantidad es requerida';
                                          }
                                          final quantity = double.tryParse(
                                            value.trim(),
                                          );
                                          if (quantity == null ||
                                              quantity <= 0) {
                                            return 'Debe ser mayor que 0';
                                          }
                                          if (_selectedType ==
                                                  StockMovementType.output &&
                                              quantity > widget.product.stock) {
                                            return 'Stock insuficiente';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                      TextFormField(
                                        controller: _noteController,
                                        enabled: !_isLoading,
                                        decoration: const InputDecoration(
                                          labelText: 'Nota',
                                          isDense: true,
                                          filled: true,
                                          fillColor: Colors.white,
                                          border: OutlineInputBorder(),
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 12,
                                          ),
                                        ),
                                        maxLines: 2,
                                      ),
                                      if (newStock != null) ...[
                                        const SizedBox(height: 10),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                newStock <
                                                    widget.product.stockMin
                                                ? scheme.error.withOpacity(0.08)
                                                : scheme.tertiary.withOpacity(
                                                    0.08,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color:
                                                  newStock <
                                                      widget.product.stockMin
                                                  ? scheme.error.withOpacity(
                                                      0.35,
                                                    )
                                                  : scheme.tertiary.withOpacity(
                                                      0.35,
                                                    ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                newStock <
                                                        widget.product.stockMin
                                                    ? Icons
                                                          .warning_amber_rounded
                                                    : Icons
                                                          .check_circle_outline,
                                                color:
                                                    newStock <
                                                        widget.product.stockMin
                                                    ? scheme.error
                                                    : scheme.tertiary,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Nuevo stock ${newStock.toStringAsFixed(2)}',
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color:
                                                            newStock <
                                                                widget
                                                                    .product
                                                                    .stockMin
                                                            ? scheme.error
                                                            : scheme.tertiary,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 14),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: _isLoading
                                                ? null
                                                : () => _dismissAnimated(),
                                            child: const Text('Cancelar'),
                                          ),
                                          const SizedBox(width: 8),
                                          FilledButton.icon(
                                            onPressed: _isLoading
                                                ? null
                                                : _save,
                                            icon: _isLoading
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : Icon(actionIcon),
                                            label: Text(
                                              _isLoading
                                                  ? 'Guardando...'
                                                  : actionLabel,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
