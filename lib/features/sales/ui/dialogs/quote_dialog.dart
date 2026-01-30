import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/sale_item_model.dart';
import '../../data/quote_model.dart';
import '../../data/quotes_repository.dart';
import '../../data/settings_repository.dart';
import '../../../clients/data/client_model.dart';
import '../../../clients/data/clients_repository.dart';
import '../../../clients/ui/client_form_dialog.dart';
import '../../../../core/errors/error_handler.dart';
import '../../../../core/printing/quote_printer.dart';
import '../../../../core/theme/app_status_theme.dart';
import '../../../../core/theme/color_utils.dart';
import '../../../../core/ui/dialog_keyboard_shortcuts.dart';
import '../../../settings/data/printer_settings_repository.dart';

/// Diálogo completo para crear/editar cotizaciones
class QuoteDialog extends StatefulWidget {
  final List<SaleItemModel> items;
  final ClientModel? selectedClient;
  final bool itbisEnabled;
  final double itbisRate;
  final double discountTotal;
  final String? ticketName;

  const QuoteDialog({
    super.key,
    required this.items,
    this.selectedClient,
    this.itbisEnabled = true,
    this.itbisRate = 0.18,
    this.discountTotal = 0,
    this.ticketName,
  });

  @override
  State<QuoteDialog> createState() => _QuoteDialogState();
}

class _QuoteDialogState extends State<QuoteDialog> {
  late List<_QuoteItem> _items;
  ClientModel? _selectedClient;
  bool _itbisEnabled = true;
  double _itbisRate = 0.18;
  double _discountTotal = 0;
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _validDaysController = TextEditingController(
    text: '15',
  );
  bool _isLoading = false;
  List<ClientModel> _clients = [];

  ThemeData get _theme => Theme.of(context);
  ColorScheme get _scheme => _theme.colorScheme;
  AppStatusTheme get _status =>
      _theme.extension<AppStatusTheme>() ??
      AppStatusTheme(
        success: _scheme.primary,
        warning: _scheme.tertiary,
        error: _scheme.error,
        info: _scheme.secondary,
      );

  @override
  void initState() {
    super.initState();
    _items = widget.items.map((item) => _QuoteItem.fromSaleItem(item)).toList();
    _selectedClient = widget.selectedClient;
    _itbisEnabled = widget.itbisEnabled;
    _itbisRate = widget.itbisRate;
    _discountTotal = widget.discountTotal;
    _loadClients();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _validDaysController.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    try {
      final clients = await ClientsRepository.getAll();
      if (!mounted) return;
      setState(() => _clients = clients);
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _loadClients,
        module: 'sales/quote/clients',
      );
    }
  }

  double get _subtotal {
    return _items.fold(0.0, (sum, item) => sum + item.totalLine);
  }

  double get _subtotalAfterDiscount {
    return (_subtotal - _discountTotal).clamp(0.0, double.infinity);
  }

  double get _itbisAmount {
    return _itbisEnabled ? _subtotalAfterDiscount * _itbisRate : 0.0;
  }

  double get _total {
    return _subtotalAfterDiscount + _itbisAmount;
  }

  Future<void> _selectClient() async {
    final result = await showDialog<ClientModel>(
      context: context,
      builder: (context) => _ClientPickerDialog(clients: _clients),
    );

    if (!mounted) return;
    if (result != null) {
      setState(() => _selectedClient = result);
    }
  }

  Future<void> _createNewClient() async {
    final result = await showDialog<ClientModel>(
      context: context,
      builder: (context) => const ClientFormDialog(),
    );

    if (!mounted) return;
    if (result != null) {
      await _loadClients();
      if (!mounted) return;
      setState(() => _selectedClient = result);
    }
  }

  Future<void> _saveQuote({bool print = false, bool preview = false}) async {
    final scheme = Theme.of(context).colorScheme;
    if (_selectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Debe seleccionar un cliente'),
          backgroundColor: scheme.error,
        ),
      );
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Debe agregar al menos un producto'),
          backgroundColor: scheme.error,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Convertir items
      final quoteItems = _items
          .map(
            (item) => QuoteItemModel(
              quoteId: 0,
              productId: item.productId,
              productCode: item.productCode,
              productName: item.description,
              description: item.description,
              qty: item.qty,
              price: item.price,
              cost: item.cost,
              discountLine: item.discount,
              totalLine: item.totalLine,
            ),
          )
          .toList();

      // Guardar cotización
      final quoteId = await QuotesRepository().saveQuote(
        clientId: _selectedClient!.id!,
        userId: null,
        ticketName: widget.ticketName,
        subtotal: _subtotalAfterDiscount,
        itbisEnabled: _itbisEnabled,
        itbisRate: _itbisRate,
        itbisAmount: _itbisAmount,
        discountTotal: _discountTotal,
        total: _total,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        items: quoteItems,
      );

      // Obtener cotización completa
      final quoteDetail = await QuotesRepository().getQuoteById(quoteId);

      if (quoteDetail != null && (print || preview)) {
        final business = await SettingsRepository.getBusinessInfo();
        final settings = await PrinterSettingsRepository.getOrCreate();

        if (preview) {
          // Quitar estado de carga antes de mostrar el preview
          if (mounted) setState(() => _isLoading = false);

          // Mostrar vista previa del PDF
          if (mounted) {
            await QuotePrinter.showPreview(
              context: context,
              quote: quoteDetail.quote,
              items: quoteDetail.items,
              clientName: quoteDetail.clientName,
              clientPhone: quoteDetail.clientPhone,
              clientRnc: quoteDetail.clientRnc,
              business: business,
              validDays: int.tryParse(_validDaysController.text) ?? 15,
            );
          }
        } else if (print) {
          // Imprimir directamente
          await QuotePrinter.printQuote(
            quote: quoteDetail.quote,
            items: quoteDetail.items,
            clientName: quoteDetail.clientName,
            clientPhone: quoteDetail.clientPhone,
            clientRnc: quoteDetail.clientRnc,
            business: business,
            settings: settings,
            validDays: int.tryParse(_validDaysController.text) ?? 15,
          );
        }
      }

      if (mounted) {
        Navigator.pop(
          context,
          QuoteDialogResult(saved: true, quoteId: quoteId, clearCart: true),
        );
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _saveQuote(print: print, preview: preview),
          module: 'sales/quote/save',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
    final headerColor = scheme.primary;
    final headerForeground = ColorUtils.readableTextColor(headerColor);

    return DialogKeyboardShortcuts(
      onSubmit: _isLoading ? null : () => _saveQuote(),
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 700,
          constraints: const BoxConstraints(maxHeight: 800),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: headerColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.description, color: headerForeground, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NUEVA COTIZACIÓN',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: headerForeground,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          'Configure los detalles de la cotización',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: headerForeground.withOpacity(0.8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: headerForeground),
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sección Cliente
                    _buildSectionTitle('CLIENTE', Icons.person),
                    const SizedBox(height: 12),
                    _buildClientSection(),

                    const SizedBox(height: 24),

                    // Sección Productos
                    _buildSectionTitle(
                      'PRODUCTOS (${_items.length})',
                      Icons.shopping_cart,
                    ),
                    const SizedBox(height: 12),
                    _buildItemsList(),

                    const SizedBox(height: 24),

                    // Sección Configuración
                    _buildSectionTitle('CONFIGURACIÓN', Icons.settings),
                    const SizedBox(height: 12),
                    _buildConfigSection(),

                    const SizedBox(height: 24),

                    // Sección Notas
                    _buildSectionTitle('NOTAS', Icons.note),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Notas adicionales para el cliente...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Totales
                    _buildTotalsSection(),
                  ],
                ),
              ),
            ),

            // Footer con acciones
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  // Botón cancelar
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCELAR'),
                  ),
                  const Spacer(),

                  // Botón Vista Previa PDF
                  OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _saveQuote(preview: true),
                    icon: const Icon(Icons.picture_as_pdf, size: 18),
                    label: const Text('VER PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: status.error,
                      side: BorderSide(color: status.error),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Botón Guardar e Imprimir
                  OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => _saveQuote(print: true),
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text('GUARDAR E IMPRIMIR'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.primary,
                      side: BorderSide(color: scheme.primary),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Botón Guardar
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : () => _saveQuote(),
                    icon: _isLoading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: scheme.onPrimary,
                            ),
                          )
                        : const Icon(Icons.save, size: 18),
                    label: const Text('GUARDAR'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
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

  Widget _buildSectionTitle(String title, IconData icon) {
    final scheme = _scheme;
    final theme = _theme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildClientSection() {
    final scheme = _scheme;
    final status = _status;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: _selectedClient == null
          ? Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectClient,
                    icon: const Icon(Icons.search),
                    label: const Text('SELECCIONAR CLIENTE'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _createNewClient,
                  icon: const Icon(Icons.person_add),
                  label: const Text('NUEVO'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: status.success,
                    side: BorderSide(color: status.success),
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 16,
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(Icons.person, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedClient!.nombre,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (_selectedClient!.telefono != null)
                        Text(
                          _selectedClient!.telefono!,
                          style: TextStyle(
                            color: scheme.onSurface.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                      if (_selectedClient!.rnc != null)
                        Text(
                          'RNC: ${_selectedClient!.rnc}',
                          style: TextStyle(
                            color: scheme.onSurface.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _selectedClient = null),
                  icon: Icon(Icons.close, color: status.error),
                  tooltip: 'Cambiar cliente',
                ),
              ],
            ),
    );
  }

  Widget _buildItemsList() {
    final scheme = _scheme;
    final status = _status;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // Header de tabla
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(11),
              ),
            ),
            child: const Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'PRODUCTO',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                Expanded(
                  child: Text(
                    'CANT',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  child: Text(
                    'PRECIO',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  child: Text(
                    'TOTAL',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(width: 40),
              ],
            ),
          ),
          // Items
          ..._items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.description,
                          style: const TextStyle(fontSize: 13),
                        ),
                        Text(
                          item.productCode,
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.qty.toStringAsFixed(
                        item.qty == item.qty.roundToDouble() ? 0 : 2,
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '\$${item.price.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '\$${item.totalLine.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: IconButton(
                      onPressed: () {
                        setState(() => _items.removeAt(index));
                      },
                      icon: Icon(
                        Icons.delete,
                        size: 18,
                        color: status.error,
                      ),
                      tooltip: 'Eliminar',
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildConfigSection() {
    final scheme = _scheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          // Switch ITBIS
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Incluir ITBIS (${(_itbisRate * 100).toInt()}%)',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            value: _itbisEnabled,
            onChanged: (value) => setState(() => _itbisEnabled = value),
            activeThumbColor: scheme.primary,
          ),
          const Divider(),
          // Validez de cotización
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Validez de la cotización:',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _validDaysController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    suffixText: 'días',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsSection() {
    final scheme = _scheme;
    final status = _status;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary, width: 2),
      ),
      child: Column(
        children: [
          _buildTotalRow('Subtotal', _subtotal),
          if (_discountTotal > 0)
            _buildTotalRow('Descuento', -_discountTotal, color: status.error),
          if (_itbisEnabled)
            _buildTotalRow(
              'ITBIS (${(_itbisRate * 100).toInt()}%)',
              _itbisAmount,
            ),
          const Divider(height: 20, thickness: 2),
          _buildTotalRow('TOTAL', _total, isBold: true, fontSize: 20),
        ],
      ),
    );
  }

  Widget _buildTotalRow(
    String label,
    double amount, {
    bool isBold = false,
    double fontSize = 15,
    Color? color,
  }) {
    final scheme = _scheme;
    final labelColor = scheme.onPrimaryContainer;
    final valueColor =
        color ??
        (isBold
            ? scheme.onPrimaryContainer
            : scheme.onPrimaryContainer.withOpacity(0.85));
    final formatter = NumberFormat('#,##0.00', 'en_US');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: labelColor,
            ),
          ),
          Text(
            '\$${formatter.format(amount)}',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Item temporal para cotización
class _QuoteItem {
  final int? productId;
  final String productCode;
  final String description;
  double qty;
  double price;
  double cost;
  double discount;

  _QuoteItem({
    this.productId,
    required this.productCode,
    required this.description,
    required this.qty,
    required this.price,
    this.cost = 0,
    this.discount = 0,
  });

  double get totalLine => (qty * price) - discount;

  factory _QuoteItem.fromSaleItem(SaleItemModel item) {
    return _QuoteItem(
      productId: item.productId,
      productCode: item.productCodeSnapshot,
      description: item.productNameSnapshot,
      qty: item.qty,
      price: item.unitPrice,
      cost: item.purchasePriceSnapshot,
      discount: item.discountLine,
    );
  }
}

/// Resultado del diálogo de cotización
class QuoteDialogResult {
  final bool saved;
  final int? quoteId;
  final bool clearCart;

  QuoteDialogResult({this.saved = false, this.quoteId, this.clearCart = false});
}

/// Diálogo de selección de cliente
class _ClientPickerDialog extends StatefulWidget {
  final List<ClientModel> clients;

  const _ClientPickerDialog({required this.clients});

  @override
  State<_ClientPickerDialog> createState() => _ClientPickerDialogState();
}

class _ClientPickerDialogState extends State<_ClientPickerDialog> {
  String _searchQuery = '';

  List<ClientModel> get _filteredClients {
    if (_searchQuery.isEmpty) return widget.clients;
    final query = _searchQuery.toLowerCase();
    return widget.clients
        .where(
          (c) =>
              c.nombre.toLowerCase().contains(query) ||
              (c.telefono?.contains(query) ?? false) ||
              (c.rnc?.contains(query) ?? false),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DialogKeyboardShortcuts(
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: 400,
          height: 500,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
            const Text(
              'SELECCIONAR CLIENTE',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, teléfono o RNC...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _filteredClients.isEmpty
                  ? const Center(child: Text('No se encontraron clientes'))
                  : ListView.builder(
                      itemCount: _filteredClients.length,
                      itemBuilder: (context, index) {
                        final client = _filteredClients[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            child: Icon(
                              Icons.person,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(client.nombre),
                          subtitle: Text(client.telefono ?? client.rnc ?? ''),
                          onTap: () => Navigator.pop(context, client),
                        );
                      },
                    ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR'),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
