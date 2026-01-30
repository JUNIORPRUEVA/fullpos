import 'package:flutter/material.dart';
import '../../../../core/theme/app_status_theme.dart';
import '../../../../core/theme/color_utils.dart';
import '../../../../core/ui/dialog_keyboard_shortcuts.dart';

class CashCloseDialog extends StatefulWidget {
  final double openingAmount;
  final double currentBalance;

  const CashCloseDialog({
    super.key,
    required this.openingAmount,
    required this.currentBalance,
  });

  @override
  State<CashCloseDialog> createState() => _CashCloseDialogState();
}

class _CashCloseDialogState extends State<CashCloseDialog> {
  late TextEditingController _closingAmountController;

  @override
  void initState() {
    super.initState();
    _closingAmountController = TextEditingController(
      text: widget.currentBalance.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _closingAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = theme.extension<AppStatusTheme>() ??
        AppStatusTheme(
          success: scheme.primary,
          warning: scheme.tertiary,
          error: scheme.error,
          info: scheme.secondary,
        );
    final closingAmount = double.tryParse(_closingAmountController.text) ?? 0;
    final difference = closingAmount - widget.currentBalance;
    final isDifferenceGood = difference.abs() < 0.01; // Tolerancia de 1 centavo
    final headerColor = status.error;
    final headerForeground = ColorUtils.readableTextColor(headerColor);
    final diffBackground = (isDifferenceGood ? status.success : status.warning)
        .withOpacity(0.12);
    final diffBorder =
        (isDifferenceGood ? status.success : status.warning).withOpacity(0.35);
    final diffValueColor = ColorUtils.ensureReadableColor(
      isDifferenceGood ? status.success : status.warning,
      diffBackground,
    );

    return DialogKeyboardShortcuts(
      onSubmit: _closeSession,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.close, color: headerForeground, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Cerrar Sesión de Caja',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: headerForeground,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: headerForeground),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Resumen
                    _buildSummaryCard(
                      'Monto de Apertura',
                      widget.openingAmount,
                      scheme.primary,
                    ),
                    const SizedBox(height: 12),
                    _buildSummaryCard(
                      'Balance Actual (Sistema)',
                      widget.currentBalance,
                      scheme.secondary,
                    ),
                    const SizedBox(height: 24),
                    // Input de cierre
                    const Text(
                      'Monto Contado en Caja:',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _closingAmountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixText: '\$',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: scheme.outline),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Diferencia
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: diffBackground,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: diffBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Diferencia:',
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${difference >= 0 ? '+' : ''}\$${difference.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: diffValueColor,
                            ),
                          ),
                          if (!isDifferenceGood) ...[
                            const SizedBox(height: 8),
                            Text(
                              difference > 0
                                  ? 'Hay más dinero de lo esperado'
                                  : 'Falta dinero en la caja',
                              style: TextStyle(
                                fontSize: 13,
                                color: diffValueColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _closeSession,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: status.error,
                      foregroundColor:
                          ColorUtils.readableTextColor(status.error),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Cerrar Sesión'),
                  ),
                ],
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _closeSession() {
    final closingAmount = double.tryParse(_closingAmountController.text);
    if (closingAmount == null || closingAmount < 0) {
      final scheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Ingresa un monto válido'),
          backgroundColor: scheme.error,
        ),
      );
      return;
    }
    Navigator.pop(context, {
      'closingAmount': closingAmount,
      'difference': closingAmount - widget.currentBalance,
    });
  }
}
