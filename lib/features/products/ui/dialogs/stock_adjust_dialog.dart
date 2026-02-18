import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:fullpos/core/security/app_actions.dart';
import 'package:fullpos/core/security/authorization_guard.dart';
import 'package:fullpos/core/session/session_manager.dart';
import 'package:fullpos/core/ui/dialog_keyboard_shortcuts.dart';
import 'package:fullpos/core/ui/dialog_sizes.dart';
import '../../data/stock_repository.dart';
import '../../models/product_model.dart';
import '../../models/stock_movement_model.dart';

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
    _scaleAnimation = Tween<double>(
      begin: 0.97,
      end: 1.0,
    ).animate(
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
      action: AppActions.adjustStock,
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
        await _dismissAnimated({
          'ok': true,
          'productId': widget.product.id,
          'updatedStock': updatedStock,
          'previousStock': previousStock,
          'type': _selectedType.name,
          'quantity': quantity,
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock ajustado correctamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
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
          child: AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
            contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: typeColor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: typeColor.withOpacity(0.35)),
          ),
          child: Row(
            children: [
              Icon(actionIcon, color: typeColor),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Ajuste de Stock',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                isInput ? 'ENTRADA' : 'SALIDA',
                style: TextStyle(
                  color: typeColor,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
            content: ConstrainedBox(
          constraints: DialogSizes.medium(context),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceVariant.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Código: ${widget.product.code}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withOpacity(0.72),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Stock actual: ',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              widget.product.stock.toStringAsFixed(2),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: widget.product.stock <= 0
                                    ? scheme.error
                                    : scheme.tertiary,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              'Mínimo: ${widget.product.stockMin.toStringAsFixed(2)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurface.withOpacity(0.75),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Operación',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<StockMovementType>(
                    segments: const [
                      ButtonSegment(
                        value: StockMovementType.input,
                        icon: Icon(Icons.add_circle_outline),
                        label: Text('Agregar'),
                      ),
                      ButtonSegment(
                        value: StockMovementType.output,
                        icon: Icon(Icons.remove_circle_outline),
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
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _quantityController,
                    enabled: !_isLoading,
                    decoration: InputDecoration(
                      labelText: isInput
                          ? 'Cantidad a agregar *'
                          : 'Cantidad a restar *',
                      hintText: 'Ej: 5.00',
                      border: const OutlineInputBorder(),
                      prefixIcon: Icon(actionIcon, color: typeColor),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'La cantidad es requerida';
                      }
                      final quantity = double.tryParse(value.trim());
                      if (quantity == null || quantity <= 0) {
                        return 'Debe ser mayor que 0';
                      }
                      if (_selectedType == StockMovementType.output &&
                          quantity > widget.product.stock) {
                        return 'Stock insuficiente (actual: ${widget.product.stock.toStringAsFixed(2)})';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _noteController,
                    enabled: !_isLoading,
                    decoration: const InputDecoration(
                      labelText: 'Nota (opcional)',
                      hintText: 'Motivo del movimiento',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.notes_outlined),
                    ),
                    maxLines: 2,
                  ),
                  if (newStock != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: newStock < widget.product.stockMin
                            ? scheme.error.withOpacity(0.08)
                            : scheme.tertiary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: newStock < widget.product.stockMin
                              ? scheme.error.withOpacity(0.45)
                              : scheme.tertiary.withOpacity(0.45),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            newStock < widget.product.stockMin
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline,
                            color: newStock < widget.product.stockMin
                                ? scheme.error
                                : scheme.tertiary,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Nuevo stock proyectado',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface.withOpacity(0.78),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  newStock.toStringAsFixed(2),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: newStock < widget.product.stockMin
                                        ? scheme.error
                                        : scheme.tertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
            actions: [
              OutlinedButton(
                onPressed: _isLoading ? null : () => _dismissAnimated(),
                child: const Text('Cancelar (Esc)'),
              ),
              FilledButton.icon(
                onPressed: _isLoading ? null : _save,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(actionIcon),
                label: Text(_isLoading ? 'Guardando...' : '$actionLabel (Enter)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
