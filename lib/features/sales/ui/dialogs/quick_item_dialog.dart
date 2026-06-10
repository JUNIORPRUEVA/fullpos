import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/ui/dialog_keyboard_shortcuts.dart';
import '../../data/sale_item_model.dart';

enum _QuickFieldTarget { qty, price, cost }

class QuickItemDialog extends StatefulWidget {
  const QuickItemDialog({super.key});

  @override
  State<QuickItemDialog> createState() => _QuickItemDialogState();
}

class _QuickItemDialogState extends State<QuickItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');
  final _costController = TextEditingController();
  final _descriptionFocusNode = FocusNode();
  final _qtyFocusNode = FocusNode();
  final _priceFocusNode = FocusNode();
  final _costFocusNode = FocusNode();

  final _currency = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RD\$',
    decimalDigits: 2,
  );

  _QuickFieldTarget _activeField = _QuickFieldTarget.price;
  bool _isSubmitting = false;
  bool _isHeaderHovered = false;

  @override
  void initState() {
    super.initState();

    _qtyController.addListener(_refresh);
    _priceController.addListener(_refresh);
    _costController.addListener(_refresh);

    _qtyFocusNode.addListener(() {
      if (_qtyFocusNode.hasFocus) _setActiveField(_QuickFieldTarget.qty);
    });
    _priceFocusNode.addListener(() {
      if (_priceFocusNode.hasFocus) _setActiveField(_QuickFieldTarget.price);
    });
    _costFocusNode.addListener(() {
      if (_costFocusNode.hasFocus) _setActiveField(_QuickFieldTarget.cost);
    });
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    _costController.dispose();
    _descriptionFocusNode.dispose();
    _qtyFocusNode.dispose();
    _priceFocusNode.dispose();
    _costFocusNode.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _setActiveField(_QuickFieldTarget field) {
    if (_activeField == field) return;
    setState(() => _activeField = field);
  }

  TextEditingController get _activeController {
    switch (_activeField) {
      case _QuickFieldTarget.qty:
        return _qtyController;
      case _QuickFieldTarget.price:
        return _priceController;
      case _QuickFieldTarget.cost:
        return _costController;
    }
  }

  FocusNode get _activeFocusNode {
    switch (_activeField) {
      case _QuickFieldTarget.qty:
        return _qtyFocusNode;
      case _QuickFieldTarget.price:
        return _priceFocusNode;
      case _QuickFieldTarget.cost:
        return _costFocusNode;
    }
  }

  double get _qtyValue => double.tryParse(_qtyController.text.trim()) ?? 0;
  double get _priceValue => double.tryParse(_priceController.text.trim()) ?? 0;
  double get _totalValue => _qtyValue * _priceValue;

  void _appendKey(String value) {
    final controller = _activeController;
    final current = controller.text;

    if (value == '.') {
      if (current.contains('.')) return;
      controller.text = current.isEmpty ? '0.' : '$current.';
    } else if (value == '00') {
      controller.text = current.isEmpty ? '0' : '$current$value';
    } else {
      controller.text = current == '0' ? value : '$current$value';
    }

    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    _activeFocusNode.requestFocus();
    _refresh();
  }

  void _backspace() {
    final controller = _activeController;
    final text = controller.text;
    if (text.isEmpty) return;

    controller.text = text.substring(0, text.length - 1);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    _activeFocusNode.requestFocus();
    _refresh();
  }

  void _clearActiveField() {
    final controller = _activeController;
    controller.clear();

    if (_activeField == _QuickFieldTarget.qty) {
      controller.text = '1';
    }

    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    _activeFocusNode.requestFocus();
    _refresh();
  }

  void _incrementActiveField() {
    final controller = _activeController;
    final current = double.tryParse(controller.text.trim()) ?? 0;
    final next = current + 1;

    controller.text = next % 1 == 0
        ? next.toStringAsFixed(0)
        : next.toStringAsFixed(2);

    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );
    _activeFocusNode.requestFocus();
    _refresh();
  }

  Future<void> _saveItem() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      final description = _descriptionController.text.trim();
      final price = _priceValue;
      final qty = _qtyValue;
      final cost = double.tryParse(_costController.text.trim()) ?? 0;

      final item = SaleItemModel(
        saleId: 0,
        productId: null,
        productCodeSnapshot: 'MANUAL',
        productNameSnapshot: description,
        unitPrice: price,
        purchasePriceSnapshot: cost,
        qty: qty,
        discountLine: 0,
        totalLine: qty * price,
        createdAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      if (mounted) Navigator.pop(context, item);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DialogKeyboardShortcuts(
      onSubmit: _saveItem,
      child: Material(
        color: Colors.transparent,
        child: AnimatedScale(
          scale: _isHeaderHovered ? 1.006 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: Container(
            width: 430,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _isHeaderHovered
                    ? const Color(0xFFBFD1F7)
                    : const Color(0xFFD8E1EC),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(_isHeaderHovered ? 0.16 : 0.12),
                  blurRadius: _isHeaderHovered ? 42 : 34,
                  spreadRadius: _isHeaderHovered ? -10 : 0,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(theme),
                  const SizedBox(height: 18),
                  _buildTotalDisplay(),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    focusNode: _descriptionFocusNode,
                    decoration: InputDecoration(
                      labelText: 'Descripción *',
                      hintText: 'Nombre del producto o servicio',
                      prefixIcon: const Icon(Icons.description_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    maxLines: 2,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'La descripción es requerida';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _buildNumberField(
                          controller: _qtyController,
                          focusNode: _qtyFocusNode,
                          label: 'Cantidad *',
                          icon: Icons.pin_outlined,
                          field: _QuickFieldTarget.qty,
                          validator: (value) {
                            final qty = double.tryParse((value ?? '').trim());
                            if (qty == null || qty <= 0) {
                              return 'Cantidad inválida';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildNumberField(
                          controller: _priceController,
                          focusNode: _priceFocusNode,
                          label: 'Precio *',
                          icon: Icons.attach_money_rounded,
                          field: _QuickFieldTarget.price,
                          validator: (value) {
                            final price = double.tryParse((value ?? '').trim());
                            if (price == null || price <= 0) {
                              return 'Precio inválido';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildNumberField(
                    controller: _costController,
                    focusNode: _costFocusNode,
                    label: 'Costo (opcional)',
                    icon: Icons.payments_outlined,
                    field: _QuickFieldTarget.cost,
                  ),
                  const SizedBox(height: 18),
                  _buildTargetSelector(),
                  const SizedBox(height: 14),
                  _buildCalculatorPad(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSubmitting
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: _isSubmitting ? null : _saveItem,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: const Text('Aplicar a la venta'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: const Color(0xFF1A56DB),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
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
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHeaderHovered = true),
      onExit: (_) => setState(() => _isHeaderHovered = false),
      child: Tooltip(
        message: 'Vende fuera de inventario',
        waitDuration: const Duration(milliseconds: 320),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: _isHeaderHovered
                ? const Color(0xFFF5F9FF)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _isHeaderHovered
                  ? const Color(0xFF1A56DB).withOpacity(0.12)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: _isHeaderHovered ? 48 : 44,
                height: _isHeaderHovered ? 48 : 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _isHeaderHovered
                        ? const [
                            Color(0xFFE0ECFF),
                            Color(0xFFF7FAFF),
                          ]
                        : const [
                            Color(0xFFE9F1FF),
                            Color(0xFFE9F1FF),
                          ],
                  ),
                  borderRadius: BorderRadius.circular(_isHeaderHovered ? 16 : 14),
                  border: Border.all(
                    color: _isHeaderHovered
                        ? const Color(0xFF2563EB).withOpacity(0.24)
                        : Colors.transparent,
                  ),
                  boxShadow: [
                    if (_isHeaderHovered)
                      BoxShadow(
                        color: const Color(0xFF2563EB).withOpacity(0.16),
                        blurRadius: 16,
                        spreadRadius: -8,
                        offset: const Offset(0, 8),
                      ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(
                      scale: animation,
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: Icon(
                    _isHeaderHovered
                        ? Icons.inventory_2_outlined
                        : Icons.calculate_rounded,
                    key: ValueKey<bool>(_isHeaderHovered),
                    color: _isHeaderHovered
                        ? const Color(0xFF2563EB)
                        : const Color(0xFF1A56DB),
                    size: _isHeaderHovered ? 25 : 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      style: (theme.textTheme.titleLarge ?? const TextStyle())
                          .copyWith(
                        fontWeight:
                            _isHeaderHovered ? FontWeight.w900 : FontWeight.w800,
                        color: _isHeaderHovered
                            ? const Color(0xFF1A56DB)
                            : const Color(0xFF17324D),
                        height: 1.08,
                        letterSpacing: _isHeaderHovered ? -0.1 : 0,
                      ),
                      child: const Text(
                        'Venta común',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        final slideAnimation = Tween<Offset>(
                          begin: const Offset(0, 0.18),
                          end: Offset.zero,
                        ).animate(animation);

                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: slideAnimation,
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        _isHeaderHovered
                            ? 'Vende fuera de inventario'
                            : 'Agrega una línea manual a la venta activa',
                        key: ValueKey<bool>(_isHeaderHovered),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _isHeaderHovered
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF6B7C8E),
                          fontSize: _isHeaderHovered ? 12.5 : 13,
                          fontWeight: _isHeaderHovered
                              ? FontWeight.w800
                              : FontWeight.w500,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: _isHeaderHovered
                      ? const Color(0xFFEAF2FF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Cerrar',
                  splashRadius: 20,
                  icon: Icon(
                    Icons.close_rounded,
                    color: _isHeaderHovered
                        ? const Color(0xFF1A56DB)
                        : const Color(0xFF5E7186),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTotalDisplay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17324D), Color(0xFF1A56DB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total calculado',
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _currency.format(_totalValue),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -0.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required IconData icon,
    required _QuickFieldTarget field,
    String? Function(String?)? validator,
  }) {
    final isActive = _activeField == field;

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      onTap: () => _setActiveField(field),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isActive ? const Color(0xFF1A56DB) : Colors.blueGrey,
            width: 1.8,
          ),
        ),
        filled: isActive,
        fillColor: isActive ? const Color(0xFFF5F9FF) : null,
      ),
      validator: validator,
    );
  }

  Widget _buildTargetSelector() {
    Widget chip(String label, _QuickFieldTarget field) {
      final isSelected = _activeField == field;

      return Expanded(
        child: InkWell(
          onTap: () {
            _setActiveField(field);
            _activeFocusNode.requestFocus();
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFEAF2FF)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF1A56DB)
                    : const Color(0xFFD7E0EA),
              ),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected
                    ? const Color(0xFF1A56DB)
                    : const Color(0xFF5E7186),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('Editar cantidad', _QuickFieldTarget.qty),
        const SizedBox(width: 8),
        chip('Editar precio', _QuickFieldTarget.price),
        const SizedBox(width: 8),
        chip('Editar costo', _QuickFieldTarget.cost),
      ],
    );
  }

  Widget _buildCalculatorPad() {
    final keys = <String>[
      '7',
      '8',
      '9',
      'C',
      '4',
      '5',
      '6',
      'DEL',
      '1',
      '2',
      '3',
      '.',
      '0',
      '00',
      '+1',
      '=',
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: keys.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.4,
      ),
      itemBuilder: (context, index) {
        final key = keys[index];
        final isPrimary = key == '=' || key == 'C' || key == '+1';
        final isAccent = key == 'DEL';

        return InkWell(
          onTap: () {
            switch (key) {
              case 'C':
                _clearActiveField();
                break;
              case 'DEL':
                _backspace();
                break;
              case '+1':
                _incrementActiveField();
                break;
              case '=':
                _activeFocusNode.requestFocus();
                _refresh();
                break;
              default:
                _appendKey(key);
                break;
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: isPrimary
                  ? const Color(0xFFEAF2FF)
                  : isAccent
                      ? const Color(0xFFF8F1F1)
                      : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isPrimary
                    ? const Color(0xFFBFD1F7)
                    : const Color(0xFFD7E0EA),
              ),
            ),
            child: Center(
              child: Text(
                key,
                style: TextStyle(
                  fontSize: key == 'DEL' ? 15 : 18,
                  fontWeight: FontWeight.w700,
                  color: isPrimary
                      ? const Color(0xFF1A56DB)
                      : isAccent
                          ? const Color(0xFFB45353)
                          : const Color(0xFF23384F),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
