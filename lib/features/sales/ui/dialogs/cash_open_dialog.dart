import 'package:flutter/material.dart';
import '../../../../core/theme/app_status_theme.dart';
import '../../../../core/theme/color_utils.dart';
import '../../../../core/ui/dialog_keyboard_shortcuts.dart';

class CashOpenDialog extends StatefulWidget {
  final double? suggestedAmount;

  const CashOpenDialog({super.key, this.suggestedAmount = 0.0});

  @override
  State<CashOpenDialog> createState() => _CashOpenDialogState();
}

class _CashOpenDialogState extends State<CashOpenDialog> {
  late TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: (widget.suggestedAmount ?? 0.0).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status =
        Theme.of(context).extension<AppStatusTheme>() ??
        AppStatusTheme(
          success: scheme.tertiary,
          warning: scheme.tertiary,
          error: scheme.error,
          info: scheme.primary,
        );
    final headerBg = status.success;
    final headerFg = ColorUtils.readableTextColor(headerBg);
    return DialogKeyboardShortcuts(
      onSubmit: _openSession,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 450, maxHeight: 350),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: headerBg,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, color: headerFg, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Abrir Sesión de Caja',
                        style: TextStyle(
                          color: headerFg,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: headerFg),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Body
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Ingresa el monto inicial de la caja:',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixText: '\$',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withAlpha(102),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: scheme.primary.withAlpha(102),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: scheme.primary, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'La sesión se abrirá con el monto especificado',
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                      onPressed: _openSession,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: status.success,
                        foregroundColor: ColorUtils.readableTextColor(
                          status.success,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: Text('Abrir Sesión'),
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

  void _openSession() {
    final raw = _amountController.text.trim();
    final amount = raw.isEmpty ? 0.0 : double.tryParse(raw);
    if (amount == null || amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ingresa un monto válido'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    Navigator.pop(context, {'openingAmount': amount});
  }
}
