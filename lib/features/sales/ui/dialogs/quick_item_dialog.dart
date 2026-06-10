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
  static const Color _brandBlue = Color(0xFF1A56DB);
  static const Color _brandBlueDark = Color(0xFF17324D);
  static const Color _textPrimary = Color(0xFF0F172A);
  static const Color _textMuted = Color(0xFF64748B);
  static const Color _borderColor = Color(0xFFD8E1EC);
  static const Color _softBg = Color(0xFFF8FAFC);
  static const Color _softBlueBg = Color(0xFFEAF2FF);
  static const Color _danger = Color(0xFFDC2626);

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
  bool _showMoreData = false;
  bool _calculatorOnly = false;

  String _calcExpression = '';
  String _calcResultText = '';

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

  String get _activeFieldLabel {
    switch (_activeField) {
      case _QuickFieldTarget.qty:
        return 'cantidad';
      case _QuickFieldTarget.price:
        return 'precio';
      case _QuickFieldTarget.cost:
        return 'costo';
    }
  }

  double get _qtyValue => double.tryParse(_qtyController.text.trim()) ?? 0;
  double get _priceValue => double.tryParse(_priceController.text.trim()) ?? 0;
  double get _totalValue => _qtyValue * _priceValue;

  bool _isOperator(String value) {
    return value == '+' || value == '-' || value == '*' || value == '/';
  }

  String _formatNumberForInput(double value) {
    if (value.isNaN || value.isInfinite) return '';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _formatCalcNumber(double value) {
    final clean = _formatNumberForInput(value);
    return clean.isEmpty ? '0' : clean;
  }

  void _clearCalculator({bool keepField = true}) {
    _calcExpression = '';
    _calcResultText = '';
    if (!keepField) {
      final controller = _activeController;
      controller.clear();
      if (_activeField == _QuickFieldTarget.qty) {
        controller.text = '1';
      }
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    }
    _refresh();
  }

  void _appendKey(String value) {
    if (_isOperator(value)) {
      _appendOperator(value);
      return;
    }

    if (value == '.') {
      final lastNumber = _calcExpression.split(RegExp(r'[+\-*/]')).last;
      if (lastNumber.contains('.')) return;
      _calcExpression = _calcExpression.isEmpty ? '0.' : '$_calcExpression.';
    } else {
      if (_calcExpression == '0') {
        _calcExpression = value;
      } else {
        _calcExpression = '$_calcExpression$value';
      }
    }

    _calcResultText = '';
    _syncExpressionToActiveFieldIfSimple();
    _activeFocusNode.requestFocus();
    _refresh();
  }

  void _appendOperator(String operator) {
    if (_calcExpression.trim().isEmpty) {
      final activeText = _activeController.text.trim();
      _calcExpression = activeText.isEmpty ? '0' : activeText;
    }

    if (_calcExpression.isEmpty) return;

    final lastChar = _calcExpression.characters.last;
    if (_isOperator(lastChar)) {
      _calcExpression =
          '${_calcExpression.substring(0, _calcExpression.length - 1)}$operator';
    } else {
      _calcExpression = '$_calcExpression$operator';
    }

    _calcResultText = '';
    _activeFocusNode.requestFocus();
    _refresh();
  }

  void _syncExpressionToActiveFieldIfSimple() {
    if (_calculatorOnly) return;
    if (_calcExpression.contains(RegExp(r'[+\-*/]'))) return;

    final controller = _activeController;
    controller.text = _calcExpression;
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
  }

  void _backspace() {
    if (_calcExpression.isNotEmpty) {
      _calcExpression = _calcExpression.substring(0, _calcExpression.length - 1);
    }

    if (!_calculatorOnly && !_calcExpression.contains(RegExp(r'[+\-*/]'))) {
      final controller = _activeController;
      controller.text = _calcExpression;
      if (_activeField == _QuickFieldTarget.qty && controller.text.isEmpty) {
        controller.text = '1';
      }
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
    }

    _calcResultText = '';
    _activeFocusNode.requestFocus();
    _refresh();
  }

  void _evaluateCalculator() {
    final expression = _calcExpression.trim();
    if (expression.isEmpty) return;

    final result = _calculateExpression(expression);
    if (result == null) {
      _calcResultText = 'Operación inválida';
      _refresh();
      return;
    }

    final text = _formatNumberForInput(result);
    if (text.isEmpty) return;

    _calcExpression = text;
    _calcResultText = '= ${_currency.format(result)}';

    if (!_calculatorOnly) {
      final controller = _activeController;
      controller.text = text;
      controller.selection = TextSelection.collapsed(offset: text.length);
      _activeFocusNode.requestFocus();
    }

    _refresh();
  }

  double? _calculateExpression(String expression) {
    final cleaned = expression
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll(' ', '');

    final tokens = RegExp(r'(\d+(?:\.\d+)?|[+\-*/])')
        .allMatches(cleaned)
        .map((match) => match.group(0)!)
        .toList();

    if (tokens.isEmpty) return null;

    final rebuilt = tokens.join();
    if (rebuilt != cleaned) return null;
    if (_isOperator(tokens.first) || _isOperator(tokens.last)) return null;

    final values = <double>[];
    final operators = <String>[];

    int precedence(String op) => (op == '*' || op == '/') ? 2 : 1;

    bool applyTopOperator() {
      if (values.length < 2 || operators.isEmpty) return false;
      final b = values.removeLast();
      final a = values.removeLast();
      final op = operators.removeLast();

      switch (op) {
        case '+':
          values.add(a + b);
          return true;
        case '-':
          values.add(a - b);
          return true;
        case '*':
          values.add(a * b);
          return true;
        case '/':
          if (b == 0) return false;
          values.add(a / b);
          return true;
      }
      return false;
    }

    for (final token in tokens) {
      final number = double.tryParse(token);
      if (number != null) {
        values.add(number);
        continue;
      }

      if (!_isOperator(token)) return null;

      while (operators.isNotEmpty && precedence(operators.last) >= precedence(token)) {
        if (!applyTopOperator()) return null;
      }
      operators.add(token);
    }

    while (operators.isNotEmpty) {
      if (!applyTopOperator()) return null;
    }

    return values.length == 1 ? values.single : null;
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
    final screen = MediaQuery.sizeOf(context);
    final width = screen.width.clamp(360.0, 520.0);
    final maxHeight = (screen.height - 70).clamp(520.0, 760.0);

    return DialogKeyboardShortcuts(
      onSubmit: _saveItem,
      child: Material(
        color: Colors.transparent,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: width,
            maxHeight: maxHeight,
          ),
          child: Container(
            width: width,
            padding: EdgeInsets.all(screen.width < 430 ? 16 : 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 34,
                  spreadRadius: -12,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 16),
                    _buildTotalDisplay(compact: screen.width < 430),
                    const SizedBox(height: 14),
                    _buildDescriptionField(),
                    const SizedBox(height: 12),
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
                              if (qty == null || qty <= 0) return 'Cantidad inválida';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: _buildNumberField(
                            controller: _priceController,
                            focusNode: _priceFocusNode,
                            label: 'Precio *',
                            icon: Icons.attach_money_rounded,
                            field: _QuickFieldTarget.price,
                            validator: (value) {
                              final price = double.tryParse((value ?? '').trim());
                              if (price == null || price <= 0) return 'Precio inválido';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildMoreDataSection(),
                    const SizedBox(height: 12),
                    _buildCalculatorHeader(),
                    const SizedBox(height: 8),
                    _buildCalculatorPad(),
                    const SizedBox(height: 14),
                    _buildFooterActions(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _softBlueBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBFD1F7)),
          ),
          child: const Icon(Icons.calculate_rounded, color: _brandBlue, size: 22),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Venta común',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _brandBlueDark,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Agrega producto o servicio fuera del inventario',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _textMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.18,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(10),
            child: const SizedBox(
              width: 36,
              height: 36,
              child: Icon(Icons.close_rounded, color: Color(0xFF475569), size: 22),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalDisplay({required bool compact}) {
    final expressionText = '${_formatCalcNumber(_qtyValue)} × ${_currency.format(_priceValue)}';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 18,
        vertical: compact ? 14 : 16,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF17324D), Color(0xFF1A56DB)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(11),
        boxShadow: [
          BoxShadow(
            color: _brandBlue.withOpacity(0.18),
            blurRadius: 16,
            spreadRadius: -8,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTotalLabel(),
                const SizedBox(height: 8),
                _buildTotalAmount(compact: true),
                const SizedBox(height: 10),
                _buildTotalExpression(expressionText),
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTotalLabel(),
                      const SizedBox(height: 8),
                      _buildTotalAmount(compact: false),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(child: _buildTotalExpression(expressionText)),
              ],
            ),
    );
  }

  Widget _buildTotalLabel() {
    return Text(
      'Total calculado',
      style: TextStyle(
        color: Colors.white.withOpacity(0.72),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1,
      ),
    );
  }

  Widget _buildTotalAmount({required bool compact}) {
    return Text(
      _currency.format(_totalValue),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.white,
        fontSize: compact ? 27 : 30,
        fontWeight: FontWeight.w900,
        height: 1,
        letterSpacing: -0.8,
      ),
    );
  }

  Widget _buildTotalExpression(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withOpacity(0.86),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }

  Widget _buildDescriptionField() {
    return TextFormField(
      controller: _descriptionController,
      focusNode: _descriptionFocusNode,
      decoration: InputDecoration(
        labelText: 'Descripción *',
        hintText: 'Nombre del producto o servicio',
        prefixIcon: const Icon(Icons.description_outlined),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _brandBlue, width: 1.7),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      maxLines: 2,
      validator: (value) {
        if (value == null || value.trim().isEmpty) return 'La descripción es requerida';
        return null;
      },
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
      onTap: () {
        _setActiveField(field);
        _calcExpression = '';
        _calcResultText = '';
      },
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 21),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: isActive ? _brandBlue : Colors.blueGrey, width: 1.7),
        ),
        filled: true,
        fillColor: isActive ? const Color(0xFFF5F9FF) : Colors.white,
      ),
      validator: validator,
    );
  }

  Widget _buildMoreDataSection() {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              setState(() => _showMoreData = !_showMoreData);
              if (!_showMoreData && _activeField == _QuickFieldTarget.cost) {
                _setActiveField(_QuickFieldTarget.price);
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _softBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _borderColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded, color: _textMuted, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Más datos',
                      style: TextStyle(
                        color: _textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _showMoreData ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _textMuted,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          firstCurve: Curves.easeOut,
          secondCurve: Curves.easeOut,
          crossFadeState:
              _showMoreData ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _buildNumberField(
              controller: _costController,
              focusNode: _costFocusNode,
              label: 'Costo (opcional)',
              icon: Icons.payments_outlined,
              field: _QuickFieldTarget.cost,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCalculatorHeader() {
    final expression = _calcExpression.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _softBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.calculate_outlined, color: _textMuted, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              expression.isEmpty
                  ? (_calculatorOnly
                      ? 'Calculadora libre'
                      : 'Calculadora para $_activeFieldLabel')
                  : expression.replaceAll('*', '×').replaceAll('/', '÷'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: expression.isEmpty ? _textMuted : _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          if (_calcResultText.isNotEmpty) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _calcResultText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _calcResultText.contains('inválida') ? _danger : _brandBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          _buildCalculatorOnlySwitch(),
        ],
      ),
    );
  }

  Widget _buildCalculatorOnlySwitch() {
    return Tooltip(
      message: _calculatorOnly
          ? 'Solo calcular, no escribir en campos'
          : 'Escribir resultado en el campo activo',
      child: InkWell(
        onTap: () {
          setState(() {
            _calculatorOnly = !_calculatorOnly;
            _calcExpression = '';
            _calcResultText = '';
          });
        },
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 26,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _calculatorOnly ? _brandBlue : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _calculatorOnly ? _brandBlue : _borderColor,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _calculatorOnly ? Icons.lock_outline_rounded : Icons.edit_rounded,
                size: 13,
                color: _calculatorOnly ? Colors.white : _textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                _calculatorOnly ? 'Solo calc.' : 'Aplicar',
                style: TextStyle(
                  color: _calculatorOnly ? Colors.white : _textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalculatorPad() {
    final keys = <String>[
      '7',
      '8',
      '9',
      'DEL',
      '4',
      '5',
      '6',
      '+',
      '1',
      '2',
      '3',
      '-',
      '0',
      '00',
      '.',
      '*',
      'C',
      '/',
      '=',
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: keys.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.85,
      ),
      itemBuilder: (context, index) {
        final key = keys[index];
        final isEqual = key == '=';
        final isClear = key == 'C';
        final isDelete = key == 'DEL';
        final isOperator = _isOperator(key);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              switch (key) {
                case 'C':
                  _clearCalculator(keepField: true);
                  break;
                case 'DEL':
                  _backspace();
                  break;
                case '=':
                  _evaluateCalculator();
                  break;
                default:
                  _appendKey(key);
                  break;
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              decoration: BoxDecoration(
                color: isEqual
                    ? _brandBlue
                    : isClear || isDelete
                        ? const Color(0xFFFFF7ED)
                        : isOperator
                            ? _softBlueBg
                            : _softBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isEqual
                      ? _brandBlue
                      : isClear || isDelete
                          ? const Color(0xFFFED7AA)
                          : isOperator
                              ? const Color(0xFFBFD1F7)
                              : _borderColor,
                ),
              ),
              child: Center(
                child: Text(
                  key == '*' ? '×' : key == '/' ? '÷' : key,
                  style: TextStyle(
                    fontSize: key == 'DEL' ? 14 : 17,
                    fontWeight: FontWeight.w900,
                    color: isEqual
                        ? Colors.white
                        : isClear || isDelete
                            ? const Color(0xFFC2410C)
                            : isOperator
                                ? _brandBlue
                                : _textPrimary,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooterActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              foregroundColor: _textPrimary,
              side: const BorderSide(color: _borderColor),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
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
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_outline, size: 19),
            label: const Text('Aplicar a la venta'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: _brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}
