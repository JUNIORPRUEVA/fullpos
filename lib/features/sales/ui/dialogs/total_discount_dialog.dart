import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/ui/dialog_keyboard_shortcuts.dart';

/// Tipo de descuento: por porcentaje o monto fijo
enum DiscountType {
  percent, // Porcentaje (%)
  amount, // Monto fijo (RD$)
}

/// Resultado del diálogo de descuento
class DiscountResult {
  final DiscountType type;
  final double value;

  DiscountResult({
    required this.type,
    required this.value,
  });
}

/// Diálogo para aplicar descuento total a la venta
class TotalDiscountDialog extends StatefulWidget {
  final double subtotal;
  final double itbisRate;
  final DiscountResult? currentDiscount;

  const TotalDiscountDialog({
    super.key,
    required this.subtotal,
    required this.itbisRate,
    this.currentDiscount,
  });

  @override
  State<TotalDiscountDialog> createState() => _TotalDiscountDialogState();
}

class _TotalDiscountDialogState extends State<TotalDiscountDialog> {
  late DiscountType _selectedType;
  late TextEditingController _valueController;
  double _discountValue = 0.0;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.currentDiscount?.type ?? DiscountType.percent;
    _discountValue = widget.currentDiscount?.value ?? 0.0;
    _valueController = TextEditingController(
      text: _discountValue > 0 ? _discountValue.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  void _updateValue(String text) {
    setState(() {
      _discountValue = double.tryParse(text) ?? 0.0;
    });
  }

  double _calculateDiscountAmount() {
    if (_selectedType == DiscountType.percent) {
      return widget.subtotal * (_discountValue / 100);
    }
    return _discountValue;
  }

  double _calculateSubtotalAfterDiscount() {
    final discountAmount = _calculateDiscountAmount();
    return (widget.subtotal - discountAmount).clamp(0.0, double.infinity);
  }

  double _calculateItbis() {
    return _calculateSubtotalAfterDiscount() * widget.itbisRate;
  }

  double _calculateTotal() {
    return _calculateSubtotalAfterDiscount() + _calculateItbis();
  }

  bool _isValidDiscount() {
    if (_discountValue <= 0) return false;

    if (_selectedType == DiscountType.percent) {
      return _discountValue > 0 && _discountValue <= 100;
    } else {
      return _discountValue > 0 && _discountValue < widget.subtotal;
    }
  }

  void _applyDiscount() {
    if (!_isValidDiscount()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedType == DiscountType.percent
                ? 'El porcentaje debe ser entre 0% y 100%'
                : 'El monto debe ser menor al subtotal',
          ),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    Navigator.of(context).pop(
      DiscountResult(
        type: _selectedType,
        value: _discountValue,
      ),
    );
  }

  void _removeDiscount() {
    Navigator.of(context).pop('remove');
  }

  @override
  Widget build(BuildContext context) {
    final hasCurrentDiscount = widget.currentDiscount != null;

    return DialogKeyboardShortcuts(
      onSubmit: _isValidDiscount() ? _applyDiscount : null,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            const Icon(Icons.discount, color: AppColors.gold),
            const SizedBox(width: 8),
            const Text('Descuento total'),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
              color: AppColors.textDarkMuted,
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<DiscountType>(
                segments: const [
                  ButtonSegment(
                    value: DiscountType.percent,
                    label: Text('Porcentaje (%)'),
                    icon: Icon(Icons.percent),
                  ),
                  ButtonSegment(
                    value: DiscountType.amount,
                    label: Text('Monto (RD\$)'),
                    icon: Icon(Icons.attach_money),
                  ),
                ],
                selected: {_selectedType},
                onSelectionChanged: (Set<DiscountType> selected) {
                  setState(() {
                    _selectedType = selected.first;
                    _valueController.clear();
                    _discountValue = 0.0;
                  });
                },
                style: ButtonStyle(
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppColors.gold;
                    }
                    return AppColors.surfaceLight;
                  }),
                  foregroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppColors.textDark;
                    }
                    return AppColors.textDarkSecondary;
                  }),
                ),
              ),
              const SizedBox(height: AppSizes.paddingL),
              TextField(
                controller: _valueController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: _selectedType == DiscountType.percent
                      ? 'Porcentaje de descuento'
                      : 'Monto de descuento',
                  hintText: _selectedType == DiscountType.percent
                      ? 'Ej: 10'
                      : 'Ej: 150.00',
                  prefixIcon: Icon(
                    _selectedType == DiscountType.percent
                        ? Icons.percent
                        : Icons.attach_money,
                    color: AppColors.teal700,
                  ),
                  suffixText:
                      _selectedType == DiscountType.percent ? '%' : 'RD\$',
                ),
                onChanged: _updateValue,
                autofocus: true,
              ),
              const SizedBox(height: AppSizes.paddingL),
              Container(
                padding: const EdgeInsets.all(AppSizes.paddingM),
                decoration: BoxDecoration(
                  color: AppColors.bgLightAlt,
                  borderRadius: BorderRadius.circular(AppSizes.radiusM),
                  border: Border.all(
                    color: AppColors.surfaceLightBorder,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    _buildTotalRow(
                      'Subtotal:',
                      widget.subtotal,
                      color: AppColors.textDark,
                    ),
                    const SizedBox(height: 8),
                    _buildTotalRow(
                      'Descuento:',
                      -_calculateDiscountAmount(),
                      color: AppColors.error,
                      bold: true,
                    ),
                    const Divider(height: 16),
                    _buildTotalRow(
                      'Subtotal c/descuento:',
                      _calculateSubtotalAfterDiscount(),
                      color: AppColors.textDarkSecondary,
                    ),
                    const SizedBox(height: 8),
                    _buildTotalRow(
                      'ITBIS (${(widget.itbisRate * 100).toStringAsFixed(0)}%):',
                      _calculateItbis(),
                      color: AppColors.textDarkSecondary,
                    ),
                    const Divider(height: 16),
                    _buildTotalRow(
                      'TOTAL FINAL:',
                      _calculateTotal(),
                      color: AppColors.teal700,
                      bold: true,
                      large: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.paddingL),
              Row(
                children: [
                  if (hasCurrentDiscount) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _removeDiscount,
                        icon: const Icon(Icons.clear),
                        label: const Text('Quitar Descuento'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSizes.spaceM),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: AppSizes.spaceM),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isValidDiscount() ? _applyDiscount : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Aplicar Descuento'),
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

  Widget _buildTotalRow(
    String label,
    double amount, {
    Color? color,
    bool bold = false,
    bool large = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: large ? 16 : 14,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color ?? AppColors.textDark,
          ),
        ),
        Text(
          'RD\$ ${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: large ? 18 : 14,
            fontWeight: bold ? FontWeight.bold : FontWeight.w600,
            color: color ?? AppColors.textDark,
          ),
        ),
      ],
    );
  }
}
