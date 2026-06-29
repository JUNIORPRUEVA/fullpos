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
  final _keyboardFocusNode = FocusNode();

  final _currency = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'RD\$',
    decimalDigits: 2,
  );

  _QuickFieldTarget _activeField = _QuickFieldTarget.price;

  bool _isSubmitting = false;
  bool _showMoreData = false;
  bool _calculatorOnly = false;
  bool _syncingCalculatorField = false;

  String _calcExpression = '';
  String _calcResultText = '';

  @override
  void initState() {
    super.initState();

    _qtyController.addListener(
      () => _handleNumberControllerChanged(_QuickFieldTarget.qty),
    );
    _priceController.addListener(
      () => _handleNumberControllerChanged(_QuickFieldTarget.price),
    );
    _costController.addListener(
      () => _handleNumberControllerChanged(_QuickFieldTarget.cost),
    );

    _qtyFocusNode.addListener(() {
      if (_qtyFocusNode.hasFocus) _setActiveField(_QuickFieldTarget.qty);
    });

    _priceFocusNode.addListener(() {
      if (_priceFocusNode.hasFocus) _setActiveField(_QuickFieldTarget.price);
    });

    _costFocusNode.addListener(() {
      if (_costFocusNode.hasFocus) _setActiveField(_QuickFieldTarget.cost);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keyboardFocusNode.requestFocus();
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
    _keyboardFocusNode.dispose();

    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _handleNumberControllerChanged(_QuickFieldTarget field) {
    if (_syncingCalculatorField) return;

    if (!_calculatorOnly && _activeField == field) {
      _calcExpression = _controllerForField(field).text.trim();
      _calcResultText = '';
    }

    _refresh();
  }

  void _setActiveField(_QuickFieldTarget field) {
    if (_activeField == field) return;
    setState(() => _activeField = field);
  }

  TextEditingController get _activeController {
    return _controllerForField(_activeField);
  }

  TextEditingController _controllerForField(_QuickFieldTarget field) {
    switch (field) {
      case _QuickFieldTarget.qty:
        return _qtyController;
      case _QuickFieldTarget.price:
        return _priceController;
      case _QuickFieldTarget.cost:
        return _costController;
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

  void _focusKeyboard() {
    if (!mounted) return;
    _keyboardFocusNode.requestFocus();
  }

  void _writeActiveFieldText(String text) {
    final controller = _activeController;

    _syncingCalculatorField = true;
    try {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    } finally {
      _syncingCalculatorField = false;
    }
  }

  void _toggleCalculatorOnly(bool value) {
    if (_calculatorOnly == value) return;

    setState(() {
      _calculatorOnly = value;
      _calcExpression = '';
      _calcResultText = '';

      if (_calculatorOnly) {
        _showMoreData = false;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_calculatorOnly) {
        FocusScope.of(context).unfocus();
        _focusKeyboard();
      } else {
        _priceFocusNode.requestFocus();
      }
    });
  }

  void _clearCalculator({bool keepField = true}) {
    setState(() {
      _calcExpression = '';
      _calcResultText = '';

      if (!keepField && !_calculatorOnly) {
        _writeActiveFieldText('');

        if (_activeField == _QuickFieldTarget.qty) {
          _writeActiveFieldText('1');
        }
      }
    });

    _focusKeyboard();
  }

  void _appendKey(String value) {
    if (_isOperator(value)) {
      _appendOperator(value);
      return;
    }

    setState(() {
      if (!_calculatorOnly && _calcExpression.trim().isEmpty) {
        _calcExpression = _activeController.text.trim();
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
    });

    _focusKeyboard();
  }

  void _appendOperator(String operator) {
    setState(() {
      if (_calcExpression.trim().isEmpty) {
        if (_calculatorOnly) {
          _calcExpression = '0';
        } else {
          final activeText = _activeController.text.trim();
          _calcExpression = activeText.isEmpty ? '0' : activeText;
        }
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
    });

    _focusKeyboard();
  }

  void _syncExpressionToActiveFieldIfSimple() {
    if (_calculatorOnly) return;
    if (_calcExpression.contains(RegExp(r'[+\-*/]'))) return;

    _writeActiveFieldText(_calcExpression);
  }

  bool _deleteSelectedActiveFieldText() {
    if (_calculatorOnly) return false;
    if (_calcExpression.contains(RegExp(r'[+\-*/]'))) return false;

    final controller = _activeController;
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return false;

    final text = controller.text;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final nextText = text.replaceRange(start, end, '');

    setState(() {
      _calcExpression = nextText;
      _calcResultText = '';
      _syncingCalculatorField = true;
      try {
        controller.value = TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: start),
        );
      } finally {
        _syncingCalculatorField = false;
      }
    });

    _focusKeyboard();
    return true;
  }

  void _backspace() {
    if (_deleteSelectedActiveFieldText()) return;

    setState(() {
      if (_calcExpression.isNotEmpty) {
        _calcExpression = _calcExpression.substring(
          0,
          _calcExpression.length - 1,
        );
      }

      if (!_calculatorOnly && !_calcExpression.contains(RegExp(r'[+\-*/]'))) {
        var text = _calcExpression;

        if (_activeField == _QuickFieldTarget.qty && text.isEmpty) {
          text = '1';
          _calcExpression = text;
        }

        _writeActiveFieldText(text);
      }

      _calcResultText = '';
    });

    _focusKeyboard();
  }

  void _evaluateCalculator() {
    final expression = _calcExpression.trim();
    if (expression.isEmpty) return;

    final result = _calculateExpression(expression);

    setState(() {
      if (result == null) {
        _calcResultText = 'Operación inválida';
        return;
      }

      final text = _formatNumberForInput(result);
      if (text.isEmpty) return;

      _calcExpression = text;
      _calcResultText = _calculatorOnly ? _currency.format(result) : '= $text';

      if (!_calculatorOnly) {
        _writeActiveFieldText(text);
      }
    });

    _focusKeyboard();
  }

  void _deleteForward() {
    if (_deleteSelectedActiveFieldText()) return;

    if (!_calculatorOnly && !_calcExpression.contains(RegExp(r'[+\-*/]'))) {
      final controller = _activeController;
      final selection = controller.selection;
      final text = controller.text;

      if (selection.isValid &&
          selection.isCollapsed &&
          selection.start >= 0 &&
          selection.start < text.length) {
        final offset = selection.start;
        final nextText = text.replaceRange(offset, offset + 1, '');

        setState(() {
          _calcExpression = nextText;
          _calcResultText = '';
          _syncingCalculatorField = true;
          try {
            controller.value = TextEditingValue(
              text: nextText,
              selection: TextSelection.collapsed(offset: offset),
            );
          } finally {
            _syncingCalculatorField = false;
          }
        });

        _focusKeyboard();
        return;
      }
    }

    _clearCalculator(keepField: true);
  }

  double? _calculateExpression(String expression) {
    final cleaned = expression
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll(',', '.')
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

      while (operators.isNotEmpty &&
          precedence(operators.last) >= precedence(token)) {
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
    if (_calculatorOnly) {
      _evaluateCalculator();
      return;
    }

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

  /// Verifica si el foco actual está dentro de un campo de texto editable.
  /// Si es así, los atajos de la calculadora no deben interceptar las teclas.
  bool _isTextInputFocused() {
    final focus = FocusManager.instance.primaryFocus;
    final context = focus?.context;
    if (context == null) return false;

    // Buscar si el widget enfocado es o está dentro de un EditableText
    final editable = context.findAncestorWidgetOfExactType<EditableText>();
    if (editable != null) return true;

    final widget = context.widget;
    return widget is EditableText;
  }

  KeyEventResult _handleCalculatorKeyboard(KeyEvent event) {
    // Si un campo de texto está enfocado, no interceptar las teclas
    if (_isTextInputFocused()) {
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final character = event.character;


    String? digit;

    if (key == LogicalKeyboardKey.digit0 || key == LogicalKeyboardKey.numpad0) {
      digit = '0';
    } else if (key == LogicalKeyboardKey.digit1 ||
        key == LogicalKeyboardKey.numpad1) {
      digit = '1';
    } else if (key == LogicalKeyboardKey.digit2 ||
        key == LogicalKeyboardKey.numpad2) {
      digit = '2';
    } else if (key == LogicalKeyboardKey.digit3 ||
        key == LogicalKeyboardKey.numpad3) {
      digit = '3';
    } else if (key == LogicalKeyboardKey.digit4 ||
        key == LogicalKeyboardKey.numpad4) {
      digit = '4';
    } else if (key == LogicalKeyboardKey.digit5 ||
        key == LogicalKeyboardKey.numpad5) {
      digit = '5';
    } else if (key == LogicalKeyboardKey.digit6 ||
        key == LogicalKeyboardKey.numpad6) {
      digit = '6';
    } else if (key == LogicalKeyboardKey.digit7 ||
        key == LogicalKeyboardKey.numpad7) {
      digit = '7';
    } else if (key == LogicalKeyboardKey.digit8 ||
        key == LogicalKeyboardKey.numpad8) {
      digit = '8';
    } else if (key == LogicalKeyboardKey.digit9 ||
        key == LogicalKeyboardKey.numpad9) {
      digit = '9';
    }

    if (digit != null) {
      _appendKey(digit);
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.period ||
        key == LogicalKeyboardKey.comma ||
        key == LogicalKeyboardKey.numpadDecimal) {
      _appendKey('.');
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd ||
        character == '+') {
      _appendKey('+');
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract ||
        character == '-') {
      _appendKey('-');
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.asterisk ||
        key == LogicalKeyboardKey.numpadMultiply ||
        character == '*') {
      _appendKey('*');
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.slash ||
        key == LogicalKeyboardKey.numpadDivide ||
        character == '/') {
      _appendKey('/');
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadEqual ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _evaluateCalculator();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.delete) {
      _deleteForward();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);

    final isTightDesktop = screen.width <= 1280 || screen.height <= 768;
    final isCompactDesktop = screen.width <= 1366 || screen.height <= 820;

    final dialogWidth = isTightDesktop
        ? (screen.width - 24).clamp(356.0, 366.0).toDouble()
        : isCompactDesktop
            ? (screen.width - 24).clamp(374.0, 386.0).toDouble()
            : (screen.width < 430 ? screen.width - 24 : 400.0)
                .clamp(380.0, 420.0)
                .toDouble();

    // Altura suficiente para mostrar todo el contenido sin scroll interno.
    // En tight (1280x1024): ~984px disponibles - 40 topbar - 45 footer = ~899px
    // Usamos clamp generoso para que quepa todo.
    final availableHeight = screen.height - 40.0 - 45.0 - 32.0;
    final dialogMaxHeight = isTightDesktop
        ? availableHeight.clamp(680.0, 820.0).toDouble()
        : isCompactDesktop
            ? availableHeight.clamp(720.0, 860.0).toDouble()
            : availableHeight.clamp(760.0, 900.0).toDouble();

    final compact = isTightDesktop || isCompactDesktop || screen.width < 430;

    // En tight desktop, reducimos espaciados internos para que quepa sin scroll
    final tight = isTightDesktop;

    return DialogKeyboardShortcuts(
      onSubmit: _saveItem,
      enableSubmitShortcuts: false,
      child: KeyboardListener(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: _handleCalculatorKeyboard,
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dialogWidth,
              maxHeight: dialogMaxHeight,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: dialogWidth,
              padding: EdgeInsets.all(compact ? 10 : 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 28,
                    spreadRadius: -10,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final needsScroll = constraints.maxHeight < 680;
                    final body = AnimatedSize(
                      duration: const Duration(milliseconds: 190),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          SizedBox(height: tight ? 8 : 12),
                          _buildModeSelector(),
                          SizedBox(height: tight ? 8 : 12),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 190),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _calculatorOnly
                                ? _buildCalculatorOnlyBody()
                                : _buildProductSaleBody(compact: compact, tight: tight),
                          ),
                        ],
                      ),
                    );

                    if (needsScroll) {
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: body,
                      );
                    }
                    return body;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductSaleBody({required bool compact, bool tight = false}) {
    return Column(
      key: const ValueKey<String>('product-sale-body'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTotalDisplay(compact: true),
        SizedBox(height: tight ? 8 : 12),
        _buildDescriptionField(),
        SizedBox(height: tight ? 6 : 10),
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
            const SizedBox(width: 8),
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
        SizedBox(height: tight ? 4 : 8),
        _buildMoreDataSection(),
        SizedBox(height: tight ? 6 : 10),
        _buildCalculatorHeader(),
        SizedBox(height: tight ? 4 : 8),
        _buildCalculatorPad(),
        SizedBox(height: tight ? 8 : 12),
        _buildFooterActions(),
      ],
    );
  }

  Widget _buildCalculatorOnlyBody() {
    return Column(
      key: const ValueKey<String>('calculator-only-body'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFreeCalculatorDisplay(),
        const SizedBox(height: 10),
        _buildCalculatorPad(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _clearCalculator(keepField: true),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Limpiar'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  foregroundColor: _textPrimary,
                  side: const BorderSide(color: _borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Listo'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  backgroundColor: _brandBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
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
          child: Icon(
            _calculatorOnly ? Icons.calculate_outlined : Icons.calculate_rounded,
            color: _brandBlue,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Column(
              key: ValueKey<bool>(_calculatorOnly),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _calculatorOnly ? 'Calculadora' : 'Venta común',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _brandBlueDark,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    height: 1.05,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _calculatorOnly
                      ? 'Calcula rápido sin agregar productos'
                      : 'Agrega producto o servicio fuera del inventario',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.18,
                  ),
                ),
              ],
            ),
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
              child: Icon(
                Icons.close_rounded,
                color: Color(0xFF475569),
                size: 22,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelector() {
    Widget option({
      required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(9),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected ? const Color(0xFFBFD1F7) : Colors.transparent,
                ),
                boxShadow: [
                  if (selected)
                    BoxShadow(
                      color: _brandBlue.withOpacity(0.08),
                      blurRadius: 10,
                      spreadRadius: -6,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 15,
                    color: selected ? _brandBlue : _textMuted,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? _brandBlue : _textMuted,
                        fontSize: 12.2,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 42,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _softBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          option(
            label: 'Producto',
            icon: Icons.add_shopping_cart_rounded,
            selected: !_calculatorOnly,
            onTap: () => _toggleCalculatorOnly(false),
          ),
          const SizedBox(width: 4),
          option(
            label: 'Solo calculadora',
            icon: Icons.calculate_outlined,
            selected: _calculatorOnly,
            onTap: () => _toggleCalculatorOnly(true),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalDisplay({required bool compact}) {
    final expressionText =
        '${_formatCalcNumber(_qtyValue)} × ${_currency.format(_priceValue)}';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTotalLabel(),
          const SizedBox(height: 8),
          _buildTotalAmount(compact: compact),
          const SizedBox(height: 10),
          _buildTotalExpression(expressionText),
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
        if (_calculatorOnly) return null;
        if (value == null || value.trim().isEmpty) {
          return 'La descripción es requerida';
        }
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
        setState(() {
          _calcExpression = controller.text.trim();
          _calcResultText = '';
        });
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
          borderSide: BorderSide(
            color: isActive ? _brandBlue : Colors.blueGrey,
            width: 1.7,
          ),
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
                  ? 'Calculadora para $_activeFieldLabel'
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
                  color: _calcResultText.contains('inválida')
                      ? _danger
                      : _brandBlue,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFreeCalculatorDisplay() {
    final rawExpression = _calcExpression.trim();
    final expression = rawExpression.isEmpty
        ? '0'
        : rawExpression.replaceAll('*', '×').replaceAll('/', '÷');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Calculadora libre',
            style: TextStyle(
              color: Colors.white.withOpacity(0.72),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            expression,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: Text(
              _calcResultText.isEmpty ? 'Resultado' : _calcResultText,
              key: ValueKey<String>(_calcResultText),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _calcResultText.contains('inválida')
                    ? const Color(0xFFFFD6D6)
                    : Colors.white.withOpacity(
                        _calcResultText.isEmpty ? 0.50 : 0.88,
                      ),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
        ],
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline, size: 19),
            label: const Text('Aplicar a la venta'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              backgroundColor: _brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
