import 'package:flutter/material.dart';

import '../../../core/brand/fullpos_brand_theme.dart';
import '../../../core/constants/app_sizes.dart';

class CashboxOpenDialog extends StatefulWidget {
  final bool canOpen;
  final String title;
  final String subtitle;
  final String confirmLabel;
  final String deniedMessage;

  const CashboxOpenDialog({
    super.key,
    required this.canOpen,
    required this.title,
    required this.subtitle,
    this.confirmLabel = 'Abrir caja',
    this.deniedMessage = 'Requiere supervisor/admin.',
  });

  static Future<double?> show({
    required BuildContext context,
    required bool canOpen,
    required String title,
    required String subtitle,
    String confirmLabel = 'Abrir caja',
    String deniedMessage = 'Requiere supervisor/admin.',
  }) {
    return showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CashboxOpenDialog(
        canOpen: canOpen,
        title: title,
        subtitle: subtitle,
        confirmLabel: confirmLabel,
        deniedMessage: deniedMessage,
      ),
    );
  }

  @override
  State<CashboxOpenDialog> createState() => _CashboxOpenDialogState();
}

class _CashboxOpenDialogState extends State<CashboxOpenDialog> {
  final _amountController = TextEditingController(text: '0.00');
  bool _submitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradient = FullposBrandTheme.backgroundGradient;

    final onSurface = scheme.onSurface;
    final mutedText = onSurface.withOpacity(0.72);
    final cardBorder = scheme.primary.withOpacity(0.18);
    final dividerColor = scheme.onSurface.withOpacity(0.10);
    final inputFill = scheme.surfaceVariant.withOpacity(
      theme.brightness == Brightness.dark ? 0.35 : 0.60,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final maxHeight = constraints.maxHeight;

          return SizedBox(
            width: maxWidth,
            height: maxHeight,
            child: Container(
              decoration: BoxDecoration(gradient: gradient),
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSizes.paddingL),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Card(
                      color: scheme.surface,
                      elevation: 14,
                      shadowColor: Colors.black.withOpacity(0.24),
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                        side: BorderSide(color: cardBorder),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: cardBorder),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.asset(
                                    FullposBrandTheme.logoAsset,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        Center(
                                      child: Icon(
                                        Icons.storefront,
                                        size: 36,
                                        color: scheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        FullposBrandTheme.appName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleLarge?.copyWith(
                                          color: onSurface,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        widget.title,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: mutedText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.surfaceVariant.withOpacity(0.40),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: dividerColor),
                              ),
                              child: Text(
                                widget.subtitle,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: mutedText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _amountController,
                              enabled: !_submitting,
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Fondo inicial',
                                hintText: '0.00',
                                prefixText: 'RD\$ ',
                                prefixIcon: Icon(Icons.payments_outlined, color: scheme.primary),
                                filled: true,
                                fillColor: inputFill,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: cardBorder),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: cardBorder),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(color: scheme.primary, width: 2),
                                ),
                              ),
                            ),
                            if (!widget.canOpen) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: scheme.error.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: scheme.error.withOpacity(0.30),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline, color: scheme.error, size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        widget.deniedMessage,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: scheme.error,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _submitting
                                        ? null
                                        : () => Navigator.pop(context),
                                    icon: const Icon(Icons.close_rounded),
                                    label: const Text('Cancelar'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: FilledButton.icon(
                                    onPressed: (!widget.canOpen || _submitting)
                                        ? null
                                        : () {
                                            setState(() => _submitting = true);
                                            final amount =
                                                double.tryParse(_amountController.text.trim()) ??
                                                    0;
                                            Navigator.pop(context, amount);
                                          },
                                    icon: const Icon(Icons.lock_open_rounded),
                                    label: Text(widget.confirmLabel),
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
              ),
            ),
          );
        },
      ),
    );
  }
}
