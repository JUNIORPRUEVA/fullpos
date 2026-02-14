import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../../../core/errors/error_handler.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/ui/responsive_grid.dart';
import '../../../core/printing/invoice_letter_pdf.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../../../core/security/scanner_input_controller.dart';
import '../../../core/security/security_config.dart';
import '../../../core/security/app_actions.dart';
import '../../../core/security/authorization_guard.dart';
import '../../../core/security/authz/authz_service.dart';
import '../../../core/security/authz/permission.dart' as authz_perm;
import '../../../core/session/session_manager.dart';
import '../../../core/session/ui_preferences.dart';
import '../../../core/theme/app_gradient_theme.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/color_utils.dart';
import '../../../core/theme/sales_page_theme.dart';
import '../../../core/theme/sales_products_theme.dart';
import '../../../core/widgets/branded_loading_view.dart';
import '../../cash/providers/cash_providers.dart';
import '../../cash/data/cash_movement_model.dart';
import '../../cash/ui/cash_movement_dialog.dart';
import '../../cash/ui/cash_open_dialog.dart';
import '../../clients/data/client_model.dart';
import '../../clients/data/clients_repository.dart';
import '../../clients/ui/client_form_dialog.dart';
import '../../products/data/categories_repository.dart';
import '../../products/data/products_repository.dart';
import '../../products/models/category_model.dart';
import '../../products/models/product_model.dart';
import '../../products/ui/widgets/product_thumbnail.dart';
import '../../settings/data/printer_settings_repository.dart';
import '../../settings/providers/business_settings_provider.dart';
import '../data/app_settings_model.dart';
import '../data/ncf_book_model.dart';
import '../data/ncf_repository.dart';
import '../data/sale_item_model.dart';
import '../data/sale_model.dart';
import '../data/layaway_repository.dart';
import '../data/sales_model.dart' as legacy_sales;
import '../data/sales_repository.dart';
import '../data/settings_repository.dart';
import '../data/temp_cart_repository.dart';
import '../data/tickets_repository.dart';
import '../data/ticket_model.dart';
import 'dialogs/client_picker_dialog.dart';
import 'dialogs/payment_dialog.dart' as payment;
import 'dialogs/product_filter_dialog.dart';
import 'dialogs/quick_item_dialog.dart';
import 'dialogs/quote_dialog.dart';
import 'dialogs/total_discount_dialog.dart';

/// Pantalla principal de POS con múltiples carritos
class SalesPage extends ConsumerStatefulWidget {
  const SalesPage({super.key});

  @override
  ConsumerState<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends ConsumerState<SalesPage> {
  // Productos: tarjetas pequeñas y consistentes (no se inflan por resolución).
  // Ajustes visuales qudel grid de productos (tamaño fijo premium)
  static const double _productCardSize = 104;
  static const double _productTileMaxExtent = 124;
  static const double _minProductCardSize = 72.0;
  static const double _ticketsFooterHeight = 60.0;
  static const double _gridSpacing = 6.0;

  double _productCardSizeFor(double availableWidth) {
    if (!availableWidth.isFinite || availableWidth <= 0) {
      return _minProductCardSize;
    }
    final relativeWidth = (availableWidth / 1200).clamp(0.6, 1.0);
    final scale = relativeWidth < 0.85 ? 0.85 : relativeWidth;
    final size = (_productCardSize * scale).clamp(_minProductCardSize, 130.0);
    return size.isFinite && size > 0 ? size : _minProductCardSize;
  }

  ColorScheme get scheme => Theme.of(context).colorScheme;
  AppStatusTheme get status =>
      Theme.of(context).extension<AppStatusTheme>() ??
      AppStatusTheme(
        success: scheme.tertiary,
        warning: scheme.tertiary,
        error: scheme.error,
        info: scheme.primary,
      );
  Color readableOn(Color bg) => ColorUtils.readableTextColor(bg);
  Color get transparent => scheme.surface.withOpacity(0);
  Color get salesDetailTextColor =>
      Theme.of(context).extension<SalesDetailTextTheme>()?.textColor ??
      scheme.onSurface;

  LinearGradient _resolveBackgroundGradient(AppGradientTheme? gradientTheme) {
    return gradientTheme?.backgroundGradient ??
        LinearGradient(
          colors: [scheme.surface, scheme.primaryContainer],
          stops: const [0.0, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
  }

  LinearGradient _resolveSalesDetailGradient(
    SalesDetailGradientTheme? gradientTheme,
  ) {
    return gradientTheme?.backgroundGradient ??
        LinearGradient(
          colors: [scheme.surface, scheme.surfaceContainerHighest],
          stops: const [0.0, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
  }

  final List<_Cart> _carts = [_Cart(name: 'Ticket 1')];
  int _currentCartIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _clientFocusNode = FocusNode();
  final ScrollController _ticketItemsScrollController = ScrollController();
  Timer? _cartPersistenceTimer;

  int? _filteredProductsCacheKey;
  List<ProductModel> _filteredProductsCache = const <ProductModel>[];

  int? _selectedCartItemIndex;

  bool _keyboardShortcutsEnabled = true;
  ScannerInputController? _scanner;
  late final bool Function(KeyEvent) _globalShortcutHandler;

  String? _lastScanCode;
  int _lastScanAtMs = 0;
  bool? _previousCashOpen;
  int _initialLoadToken = 0;
  bool _loggedFirstBuild = false;

  List<ProductModel> _allProducts = [];
  List<ProductModel> _searchResults = [];
  bool _isSearching = false;

  List<NcfBookModel> _availableNcfs = [];
  List<CategoryModel> _categories = [];
  List<ClientModel> _clients = [];
  AppSettingsModel? _appSettings;
  ProductFilterModel _productFilter = ProductFilterModel();
  String? _selectedCategory;

  _Cart get _currentCart => _carts[_currentCartIndex];

  void _applySalesDefaultsToCart(_Cart cart) {
    final settings = _appSettings;
    if (settings == null) return;

    cart.itbisRate = settings.itbisRate;
    cart.itbisEnabled = settings.itbisEnabledDefault;
    cart.fiscalEnabled = settings.fiscalEnabledDefault;
    if (cart.fiscalEnabled) {
      // Fiscal implica ITBIS activo.
      cart.itbisEnabled = true;
    }
  }

  BoxConstraints _ticketPanelConstraints(double width) {
    // En layout horizontal, hacemos el panel proporcional para no aplastar
    // el grid cuando el ancho baja.
    if (width < 1350) {
      final max = (width * 0.34).clamp(300.0, 400.0);
      final min = (max - 70).clamp(280.0, max);
      return BoxConstraints(minWidth: min, maxWidth: max);
    }
    if (width < 1600) {
      final max = (width * 0.32).clamp(380.0, 460.0);
      final min = (max - 80).clamp(340.0, max);
      return BoxConstraints(minWidth: min, maxWidth: max);
    }
    final max = (width * 0.30).clamp(420.0, 520.0);
    final min = (max - 90).clamp(360.0, max);
    return BoxConstraints(minWidth: min, maxWidth: max);
  }

  @override
  void initState() {
    super.initState();
    _loadAccess();
    _loadInitialData();
    // Evitar modificar providers durante el build inicial (Riverpod lo prohíbe).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _refreshCashSession();
    });
    _loadScannerConfig();
    _globalShortcutHandler = _handleGlobalShortcutKey;
    HardwareKeyboard.instance.addHandler(_globalShortcutHandler);
    RawKeyboard.instance.addListener(_handleScannerKey);
  }

  Future<void> _loadAccess() async {
    final enabled = await UiPreferences.isKeyboardShortcutsEnabled();
    if (!mounted) return;
    setState(() => _keyboardShortcutsEnabled = enabled);
  }

  void _handleScannerKey(RawKeyEvent event) {
    _scanner?.handleKeyEvent(event);
  }

  bool _handleGlobalShortcutKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (Navigator.of(context, rootNavigator: true).canPop()) return false;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.f1) {
      _searchFocusNode.requestFocus();
      return true;
    }

    if (key == LogicalKeyboardKey.f8) {
      if (_currentCart.items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Agrega productos antes de cobrar'),
            backgroundColor: scheme.error,
          ),
        );
        return true;
      }
      _processPayment(SaleKind.invoice, initialPrintTicket: true);
      return true;
    }

    return false;
  }

  Future<void> _loadScannerConfig() async {
    final companyId = await SessionManager.companyId() ?? 1;
    final terminalId =
        await SessionManager.terminalId() ??
        await SessionManager.ensureTerminalId();
    final config = await SecurityConfigRepository.load(
      companyId: companyId,
      terminalId: terminalId,
    );

    if (!mounted) return;

    _scanner?.dispose();
    _scanner = config.scannerEnabled
        ? ScannerInputController(
            enabled: true,
            suffix: config.scannerSuffix,
            prefix: config.scannerPrefix,
            timeout: Duration(milliseconds: config.scannerTimeoutMs),
            emitOnTimeout: false,
            onScan: _handleBarcodeScan,
          )
        : null;
  }

  Future<void> _handleBarcodeScan(
    String raw, {
    bool clearSearchField = false,
  }) async {
    final code = raw.trim();
    if (code.isEmpty) return;

    // Evita duplicados cuando la misma lectura dispara dos rutas:
    // - RawKeyboard/ScannerInputController
    // - TextField.onSubmitted
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_lastScanCode == code && (nowMs - _lastScanAtMs) <= 200) {
      return;
    }
    _lastScanCode = code;
    _lastScanAtMs = nowMs;

    final repo = ProductsRepository();
    ProductModel? product = await ErrorHandler.instance.runSafe<ProductModel?>(
      () => repo.getByCode(code),
      context: context,
      onRetry: () =>
          _handleBarcodeScan(code, clearSearchField: clearSearchField),
      module: 'sales/scan/code',
    );

    if (product == null && code.toUpperCase() != code) {
      product = await ErrorHandler.instance.runSafe<ProductModel?>(
        () => repo.getByCode(code.toUpperCase()),
        context: context,
        onRetry: () =>
            _handleBarcodeScan(code, clearSearchField: clearSearchField),
        module: 'sales/scan/code_upper',
      );
    }

    if (product == null) {
      final results = await ErrorHandler.instance.runSafe<List<ProductModel>>(
        () => repo.search(code),
        context: context,
        onRetry: () =>
            _handleBarcodeScan(code, clearSearchField: clearSearchField),
        module: 'sales/scan/search',
      );
      if (results != null && results.length == 1) {
        product = results.first;
      }
    }

    if (!mounted) return;

    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se encontro producto con codigo: $code'),
          backgroundColor: scheme.error,
        ),
      );
      return;
    }

    await _addProductToCart(product);
    if (clearSearchField && mounted) {
      _searchController.clear();
      _searchFocusNode.requestFocus();
      setState(() {
        _searchResults = _allProducts;
      });
    }
  }

  Future<void> _loadInitialData() async {
    final token = ++_initialLoadToken;
    setState(() => _isSearching = true);
    // Deja que se pinte al menos 1 frame antes de ejecutar consultas pesadas.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || token != _initialLoadToken) return;

    debugPrint(
      '[SALES] sales-data-load-start t=${DateTime.now().toIso8601String()}',
    );

    final productsRepo = ProductsRepository();
    final categoriesRepo = CategoriesRepository();
    final ticketsRepo = TicketsRepository();
    final tempCartRepo = TempCartRepository();

    try {
      final results = await Future.wait([
        productsRepo.getAll(),
        categoriesRepo.getAll(),
        ClientsRepository.getAll(),
        ticketsRepo.listTickets(),
        tempCartRepo.getAllCarts(),
        SettingsRepository.getAppSettings(),
      ]);
      if (!mounted || token != _initialLoadToken) return;

      final products = results[0] as List<ProductModel>;
      final categories = results[1] as List<CategoryModel>;
      final clients = results[2] as List<ClientModel>;
      final dbTickets = results[3] as List<PosTicketModel>;
      final tempCarts = results[4] as List<Map<String, dynamic>>;
      final appSettings = results[5] as AppSettingsModel;

      final loadedCarts = <_Cart>[];

      // Convertir tickets de BD a _Cart objects (batch para evitar N queries).
      final ticketIds = dbTickets.map((t) => t.id).whereType<int>().toList();
      final ticketItemsById = await ticketsRepo.getTicketItemsByTicketIds(
        ticketIds,
      );
      if (!mounted || token != _initialLoadToken) return;

      for (final ticketModel in dbTickets) {
        final id = ticketModel.id;
        if (id == null) continue;
        final cart = _Cart(name: ticketModel.ticketName)
          ..ticketId = id
          ..itbisEnabled = ticketModel.itbisEnabled
          ..itbisRate = ticketModel.itbisRate
          ..discount = ticketModel.discountTotal;

        final cartItems = ticketItemsById[id] ?? const <PosTicketItemModel>[];
        for (final itemModel in cartItems) {
          cart.items.add(
            SaleItemModel(
              id: itemModel.id,
              saleId: 0,
              productId: itemModel.productId,
              productCodeSnapshot: itemModel.productCodeSnapshot,
              productNameSnapshot: itemModel.productNameSnapshot,
              qty: itemModel.qty,
              unitPrice: itemModel.price,
              discountLine: itemModel.discountLine,
              purchasePriceSnapshot: itemModel.cost,
              totalLine: itemModel.totalLine,
              createdAtMs: 0,
            ),
          );
        }

        loadedCarts.add(cart);
      }

      // Cargar carritos temporales (batch para evitar N queries).
      final cartIds = tempCarts
          .map((m) => m['id'])
          .whereType<int>()
          .toList(growable: false);
      final tempCartItemsById = await tempCartRepo.getCartItemsByCartIds(
        cartIds,
      );
      if (!mounted || token != _initialLoadToken) return;

      for (final cartMap in tempCarts) {
        final id = cartMap['id'] as int?;
        if (id == null) continue;
        final cart = _Cart(name: cartMap['name'] as String)
          ..tempCartId = id
          ..discount = (cartMap['discount'] as num).toDouble()
          ..itbisEnabled = (cartMap['itbis_enabled'] as int) == 1
          ..itbisRate = (cartMap['itbis_rate'] as num).toDouble()
          ..fiscalEnabled = (cartMap['fiscal_enabled'] as int) == 1
          ..discountTotalType = cartMap['discount_total_type'] as String?
          ..discountTotalValue = (cartMap['discount_total_value'] as num?)
              ?.toDouble();

        final clientId = cartMap['client_id'] as int?;
        if (clientId != null) {
          final client = clients.where((c) => c.id == clientId).firstOrNull;
          if (client != null) cart.selectedClient = client;
        }

        cart.items.addAll(tempCartItemsById[id] ?? const <SaleItemModel>[]);
        loadedCarts.add(cart);
      }

      if (!mounted || token != _initialLoadToken) return;

      setState(() {
        _allProducts = products;
        _searchResults = products;
        _categories = categories;
        _clients = clients;
        _appSettings = appSettings;
        if (loadedCarts.isNotEmpty) {
          _carts.clear();
          _carts.addAll(loadedCarts);
          _currentCartIndex = 0;
        } else {
          // Si no hay carritos cargados, aplicar defaults al carrito inicial.
          if (_carts.isNotEmpty) {
            _applySalesDefaultsToCart(_carts.first);
          }
        }
        _isSearching = false;
      });

      debugPrint(
        '[SALES] sales-data-ready t=${DateTime.now().toIso8601String()} '
        'products=${products.length} categories=${categories.length} clients=${clients.length}',
      );
    } catch (e) {
      if (!mounted || token != _initialLoadToken) return;
      setState(() => _isSearching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo cargar Ventas: $e'),
          backgroundColor: scheme.error,
        ),
      );
    }
  }

  Future<void> _refreshCashSession() async {
    await ref.read(cashSessionControllerProvider.notifier).refresh();
  }

  int? get _activeSessionId =>
      ref.read(cashSessionControllerProvider).valueOrNull?.id;

  Future<void> _openCashMovement(String type) async {
    var sessionId = _activeSessionId;
    if (sessionId == null) {
      final opened = await CashOpenDialog.show(context);
      if (opened == true) await _refreshCashSession();
      sessionId = _activeSessionId;
    }

    if (!mounted) return;

    if (sessionId == null) {
      // Solo mostrar el mensaje si el usuario intenta abrir un movimiento de caja, no al cargar la pantalla.
      // Si la acción fue disparada por el usuario (por botón, etc.), mostrar el mensaje. Si es por navegación, no hacer nada.
      // Aquí simplemente retornamos silenciosamente.
      return;
    }

    await CashMovementDialog.show(context, type: type, sessionId: sessionId);
    await _refreshCashSession();
  }

  /// Guarda todos los carritos temporales en la base de datos
  // ignore: unused_element
  Future<void> _saveAllCartsToDatabase() async {
    final tempCartRepo = TempCartRepository();

    for (final cart in _carts) {
      // Solo guardar carritos que no sean tickets pendientes y tengan items
      if (cart.ticketId == null && cart.items.isNotEmpty) {
        try {
          await tempCartRepo.saveCart(
            id: cart.tempCartId,
            name: cart.name,
            userId: null,
            clientId: cart.selectedClient?.id,
            discount: cart.discount,
            itbisEnabled: cart.itbisEnabled,
            itbisRate: cart.itbisRate,
            fiscalEnabled: cart.fiscalEnabled,
            discountTotalType: cart.discountTotalType,
            discountTotalValue: cart.discountTotalValue,
            items: cart.items,
          );
        } catch (e) {
          debugPrint('Error guardando carrito temporal: $e');
        }
      }
    }
  }

  /// Elimina el carrito temporal de la base de datos
  Future<void> _deleteCurrentCartFromDatabase() async {
    if (_currentCart.tempCartId != null) {
      try {
        await TempCartRepository().deleteCart(_currentCart.tempCartId!);
      } catch (e) {
        debugPrint('Error eliminando carrito temporal: $e');
      }
    }
  }

  Future<void> _deleteTempCartFromDatabase(int? tempCartId) async {
    if (tempCartId == null) return;
    try {
      await TempCartRepository().deleteCart(tempCartId);
    } catch (e) {
      debugPrint('Error eliminando carrito temporal: $e');
    }
  }

  Future<void> _runSaleOutputs({
    required int saleId,
    required bool shouldPrint,
    required bool shouldDownloadInvoicePdf,
    required bool isLayaway,
    required double receivedAmount,
  }) async {
    legacy_sales.SaleModel? saleForOutput;
    List<legacy_sales.SaleItemModel> saleItemsForOutput =
        const <legacy_sales.SaleItemModel>[];

    try {
      saleForOutput = await SalesRepository.getSaleById(saleId);
      saleItemsForOutput = await SalesRepository.getItemsBySaleId(saleId);
    } catch (e) {
      debugPrint('Error al cargar venta para salida: $e');
      return;
    }

    if (shouldPrint) {
      try {
        final sale = saleForOutput;
        final items = saleItemsForOutput;
        if (sale != null) {
          final settings = await PrinterSettingsRepository.getOrCreate();
          if (settings.selectedPrinterName != null &&
              settings.selectedPrinterName!.isNotEmpty) {
            final cashierName = await SessionManager.displayName() ?? 'Cajero';
            final double pendingAfter = (sale.total - sale.paidAmount).clamp(
              0,
              double.infinity,
            );
            final layawayStatusLabel = pendingAfter > 0
                ? 'PENDIENTE'
                : 'PAGADO';
            await UnifiedTicketPrinter.printSaleTicket(
              sale: sale,
              items: items,
              cashierName: cashierName,
              isLayaway: isLayaway,
              pendingAmount: isLayaway ? pendingAfter : 0,
              lastPaymentAmount: isLayaway ? receivedAmount : 0,
              statusLabel: isLayaway ? layawayStatusLabel : sale.status,
            );
          }
        }
      } catch (e) {
        debugPrint('Error al imprimir ticket: $e');
      }
    }

    if (shouldDownloadInvoicePdf) {
      try {
        final sale = saleForOutput;
        if (sale != null) {
          await _downloadInvoiceLetterPdf(sale, saleItemsForOutput);
        }
      } catch (e) {
        debugPrint('Error al descargar factura PDF: $e');
      }
    }
  }

  void _updateCurrentCart(VoidCallback update) {
    setState(update);
    _scheduleCartPersistence();
  }

  void _scheduleCartPersistence() {
    _cartPersistenceTimer?.cancel();
    _cartPersistenceTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persistCurrentCartToDatabase());
    });
  }

  Future<void> _persistCurrentCartToDatabase() async {
    _cartPersistenceTimer = null;
    if (!mounted) return;
    if (_currentCart.items.isEmpty) {
      await _deleteCurrentCartFromDatabase();
      return;
    }

    final repo = TempCartRepository();
    final userId = await SessionManager.userId();
    try {
      final savedId = await repo.saveCart(
        id: _currentCart.tempCartId,
        name: _currentCart.name,
        userId: userId,
        clientId: _currentCart.selectedClient?.id,
        discount: _currentCart.discount,
        itbisEnabled: _currentCart.itbisEnabled,
        itbisRate: _currentCart.itbisRate,
        fiscalEnabled: _currentCart.fiscalEnabled,
        discountTotalType: _currentCart.discountTotalType,
        discountTotalValue: _currentCart.discountTotalValue,
        items: _currentCart.items,
      );
      _currentCart.tempCartId = savedId;
    } catch (e, st) {
      debugPrint('Error guardando carrito temporal: $e $st');
    }
  }

  Future<void> _loadAvailableNcfs() async {
    try {
      final all = await NcfRepository.getAll();
      final available = all.where((ncf) => ncf.isAvailable).toList();
      if (!mounted) return;
      setState(() {
        _availableNcfs = available;

        // Asegura que el dropdown siempre tenga un value que exista en los items
        if (_currentCart.fiscalEnabled) {
          final selected = _currentCart.selectedNcf;
          if (selected?.id != null) {
            final match = available.where((b) => b.id == selected!.id).toList();
            _currentCart.selectedNcf = match.isNotEmpty
                ? match.first
                : (available.isNotEmpty ? available.first : null);
          } else if (selected != null) {
            final match = available
                .where(
                  (b) =>
                      b.type == selected.type &&
                      b.series == selected.series &&
                      b.fromN == selected.fromN &&
                      b.toN == selected.toN,
                )
                .toList();
            _currentCart.selectedNcf = match.isNotEmpty
                ? match.first
                : (available.isNotEmpty ? available.first : null);
          } else {
            _currentCart.selectedNcf = available.isNotEmpty
                ? available.first
                : null;
          }
        }
      });
      _scheduleCartPersistence();
    } catch (e, st) {
      debugPrint('Error loading NCF books: $e\\n$st');
    }
  }

  // Ajusta el stock localmente tras completar una venta para reflejar el inventario actualizado
  void _applyStockAdjustments(List<SaleItemModel> items) {
    if (items.isEmpty) return;

    final Map<int, double> deltas = {};
    for (final item in items) {
      final productId = item.productId;
      if (productId != null) {
        deltas.update(
          productId,
          (value) => value + item.qty,
          ifAbsent: () => item.qty,
        );
      }
    }

    if (deltas.isEmpty) return;

    double newStock(double current, double delta) {
      final updated = current - delta;
      return updated < 0 ? 0 : updated;
    }

    setState(() {
      _allProducts = _allProducts
          .map(
            (p) => deltas.containsKey(p.id)
                ? p.copyWith(stock: newStock(p.stock, deltas[p.id]!))
                : p,
          )
          .toList();

      _searchResults = _searchResults
          .map(
            (p) => deltas.containsKey(p.id)
                ? p.copyWith(stock: newStock(p.stock, deltas[p.id]!))
                : p,
          )
          .toList();
    });
  }

  List<ProductModel> _filteredProducts() {
    final source = _searchController.text.trim().isEmpty
        ? _allProducts
        : _searchResults;

    final cacheKey = Object.hash(
      _searchController.text.trim().isEmpty,
      identityHashCode(source),
      source.length,
      identityHashCode(_categories),
      _categories.length,
      _selectedCategory,
      _productFilter.onlyWithStock,
      _productFilter.minPrice,
      _productFilter.maxPrice,
      _productFilter.sortBy,
    );
    if (_filteredProductsCacheKey == cacheKey) {
      return _filteredProductsCache;
    }

    int? selectedCategoryId;
    if (_selectedCategory != null && _selectedCategory != 'Todos') {
      for (final c in _categories) {
        if (c.name == _selectedCategory) {
          selectedCategoryId = c.id;
          break;
        }
      }
    }

    final filtered = source.where((p) {
      if (selectedCategoryId != null && p.categoryId != selectedCategoryId) {
        return false;
      }
      if (_productFilter.onlyWithStock && p.stock <= 0) return false;
      if (_productFilter.minPrice != null &&
          p.salePrice < _productFilter.minPrice!) {
        return false;
      }
      if (_productFilter.maxPrice != null &&
          p.salePrice > _productFilter.maxPrice!) {
        return false;
      }
      return true;
    }).toList();

    switch (_productFilter.sortBy) {
      case ProductSortBy.nameAsc:
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case ProductSortBy.nameDesc:
        filtered.sort((a, b) => b.name.compareTo(a.name));
        break;
      case ProductSortBy.priceAsc:
        filtered.sort((a, b) => a.salePrice.compareTo(b.salePrice));
        break;
      case ProductSortBy.priceDesc:
        filtered.sort((a, b) => b.salePrice.compareTo(a.salePrice));
        break;
      case ProductSortBy.stockAsc:
        filtered.sort((a, b) => a.stock.compareTo(b.stock));
        break;
      case ProductSortBy.stockDesc:
        filtered.sort((a, b) => b.stock.compareTo(a.stock));
        break;
    }

    final cached = List<ProductModel>.unmodifiable(filtered);
    _filteredProductsCacheKey = cacheKey;
    _filteredProductsCache = cached;
    return cached;
  }

  Future<void> _searchProducts(String query) async {
    if (!mounted) return;
    setState(() => _isSearching = true);
    final repo = ProductsRepository();
    final trimmed = query.trim();
    final results = trimmed.isEmpty
        ? await repo.getAll()
        : await repo.search(trimmed);

    if (!mounted) return;

    setState(() {
      _searchResults = results;
      if (trimmed.isEmpty) _allProducts = results;
      _isSearching = false;
    });
  }

  Future<bool> _authorizeAction(
    AppAction action, {
    String resourceType = 'sale',
    String? resourceId,
    String? reason,
  }) async {
    return requireAuthorizationIfNeeded(
      context: context,
      action: action,
      resourceType: resourceType,
      resourceId: resourceId,
      reason: reason,
      isOnline: true,
    );
  }

  Future<T?> _presentDialog<T>({
    required WidgetBuilder builder,
    bool barrierDismissible = true,
    bool useRootNavigator = true,
    Color? barrierColor,
    String? barrierLabel,
    RouteSettings? routeSettings,
  }) async {
    if (!mounted) return null;
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel: barrierLabel,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      builder: builder,
    );
  }

  void _onCategorySelected(String? categoryName) {
    setState(
      () => _selectedCategory = categoryName == 'Todos' ? null : categoryName,
    );
  }

  Future<void> _openFilterDialog() async {
    final result = await _presentDialog<ProductFilterModel>(
      builder: (context) => ProductFilterDialog(
        initialFilter: _productFilter,
        categories: _categories
            .map((c) => {'id': c.id, 'name': c.name})
            .toList(),
      ),
    );

    if (!mounted || result == null) return;
    setState(() => _productFilter = result);
  }

  Future<ClientModel?> _showClientPicker() async {
    final result = await _presentDialog<ClientModel>(
      builder: (context) => ClientPickerDialog(clients: _clients),
    );

    if (!mounted || result == null) return null;
    _updateCurrentCart(() {
      _currentCart.selectedClient = result;
      _currentCart.name = result.nombre;
    });
    if (_currentCart.ticketId != null) {
      final ticketId = _currentCart.ticketId!;
      await ErrorHandler.instance.runSafe<void>(
        () => TicketsRepository().updateTicketName(ticketId, result.nombre),
        context: context,
        onRetry: () => ErrorHandler.instance.runSafe<void>(
          () => TicketsRepository().updateTicketName(ticketId, result.nombre),
          context: context,
          module: 'sales/ticket_name',
        ),
        module: 'sales/ticket_name',
      );
    }

    return result;
  }

  Future<void> _showQuickItemDialog() async {
    final result = await _presentDialog<SaleItemModel>(
      builder: (context) => const QuickItemDialog(),
    );

    if (!mounted || result == null) return;
    _updateCurrentCart(() => _currentCart.items.add(result));
  }

  Future<void> _showTotalDiscountDialog() async {
    if (_currentCart.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Agrega productos antes de aplicar descuento'),
          backgroundColor: status.warning,
        ),
      );
      return;
    }

    final currentDiscount =
        _currentCart.discountTotalValue != null &&
            _currentCart.discountTotalValue! > 0
        ? DiscountResult(
            type: _currentCart.discountTotalType == 'percent'
                ? DiscountType.percent
                : DiscountType.amount,
            value: _currentCart.discountTotalValue!,
          )
        : null;

    final result = await _presentDialog<dynamic>(
      builder: (context) => TotalDiscountDialog(
        subtotal: _currentCart.calculateSubtotal(),
        itbisRate: _currentCart.itbisRate,
        currentDiscount: currentDiscount,
      ),
    );

    if (!mounted) return;

    if (result == 'remove') {
      _updateCurrentCart(() {
        _currentCart.discountTotalType = null;
        _currentCart.discountTotalValue = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Descuento eliminado'),
          backgroundColor: status.success,
        ),
      );
      return;
    }

    if (result is DiscountResult) {
      final ticketId = _currentCart.ticketId?.toString();
      final canDiscount = await _authorizeAction(
        AppActions.applyDiscount,
        resourceType: 'sale',
        resourceId: ticketId,
        reason: 'Aplicar descuento',
      );
      if (!canDiscount) return;

      if (result.type == DiscountType.percent && result.value > 15.0) {
        final canOverLimit = await _authorizeAction(
          AppActions.applyDiscountOverLimit,
          resourceType: 'sale',
          resourceId: ticketId,
          reason: 'Descuento > 15%',
        );
        if (!canOverLimit) return;
      }

      if (!mounted) return;
      _updateCurrentCart(() {
        _currentCart.discountTotalType = result.type == DiscountType.percent
            ? 'percent'
            : 'amount';
        _currentCart.discountTotalValue = result.value;
      });
      final discountLabel = result.type == DiscountType.percent
          ? 'Descuento aplicado: ${result.value.toStringAsFixed(1)}%'
          : 'Descuento aplicado: RD\$ ${result.value.toStringAsFixed(2)}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(discountLabel), backgroundColor: status.success),
      );
    }
  }

  void _removeClient() {
    final ticketIndex = _carts.indexOf(_currentCart);
    _updateCurrentCart(() {
      _currentCart.selectedClient = null;
      _currentCart.name = 'Ticket ${ticketIndex + 1}';
    });
  }

  Future<void> _addProductToCart(ProductModel product) async {
    final qtyInCart = _currentCart.getQuantityForProduct(product.id ?? -1);
    final effectiveStock = product.stock - qtyInCart;
    if (effectiveStock <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Producto sin stock disponible'),
          backgroundColor: scheme.error,
        ),
      );
      return;
    }

    _updateCurrentCart(() => _currentCart.addProduct(product));
  }

  void _incrementCartItemQty(SaleItemModel item, int index) async {
    if (item.productId == null) {
      _updateCurrentCart(
        () => _currentCart.updateQuantity(index, item.qty + 1),
      );
      return;
    }

    final repo = ProductsRepository();
    final product = await ErrorHandler.instance.runSafe<ProductModel?>(
      () => repo.getById(item.productId!),
      context: context,
      onRetry: () => _incrementCartItemQty(item, index),
      module: 'sales/product_get',
    );
    if (!mounted) return;
    if (product == null) return;
    final available =
        product.stock - _currentCart.getQuantityForProduct(item.productId!);
    if (available <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stock insuficiente'),
          backgroundColor: scheme.error,
        ),
      );
      return;
    }

    if (!mounted) return;
    _updateCurrentCart(() => _currentCart.updateQuantity(index, item.qty + 1));
  }

  void _showEditItemDialog(SaleItemModel item, int index) {
    final qtyController = TextEditingController(
      text: item.qty.toStringAsFixed(0),
    );
    final discountController = TextEditingController(
      text: item.discountLine.toStringAsFixed(2),
    );
    String discountMode = 'amount';

    double computeBaseSubtotal() {
      final qty = double.tryParse(qtyController.text) ?? item.qty;
      return qty * item.unitPrice;
    }

    double computeDiscountAmount() {
      final base = computeBaseSubtotal();
      final raw = double.tryParse(discountController.text) ?? 0.0;
      if (discountMode == 'percent') {
        final pct = raw.clamp(0.0, 100.0);
        return base * (pct / 100);
      }
      return raw.clamp(0.0, base);
    }

    _presentDialog<void>(
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final subtotal = computeBaseSubtotal();
          final discountAmount = computeDiscountAmount();
          final total = (subtotal - discountAmount).clamp(0.0, double.infinity);

          void saveItemChanges() {
            final newQty = double.tryParse(qtyController.text) ?? item.qty;
            final discountToApply = computeDiscountAmount();

            if (newQty <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('La cantidad debe ser mayor a 0'),
                  backgroundColor: scheme.error,
                ),
              );
              return;
            }

            _updateCurrentCart(() {
              _currentCart.items[index] = item.copyWith(
                qty: newQty,
                discountLine: discountToApply,
              );
            });
            Navigator.pop(context);
          }

          return _DialogHotkeys(
            onEnter: saveItemChanges,
            child: AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 32,
              ),
              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.percent, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.productNameSnapshot,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'C?digo: ${item.productCodeSnapshot}',
                        style: TextStyle(
                          color: scheme.onSurface.withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Precio unitario: ${item.unitPrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: scheme.onSurface.withOpacity(0.6),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: qtyController,
                        decoration: const InputDecoration(
                          labelText: 'Cantidad',
                          prefixIcon: Icon(Icons.numbers),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setStateDialog(() {}),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Monto'),
                            selected: discountMode == 'amount',
                            onSelected: (_) =>
                                setStateDialog(() => discountMode = 'amount'),
                          ),
                          ChoiceChip(
                            label: const Text('Porcentaje'),
                            selected: discountMode == 'percent',
                            onSelected: (_) =>
                                setStateDialog(() => discountMode = 'percent'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: discountController,
                        decoration: InputDecoration(
                          labelText: discountMode == 'percent'
                              ? 'Descuento (%)'
                              : 'Descuento (RD\$)',
                          prefixIcon: const Icon(Icons.local_offer),
                          border: const OutlineInputBorder(),
                          helperText: discountMode == 'percent'
                              ? 'Aplica % sobre el subtotal de este producto'
                              : 'Monto fijo a descontar',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setStateDialog(() {}),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Subtotal:',
                                  style: TextStyle(fontSize: 13),
                                ),
                                Text(
                                  subtotal.toStringAsFixed(2),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  discountMode == 'percent'
                                      ? 'Descuento (${(double.tryParse(discountController.text) ?? 0).clamp(0.0, 100.0).toStringAsFixed(1)}%)'
                                      : 'Descuento:',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                Text(
                                  '-${discountAmount.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.error,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Total:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  total.toStringAsFixed(2),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: saveItemChanges,
                  icon: const Icon(Icons.check),
                  label: const Text('Aplicar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  bool _canEnableFiscalOrNotify() {
    final missing = <String>[];
    final client = _currentCart.selectedClient;

    if (client == null) {
      missing.add('Cliente');
    } else {
      final rnc = (client.rnc ?? '').trim();
      if (rnc.isEmpty) missing.add('RNC del cliente');
    }

    if (missing.isEmpty) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No se puede activar NCF. Falta: ${missing.join(', ')}.'),
        backgroundColor: scheme.error,
      ),
    );
    return false;
  }

  bool _canProceedWithFiscalOrNotify() {
    if (!_currentCart.fiscalEnabled) return true;

    final missing = <String>[];
    final client = _currentCart.selectedClient;
    if (client == null) {
      missing.add('Cliente');
    } else {
      final rnc = (client.rnc ?? '').trim();
      if (rnc.isEmpty) missing.add('RNC del cliente');
    }

    if (!_currentCart.itbisEnabled) missing.add('ITBIS');

    if (missing.isEmpty) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No se puede continuar con NCF. Falta: ${missing.join(', ')}.',
        ),
        backgroundColor: scheme.error,
      ),
    );
    return false;
  }

  Future<void> _processPayment(
    String kind, {
    bool initialPrintTicket = false,
  }) async {
    if (_currentCart.items.isEmpty) return;

    if (!_canProceedWithFiscalOrNotify()) return;

    if (_currentCart.fiscalEnabled && _availableNcfs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No hay NCF disponibles. Hable con Administración para agregarlo.',
          ),
          backgroundColor: scheme.error,
        ),
      );
      return;
    }

    if (_currentCart.fiscalEnabled && _currentCart.selectedNcf == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Seleccione un Comprobante Fiscal (NCF)'),
          backgroundColor: scheme.error,
        ),
      );
      return;
    }

    final canCharge = await _authorizeAction(
      AppActions.chargeSale,
      resourceType: 'sale',
      resourceId: _currentCart.ticketId?.toString(),
    );
    if (!canCharge) return;

    // Importante: usar las funciones del carrito como fuente única.
    // Evita doble descuento (bug: totales guardados/impresos en 0).
    final totalDiscount = _currentCart.calculateTotalDiscountsCombined();
    final subtotalAfterDiscount = _currentCart.calculateSubtotalAfterDiscount();
    final itbisAmount = _currentCart.calculateItbis();
    final total = _currentCart.calculateTotal();
    final paymentResult = await _presentDialog<Map<String, dynamic>>(
      builder: (context) => payment.PaymentDialog(
        total: total,
        initialPrintTicket: initialPrintTicket,
        allowInvoicePdfDownload: kind == SaleKind.invoice,
        selectedClient: _currentCart.selectedClient,
        onSelectClient: _showClientPicker,
      ),
    );

    if (!mounted || paymentResult == null) return;

    // Permite que el cierre del dialogo se renderice antes de continuar con
    // operaciones pesadas (DB/PDF/impresion). Evita que se "congele" la UI con
    // el dialogo aun visible.
    await WidgetsBinding.instance.endOfFrame;
    // En desktop (Windows/Linux/macOS) el cierre del dialog puede quedar visualmente
    // “pegado” si arrancamos trabajo pesado inmediatamente, y parece que hay que
    // presionar Cobrar dos veces. Dar un pequeño margen para completar la animación.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }
    if (!mounted) return;

    final method = paymentResult['method'] as payment.PaymentMethod;
    final receivedAmountRaw =
        (paymentResult['received'] as num?)?.toDouble() ?? total;
    final changeAmountRaw =
        (paymentResult['change'] as num?)?.toDouble() ?? 0.0;
    final bool isCreditPayment = method == payment.PaymentMethod.credit;
    final receivedAmount = isCreditPayment ? 0.0 : receivedAmountRaw;
    final changeAmount = isCreditPayment ? 0.0 : changeAmountRaw;
    final shouldPrint = paymentResult['printTicket'] == true;
    final shouldDownloadInvoicePdf =
        paymentResult['downloadInvoicePdf'] == true;

    if (method == payment.PaymentMethod.credit) {
      final canCredit = await _authorizeAction(
        AppActions.grantCredit,
        resourceType: 'sale',
        resourceId: _currentCart.ticketId?.toString(),
      );
      if (!canCredit) return;
    }

    if (method == payment.PaymentMethod.layaway) {
      final canLayaway = await _authorizeAction(
        AppActions.createLayaway,
        resourceType: 'sale',
        resourceId: _currentCart.ticketId?.toString(),
      );
      if (!canLayaway) return;

      if (_activeSessionId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Debe abrir caja para crear un apartado'),
            backgroundColor: scheme.error,
          ),
        );
        return;
      }
    }

    final localCode = await SalesRepository.generateNextLocalCode(kind);
    String? ncfFull;
    String? ncfType;
    if (_currentCart.fiscalEnabled && _currentCart.selectedNcf != null) {
      final selected = _currentCart.selectedNcf!;
      ncfType = selected.type;

      // Consumir el NCF del talonario seleccionado (evita consumir otro libro del mismo tipo)
      if (selected.id != null) {
        ncfFull = await NcfRepository.consumeNextForBook(selected.id!);
      } else {
        ncfFull = await NcfRepository.consumeNext(selected.type);
      }

      if (ncfFull == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No hay NCF disponibles para el talonario seleccionado',
            ),
            backgroundColor: scheme.error,
          ),
        );
        return;
      }
    }

    final paymentMethodStr = switch (method) {
      payment.PaymentMethod.cash => PaymentMethod.cash,
      payment.PaymentMethod.card => PaymentMethod.card,
      payment.PaymentMethod.transfer => PaymentMethod.transfer,
      payment.PaymentMethod.mixed => PaymentMethod.mixed,
      payment.PaymentMethod.credit => PaymentMethod.credit,
      payment.PaymentMethod.layaway => PaymentMethod.layaway,
    };

    final bool isLayaway = method == payment.PaymentMethod.layaway;

    final productsRepo = ProductsRepository();
    final List<SaleItemModel> itemsPayload = [];

    for (final item in _currentCart.items) {
      var enriched = item;

      // Refresca datos del producto para guardar código, nombre, precio y costo actuales
      if (item.productId != null) {
        final product = await productsRepo.getById(item.productId!);
        if (product != null) {
          enriched = enriched.copyWith(
            productCodeSnapshot: enriched.productCodeSnapshot.isNotEmpty
                ? enriched.productCodeSnapshot
                : product.code,
            productNameSnapshot: enriched.productNameSnapshot.isNotEmpty
                ? enriched.productNameSnapshot
                : product.name,
            unitPrice: enriched.unitPrice > 0
                ? enriched.unitPrice
                : product.salePrice,
            purchasePriceSnapshot: enriched.purchasePriceSnapshot > 0
                ? enriched.purchasePriceSnapshot
                : product.purchasePrice,
          );
        }
      }

      final totalLine =
          (enriched.qty * enriched.unitPrice) - enriched.discountLine;
      itemsPayload.add(enriched.copyWith(totalLine: totalLine));
    }

    int saleId;
    final int? tempCartIdToDelete = _currentCart.tempCartId;
    final int cartIndexToRemove = _currentCartIndex;
    try {
      if (isLayaway) {
        saleId = await LayawayRepository.createLayawaySale(
          localCode: localCode,
          kind: kind,
          items: itemsPayload,
          itbisEnabled: _currentCart.itbisEnabled,
          itbisRate: _currentCart.itbisRate,
          discountTotal: totalDiscount,
          subtotalOverride: subtotalAfterDiscount,
          itbisAmountOverride: itbisAmount,
          totalOverride: total,
          fiscalEnabled: _currentCart.fiscalEnabled,
          ncfFull: ncfFull,
          ncfType: ncfType,
          sessionId: _activeSessionId,
          customerId: _currentCart.selectedClient?.id,
          customerName: _currentCart.selectedClient?.nombre,
          customerPhone: _currentCart.selectedClient?.telefono,
          initialPayment: receivedAmount,
          note: paymentResult['note'] as String?,
        );
      } else {
        saleId = await SalesRepository.createSale(
          localCode: localCode,
          kind: kind,
          items: itemsPayload,
          itbisEnabled: _currentCart.itbisEnabled,
          itbisRate: _currentCart.itbisRate,
          discountTotal: totalDiscount,
          subtotalOverride: subtotalAfterDiscount,
          itbisAmountOverride: itbisAmount,
          totalOverride: total,
          paymentMethod: paymentMethodStr,
          sessionId: _activeSessionId,
          customerId: _currentCart.selectedClient?.id,
          customerName: _currentCart.selectedClient?.nombre,
          customerPhone: _currentCart.selectedClient?.telefono,
          ncfFull: ncfFull,
          ncfType: ncfType,
          fiscalEnabled: _currentCart.fiscalEnabled,
          paidAmount: receivedAmount,
          changeAmount: changeAmount > 0 ? changeAmount : 0,
        );
      }
    } on AppException catch (e, st) {
      if (e.code != 'stock_negative') {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          module: 'sales',
        );
        return;
      }

      final proceed = await _presentDialog<bool>(
        builder: (context) => AlertDialog(
          title: const Text('Stock insuficiente'),
          content: Text(e.messageUser),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('CONTINUAR'),
            ),
          ],
        ),
      );

      if (!mounted || proceed != true) return;

      final retry = await ErrorHandler.instance.runSafe<int>(
        () => SalesRepository.createSale(
          localCode: localCode,
          kind: kind,
          items: itemsPayload,
          allowNegativeStock: true,
          itbisEnabled: _currentCart.itbisEnabled,
          itbisRate: _currentCart.itbisRate,
          discountTotal: totalDiscount,
          subtotalOverride: subtotalAfterDiscount,
          itbisAmountOverride: itbisAmount,
          totalOverride: total,
          paymentMethod: paymentMethodStr,
          sessionId: _activeSessionId,
          customerId: _currentCart.selectedClient?.id,
          customerName: _currentCart.selectedClient?.nombre,
          customerPhone: _currentCart.selectedClient?.telefono,
          ncfFull: ncfFull,
          ncfType: ncfType,
          fiscalEnabled: _currentCart.fiscalEnabled,
          paidAmount: receivedAmount,
          changeAmount: changeAmount > 0 ? changeAmount : 0,
        ),
        context: context,
        module: 'sales',
      );
      if (retry == null) return;
      saleId = retry;
    } catch (e, st) {
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        module: 'sales',
      );
      return;
    }

    if (!isLayaway) {
      _applyStockAdjustments(itemsPayload);
    }

    // ✅ LIMPIEZA INMEDIATA (UX): cerrar/limpiar detalles sin esperar impresión/descarga/DB.
    if (!mounted) return;
    setState(() {
      if (cartIndexToRemove >= 0 && cartIndexToRemove < _carts.length) {
        _carts[cartIndexToRemove].isCompleted = true;
        _carts.removeAt(cartIndexToRemove);
      }

      if (_carts.isNotEmpty) {
        _currentCartIndex = 0;
      } else {
        final cart = _Cart(name: 'Ticket 1');
        _applySalesDefaultsToCart(cart);
        _carts.add(cart);
        _currentCartIndex = 0;
      }
      _selectedCartItemIndex = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✔ Venta completada correctamente',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        backgroundColor: status.success,
        duration: Duration(seconds: 2),
      ),
    );

    unawaited(_deleteTempCartFromDatabase(tempCartIdToDelete));
    if (shouldPrint || shouldDownloadInvoicePdf) {
      unawaited(
        _runSaleOutputs(
          saleId: saleId,
          shouldPrint: shouldPrint,
          shouldDownloadInvoicePdf: shouldDownloadInvoicePdf,
          isLayaway: isLayaway,
          receivedAmount: receivedAmount,
        ),
      );
    }
  }

  Future<void> _downloadInvoiceLetterPdf(
    legacy_sales.SaleModel sale,
    List<legacy_sales.SaleItemModel> items,
  ) async {
    final business = ref.read(businessSettingsProvider);
    final cashierName = await SessionManager.displayName() ?? 'Cajero';
    final bytes = await InvoiceLetterPdf.generate(
      sale: sale,
      items: items,
      business: business,
      brandColorArgb: scheme.primary.value,
      cashierName: cashierName,
    );

    final clientName = (sale.customerNameSnapshot ?? '').trim();
    if (clientName.isEmpty) {
      throw Exception(
        'Debe seleccionar/configurar un cliente antes de descargar',
      );
    }

    final downloadsDir = await _getBestDownloadDirectory();
    final safeClient = _sanitizeFilenamePart(clientName);
    final safeCode = _sanitizeFilenamePart(sale.localCode);
    final filename = 'FACTURA_${safeClient}_$safeCode.pdf';
    final file = File('${downloadsDir.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes, flush: true);

    debugPrint('Factura descargada: ${file.path}');

    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Factura descargada'),
        duration: Duration(milliseconds: 900),
      ),
    );
  }

  Future<Directory> _getBestDownloadDirectory() async {
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return downloads;
    return getApplicationDocumentsDirectory();
  }

  String _sanitizeFilenamePart(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'CLIENTE';
    final noBadChars = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final collapsedSpaces = noBadChars.replaceAll(RegExp(r'\s+'), ' ');
    return collapsedSpaces;
  }

  Future<void> _saveAsQuote() async {
    final canQuote = await _authorizeAction(
      AppActions.createQuote,
      resourceType: 'quote',
      resourceId: _currentCart.ticketId?.toString(),
    );
    if (!canQuote) return;

    final result = await _presentDialog<QuoteDialogResult>(
      builder: (context) => QuoteDialog(
        items: _currentCart.items,
        selectedClient: _currentCart.selectedClient,
        itbisEnabled: _currentCart.itbisEnabled,
        itbisRate: _currentCart.itbisRate,
        discountTotal:
            _currentCart.discount + _currentCart.calculateTotalDiscount(),
        ticketName: _currentCart.name,
      ),
    );

    if (!mounted || result?.saved != true || !result!.clearCart) return;

    // Eliminar carrito temporal si existe
    await _deleteCurrentCartFromDatabase();

    if (!mounted) return;
    setState(() {
      _currentCart.clear();
      _selectedCartItemIndex = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cotización guardada'),
        backgroundColor: status.success,
      ),
    );
  }

  @override
  void dispose() {
    RawKeyboard.instance.removeListener(_handleScannerKey);
    HardwareKeyboard.instance.removeHandler(_globalShortcutHandler);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _clientFocusNode.dispose();
    _ticketItemsScrollController.dispose();
    _scanner?.dispose();
    _cartPersistenceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loggedFirstBuild) {
      _loggedFirstBuild = true;
      debugPrint(
        '[SALES] sales-first-build t=${DateTime.now().toIso8601String()}',
      );
    }
    final cashSessionState = ref.watch(cashSessionControllerProvider);
    final currentSessionId = cashSessionState.valueOrNull?.id;
    final cashIsOpen = currentSessionId != null;

    if (_previousCashOpen == null) {
      _previousCashOpen = cashIsOpen;
    } else if (_previousCashOpen == true && !cashIsOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Caja cerrada automáticamente. Abre caja para continuar.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 3),
          ),
        );
      });
    }
    _previousCashOpen = cashIsOpen;

    // Atajos opcionales que dependen de la preferencia de teclado.
    final Map<LogicalKeySet, Intent> optionalShortcuts =
        _keyboardShortcutsEnabled
        ? {
            LogicalKeySet(LogicalKeyboardKey.f2): const OpenManualSaleIntent(),
            LogicalKeySet(LogicalKeyboardKey.f3):
                const FocusSearchClientIntent(),
            LogicalKeySet(LogicalKeyboardKey.f4):
                const OpenTicketSelectorIntent(),
            LogicalKeySet(LogicalKeyboardKey.f7): const ApplyDiscountIntent(),
            LogicalKeySet(LogicalKeyboardKey.slash): const OpenPaymentIntent(),
            LogicalKeySet(LogicalKeyboardKey.numpadDivide):
                const OpenPaymentIntent(),
            LogicalKeySet(LogicalKeyboardKey.f8): const OpenPaymentIntent(),
            LogicalKeySet(
              LogicalKeyboardKey.control,
              LogicalKeyboardKey.backspace,
            ): const DeleteSelectedItemIntent(),
            LogicalKeySet(LogicalKeyboardKey.add):
                const IncreaseQuantityIntent(),
            LogicalKeySet(LogicalKeyboardKey.equal, LogicalKeyboardKey.shift):
                const IncreaseQuantityIntent(),
            LogicalKeySet(LogicalKeyboardKey.minus):
                const DecreaseQuantityIntent(),
          }
        : const {};

    return Shortcuts(
      shortcuts: optionalShortcuts,
      child: Actions(
        actions: {
          FocusSearchProductIntent: CallbackAction<FocusSearchProductIntent>(
            onInvoke: (_) {
              _searchFocusNode.requestFocus();
              return null;
            },
          ),
          FocusSearchClientIntent: CallbackAction<FocusSearchClientIntent>(
            onInvoke: (_) {
              _showClientPicker();
              return null;
            },
          ),
          NewClientIntent: CallbackAction<NewClientIntent>(
            onInvoke: (_) async {
              final result = await _presentDialog<ClientModel>(
                builder: (context) => const ClientFormDialog(),
              );
              if (!mounted || result == null) return null;
              setState(() {
                _clients.add(result);
              });
              _updateCurrentCart(() {
                _currentCart.selectedClient = result;
              });
              return null;
            },
          ),
          OpenManualSaleIntent: CallbackAction<OpenManualSaleIntent>(
            onInvoke: (_) {
              _showQuickItemDialog();
              return null;
            },
          ),
          OpenTicketSelectorIntent: CallbackAction<OpenTicketSelectorIntent>(
            onInvoke: (_) {
              _showTicketSelector();
              return null;
            },
          ),
          ApplyDiscountIntent: CallbackAction<ApplyDiscountIntent>(
            onInvoke: (_) {
              if (_selectedCartItemIndex != null &&
                  _selectedCartItemIndex! < _currentCart.items.length) {
                _showEditItemDialog(
                  _currentCart.items[_selectedCartItemIndex!],
                  _selectedCartItemIndex!,
                );
              }
              return null;
            },
          ),
          OpenPaymentIntent: CallbackAction<OpenPaymentIntent>(
            onInvoke: (_) {
              if (_currentCart.items.isNotEmpty) {
                _processPayment(SaleKind.invoice, initialPrintTicket: true);
              }
              return null;
            },
          ),
          OpenPaymentAndPrintIntent: CallbackAction<OpenPaymentAndPrintIntent>(
            onInvoke: (_) {
              if (_currentCart.items.isNotEmpty) {
                _processPayment(SaleKind.invoice, initialPrintTicket: true);
              }
              return null;
            },
          ),
          FinalizeSaleIntent: CallbackAction<FinalizeSaleIntent>(
            onInvoke: (_) {
              if (_currentCart.items.isNotEmpty) {
                _processPayment(SaleKind.invoice, initialPrintTicket: false);
              }
              return null;
            },
          ),
          DeleteSelectedItemIntent: CallbackAction<DeleteSelectedItemIntent>(
            onInvoke: (_) {
              if (_selectedCartItemIndex != null &&
                  _selectedCartItemIndex! < _currentCart.items.length) {
                _updateCurrentCart(() {
                  _currentCart.removeItem(_selectedCartItemIndex!);
                  _selectedCartItemIndex = null;
                });
              }
              return null;
            },
          ),
          IncreaseQuantityIntent: CallbackAction<IncreaseQuantityIntent>(
            onInvoke: (_) {
              if (_selectedCartItemIndex != null &&
                  _selectedCartItemIndex! < _currentCart.items.length) {
                setState(() {
                  final item = _currentCart.items[_selectedCartItemIndex!];
                  _currentCart.updateQuantity(
                    _selectedCartItemIndex!,
                    item.qty + 1,
                  );
                });
              }
              return null;
            },
          ),
          DecreaseQuantityIntent: CallbackAction<DecreaseQuantityIntent>(
            onInvoke: (_) {
              if (_selectedCartItemIndex != null &&
                  _selectedCartItemIndex! < _currentCart.items.length) {
                setState(() {
                  final item = _currentCart.items[_selectedCartItemIndex!];
                  if (item.qty > 1) {
                    _currentCart.updateQuantity(
                      _selectedCartItemIndex!,
                      item.qty - 1,
                    );
                  }
                });
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: LayoutBuilder(
              builder: (context, outerConstraints) {
                Widget buildSalesLayout(BoxConstraints constraints) {
                  final ticketPanelConstraints = _ticketPanelConstraints(
                    constraints.maxWidth,
                  );
                  final panelMargin = constraints.maxWidth < 1150 ? 8.0 : 10.0;
                  final scheme = Theme.of(context).colorScheme;
                  final gradientTheme = Theme.of(
                    context,
                  ).extension<AppGradientTheme>();
                  final backgroundGradient = _resolveBackgroundGradient(
                    gradientTheme,
                  );

                  return Stack(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    12,
                                    6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: backgroundGradient,
                                  ),
                                  child: _build3DControlBar(),
                                ),
                                Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.only(top: 4),
                                    decoration: BoxDecoration(
                                      gradient: backgroundGradient,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Theme.of(
                                            context,
                                          ).shadowColor.withOpacity(0.25),
                                          blurRadius: 16,
                                          offset: const Offset(0, 8),
                                        ),
                                        BoxShadow(
                                          color: scheme.primary.withOpacity(
                                            0.08,
                                          ),
                                          blurRadius: 10,
                                          offset: const Offset(-2, -2),
                                          spreadRadius: -1,
                                        ),
                                      ],
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: _isSearching
                                              ? const BrandedLoadingView(
                                                  fullScreen: false,
                                                  message:
                                                      'Cargando datos de ventas...',
                                                )
                                              : (() {
                                                  final products =
                                                      _filteredProducts();
                                                  if (products.isEmpty) {
                                                    return Center(
                                                      child: Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          Icon(
                                                            Icons
                                                                .inventory_2_outlined,
                                                            size: 80,
                                                            color: scheme
                                                                .onSurface
                                                                .withOpacity(
                                                                  0.3,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            height: 16,
                                                          ),
                                                          Text(
                                                            'No hay productos disponibles',
                                                            style: TextStyle(
                                                              color: scheme
                                                                  .onSurface
                                                                  .withOpacity(
                                                                    0.6,
                                                                  ),
                                                              fontSize: 18,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            height: 8,
                                                          ),
                                                          Text(
                                                            'Intenta buscar con otro término',
                                                            style: TextStyle(
                                                              color: scheme
                                                                  .onSurface
                                                                  .withOpacity(
                                                                    0.4,
                                                                  ),
                                                              fontSize: 14,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }
                                                  return Builder(
                                                    builder: (context) {
                                                      final productsTheme =
                                                          Theme.of(context)
                                                              .extension<
                                                                SalesProductsTheme
                                                              >();
                                                      final gridBg = productsTheme
                                                          ?.gridBackgroundColor;
                                                      final resolvedGridBg =
                                                          (gridBg == null ||
                                                              gridBg.opacity ==
                                                                  0)
                                                          ? Colors.transparent
                                                          : gridBg;

                                                      return Container(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              left: 12,
                                                              right: 12,
                                                              top: 8,
                                                              bottom: 72,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: resolvedGridBg,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                16,
                                                              ),
                                                        ),
                                                        child: LayoutBuilder(
                                                          builder: (context, constraints) {
                                                            final cardSize =
                                                                _productCardSizeFor(
                                                                  constraints
                                                                      .maxWidth,
                                                                );
                                                            double
                                                            maxExtent = stableMaxCrossAxisExtent(
                                                              availableWidth:
                                                                  constraints
                                                                      .maxWidth,
                                                              desiredMaxExtent:
                                                                  _productTileMaxExtent,
                                                              spacing:
                                                                  _gridSpacing,
                                                              minExtent:
                                                                  _productTileMaxExtent,
                                                            );
                                                            if (!maxExtent
                                                                    .isFinite ||
                                                                maxExtent <=
                                                                    0) {
                                                              maxExtent =
                                                                  _productTileMaxExtent;
                                                            }
                                                            return GridView.builder(
                                                              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                                                maxCrossAxisExtent:
                                                                    maxExtent,
                                                                mainAxisExtent:
                                                                    cardSize *
                                                                    1.35,
                                                                crossAxisSpacing:
                                                                    _gridSpacing,
                                                                mainAxisSpacing:
                                                                    _gridSpacing,
                                                              ),
                                                              itemCount:
                                                                  products
                                                                      .length,
                                                              itemBuilder: (context, index) {
                                                                final product =
                                                                    products[index];
                                                                return Center(
                                                                  child: SizedBox(
                                                                    width:
                                                                        cardSize,
                                                                    height:
                                                                        cardSize *
                                                                        1.15,
                                                                    child: _buildProductCard(
                                                                      product,
                                                                      index:
                                                                          index,
                                                                    ),
                                                                  ),
                                                                );
                                                              },
                                                            );
                                                          },
                                                        ),
                                                      );
                                                    },
                                                  );
                                                })(),
                                        ),
                                        Positioned(
                                          bottom: 0,
                                          left: 0,
                                          right: 0,
                                          child: _buildTicketsFooter(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const VerticalDivider(width: 1, thickness: 1),
                          ConstrainedBox(
                            constraints: ticketPanelConstraints,
                            child: Container(
                              margin: EdgeInsets.all(panelMargin),
                              decoration: BoxDecoration(
                                gradient: backgroundGradient,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Theme.of(
                                      context,
                                    ).shadowColor.withOpacity(0.25),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                    spreadRadius: 0,
                                  ),
                                  BoxShadow(
                                    color: scheme.primary.withOpacity(0.12),
                                    blurRadius: 10,
                                    offset: const Offset(-2, -2),
                                    spreadRadius: -1,
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _buildTicketPanel(),
                            ),
                          ),
                        ],
                      ),
                      if (!cashIsOpen) _buildCashClosedOverlay(),
                    ],
                  );
                }

                // Mantener diseño de dos columnas pero con uso completo del espacio.
                return SizedBox.expand(
                  child: buildSalesLayout(outerConstraints),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCashClosedOverlay() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Positioned.fill(
      child: Container(
        color: theme.shadowColor.withOpacity(0.7),
        child: Center(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: scheme.secondary.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(0.5),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.secondary.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.point_of_sale,
                    size: 48,
                    color: scheme.secondary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'CAJA CERRADA',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Debe abrir la caja para iniciar el turno\ny poder realizar ventas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onSurface.withOpacity(0.45),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result = await CashOpenDialog.show(context);
                      if (result == true) await _refreshCashSession();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.secondary,
                      foregroundColor: scheme.onSecondary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.lock_open, size: 20),
                    label: const Text(
                      'ABRIR CAJA',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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

  Widget _buildProductCard(ProductModel product, {required int index}) {
    final qtyInCart = _currentCart.getQuantityForProduct(product.id ?? -1);
    final effectiveStock = product.stock - qtyInCart;
    final isLowStock = effectiveStock > 0 && effectiveStock <= 10;
    final isOutOfStock = effectiveStock <= 0;
    final stockColor = isOutOfStock
        ? scheme.error
        : (isLowStock ? status.warning : scheme.primary.withOpacity(0.85));
    final theme = Theme.of(context);
    final productsTheme = theme.extension<SalesProductsTheme>();
    final isAlt = index.isOdd;

    Color resolve(Color? c, Color fallback) {
      if (c == null) return fallback;
      return c.opacity == 0 ? fallback : c;
    }

    final cardBg = resolve(
      isAlt
          ? productsTheme?.cardAltBackgroundColor
          : productsTheme?.cardBackgroundColor,
      scheme.surface,
    );
    final cardBorder = resolve(
      isAlt
          ? productsTheme?.cardAltBorderColor
          : productsTheme?.cardBorderColor,
      scheme.onSurface.withOpacity(0.10),
    );
    final cardText = resolve(
      isAlt ? productsTheme?.cardAltTextColor : productsTheme?.cardTextColor,
      scheme.onSurface,
    );
    final readableCardText = ColorUtils.ensureReadableColor(cardText, cardBg);
    final priceColor = resolve(productsTheme?.priceColor, scheme.primary);

    final nameOverlayBg = scheme.onSurface.withOpacity(0.70);
    final nameOverlayText = ColorUtils.ensureReadableColor(
      scheme.surface,
      nameOverlayBg,
    );

    final rawPrice = product.salePrice;
    final formattedPrice = (rawPrice % 1 == 0)
        ? rawPrice.toStringAsFixed(0)
        : rawPrice.toStringAsFixed(2);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: cardBg,
        border: Border.all(color: cardBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: theme.shadowColor.withOpacity(0.12),
            blurRadius: 12,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          color: transparent,
          child: InkWell(
            onTap: isOutOfStock ? null : () => _addProductToCart(product),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Imagen del producto más compacta
                Expanded(
                  flex: 4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ProductThumbnail.fromProduct(
                        product,
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: BorderRadius.circular(12),
                        showBorder: false,
                      ),
                      // Nombre flotante sobre la imagen
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, nameOverlayBg],
                              stops: const [0.0, 1.0],
                            ),
                          ),
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(
                              product.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.0,
                                fontWeight: FontWeight.w600,
                                height: 1.05,
                                color: nameOverlayText,
                                letterSpacing: 0.1,
                                shadows: [
                                  Shadow(
                                    color: Theme.of(
                                      context,
                                    ).shadowColor.withOpacity(0.35),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Badge de código en esquina superior derecha
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            // Contraste garantizado: fondo ≈ onSurface, texto ≈ surface.
                            // Evita casos donde el tema deja fondo y texto casi iguales.
                            color: scheme.onSurface.withOpacity(0.78),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: scheme.surface.withOpacity(0.24),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            product.code.toUpperCase(),
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'monospace',
                              color: ColorUtils.ensureReadableColor(
                                scheme.surface,
                                scheme.onSurface,
                              ),
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                      // Badge de cantidad en carrito
                      if (qtyInCart > 0)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.secondary,
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(
                                    context,
                                  ).shadowColor.withOpacity(0.2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shopping_cart,
                                  size: 10,
                                  color: scheme.onSecondary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  qtyInCart.toInt().toString(),
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: scheme.onSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Información del producto
                Expanded(
                  flex: 2,
                  child: Container(
                    // Slightly tighter padding to avoid RenderFlex overflow on
                    // small tile heights (e.g. 144px).
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Precio y Stock en fila
                        Flexible(
                          fit: FlexFit.loose,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Precio
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'PRECIO',
                                      style: TextStyle(
                                        fontSize: 6.5,
                                        fontWeight: FontWeight.w600,
                                        color: readableCardText.withOpacity(
                                          0.62,
                                        ),
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        '\$$formattedPrice',
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w900,
                                          color: priceColor,
                                          height: 1.0,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              // Stock badge (se adapta para no overflow)
                              Flexible(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: stockColor,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isOutOfStock
                                                ? Icons.remove_circle_outline
                                                : Icons.inventory_2,
                                            size: 11,
                                            color: readableOn(stockColor),
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            isOutOfStock
                                                ? 'Agot.'
                                                : '${effectiveStock.toInt()}',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w800,
                                              color: readableOn(stockColor),
                                              height: 1.0,
                                            ),
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
                      ],
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

  Widget _buildCategoryDropdown() {
    final salesTheme = Theme.of(context).extension<SalesPageTheme>();

    Color resolve(Color? c, Color fallback) {
      if (c == null || c.opacity == 0) return fallback;
      return c;
    }

    final allOption = 'Todas';
    final items = [allOption, ..._categories.map((c) => c.name)];
    final dropdownBg = resolve(
      salesTheme?.controlBarDropdownBackgroundColor,
      transparent,
    );
    final dropdownBorder = resolve(
      salesTheme?.controlBarDropdownBorderColor,
      scheme.onSurface.withOpacity(0.2),
    );
    final dropdownText = resolve(
      salesTheme?.controlBarDropdownTextColor,
      scheme.primary,
    );
    final menuBg = resolve(
      salesTheme?.controlBarPopupBackgroundColor,
      scheme.surface,
    );
    final menuText = resolve(
      salesTheme?.controlBarPopupTextColor,
      scheme.onSurface,
    );
    final menuSelectedBg = resolve(
      salesTheme?.controlBarPopupSelectedBackgroundColor,
      scheme.primary.withOpacity(0.14),
    );
    final menuSelectedText = resolve(
      salesTheme?.controlBarPopupSelectedTextColor,
      scheme.primary,
    );
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: PopupMenuButton<String>(
        tooltip: 'Elegir categoría',
        offset: const Offset(0, 42),
        color: menuBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        initialValue: _selectedCategory ?? allOption,
        onSelected: (value) =>
            _onCategorySelected(value == allOption ? null : value),
        itemBuilder: (context) => items
            .map(
              (name) => PopupMenuItem<String>(
                value: name,
                child: Builder(
                  builder: (context) {
                    final isSelected = (_selectedCategory ?? allOption) == name;
                    final iconColor = isSelected
                        ? menuSelectedText
                        : menuText.withOpacity(0.75);
                    final textColor = isSelected
                        ? menuSelectedText
                        : menuText.withOpacity(0.92);

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? menuSelectedBg : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            name == allOption
                                ? Icons.filter_alt_off_outlined
                                : Icons.category_outlined,
                            size: 18,
                            color: iconColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            name,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            )
            .toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: dropdownBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: dropdownBorder, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_list, size: 18, color: dropdownText),
              const SizedBox(width: 6),
              Text(
                _selectedCategory ?? 'Categoría',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: dropdownText,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: dropdownText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _build3DControlBar() {
    final gradientTheme = Theme.of(context).extension<AppGradientTheme>();
    final backgroundGradient = _resolveBackgroundGradient(gradientTheme);
    final salesTheme = Theme.of(context).extension<SalesPageTheme>();

    Color resolve(Color? c, Color fallback) {
      if (c == null || c.opacity == 0) return fallback;
      return c;
    }

    final tokens =
        Theme.of(context).extension<AppTokens>() ?? AppTokens.defaultTokens;
    final controlText = resolve(
      salesTheme?.controlBarTextColor,
      tokens.controlBarText,
    );
    final controlBorder = resolve(
      salesTheme?.controlBarBorderColor,
      tokens.controlBarBorder,
    );
    final controlContentBg = resolve(
      salesTheme?.controlBarContentBackgroundColor,
      tokens.searchFieldBackground,
    );
    final controlBarBg = salesTheme?.controlBarBackgroundColor;
    final hasCustomBarBg = controlBarBg != null && controlBarBg.opacity != 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < 980;

        // Colores acorde al tema (tokens) y ajustados por contraste.
        // Evita que se “quede fijo en negro” cuando cambia el tema.
        final fieldTextColor = ColorUtils.ensureReadableColor(
          tokens.searchFieldText,
          controlContentBg,
        );

        final hintCandidate = tokens.searchFieldText.withOpacity(0.62);
        var hintColor = ColorUtils.ensureReadableColor(
          hintCandidate,
          controlContentBg,
          minRatio: 3.0,
        );
        if (hintColor == Colors.black || hintColor == Colors.white) {
          hintColor = hintColor.withOpacity(0.65);
        }

        final iconColor = ColorUtils.ensureReadableColor(
          tokens.searchFieldIcon,
          controlContentBg,
          minRatio: 3.0,
        ).withOpacity(0.9);

        // En pantallas amplias, el buscador debe verse más estrecho (≈95%)
        // para un layout más elegante. En compacto se mantiene al 100%
        // para no romper la usabilidad.
        final searchBarWidth = isCompact ? double.infinity : (width * 0.95);

        final outerPadding = EdgeInsets.all((width * 0.006).clamp(3.0, 6.0));
        final barHeight = isCompact ? 40.0 : 44.0;
        final radius = isCompact ? 14.0 : 16.0;
        final iconSize = isCompact ? 18.0 : 20.0;
        final textSize = isCompact ? 12.5 : 13.0;
        final fieldVPad = isCompact ? 11.0 : 12.0;

        IconButton compactIconButton({
          required IconData icon,
          required VoidCallback onPressed,
          required String tooltip,
          Color? color,
        }) {
          return IconButton(
            onPressed: onPressed,
            tooltip: tooltip,
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tightFor(
              width: barHeight,
              height: barHeight,
            ),
            icon: Icon(
              icon,
              size: iconSize,
              color: color ?? controlText.withOpacity(0.8),
            ),
          );
        }

        return Container(
          padding: outerPadding,
          decoration: BoxDecoration(
            color: hasCustomBarBg ? controlBarBg : null,
            gradient: hasCustomBarBg ? null : backgroundGradient,
            borderRadius: BorderRadius.circular(radius),
            border:
                (salesTheme?.controlBarBorderColor != null &&
                    salesTheme!.controlBarBorderColor.opacity != 0)
                ? Border.all(color: controlBorder, width: 1)
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: searchBarWidth),
                    child: Container(
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: controlContentBg,
                        borderRadius: BorderRadius.circular(
                          isCompact ? 12 : 14,
                        ),
                        border: Border.all(color: controlBorder, width: 1),
                      ),
                      child: Row(
                        children: [
                          SizedBox(width: isCompact ? 10 : 12),
                          Icon(Icons.search, color: iconColor, size: iconSize),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              decoration: InputDecoration(
                                // Evita que el InputDecorationTheme global
                                // pinte un fondo blanco encima de nuestro
                                // contenedor (lo que hacía el texto “blanco
                                // sobre blanco” en algunos temas).
                                filled: true,
                                fillColor: Colors.transparent,
                                hintText:
                                    'Buscar artículo por nombre o código…',
                                hintStyle: TextStyle(
                                  color: hintColor,
                                  fontSize: textSize,
                                ),
                                border: InputBorder.none,
                                isCollapsed: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: isCompact ? 10 : 12,
                                  vertical: fieldVPad,
                                ),
                              ),
                              onChanged: _searchProducts,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (value) async {
                                final q = value.trim();
                                if (q.isEmpty) return;
                                // Si hay espacios, normalmente es búsqueda por nombre.
                                if (q.contains(' ')) return;
                                await _handleBarcodeScan(
                                  q,
                                  clearSearchField: true,
                                );
                              },
                              style: TextStyle(
                                color: fieldTextColor,
                                fontSize: textSize,
                              ),
                            ),
                          ),
                          _buildCategoryDropdown(),
                          compactIconButton(
                            icon: Icons.filter_list,
                            color: _productFilter.hasActiveFilters
                                ? status.warning
                                : controlText,
                            onPressed: _openFilterDialog,
                            tooltip: 'Filtros avanzados',
                          ),
                          SizedBox(width: isCompact ? 4 : 6),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompactOperationButton({
    required IconData icon,
    required String label,
    required Color color,
    Color? foregroundColor,
    Color? borderColor,
    required VoidCallback onPressed,
  }) {
    final contrastColor = foregroundColor ?? ColorUtils.foregroundFor(color);

    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: contrastColor),
      label: Text(
        label,
        style: TextStyle(
          color: contrastColor,
          fontSize: 14.0,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: contrastColor,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 2,
        shadowColor: Theme.of(context).shadowColor.withOpacity(0.20),
        minimumSize: const Size(0, 44),
      ),
    );
  }

  Widget _buildTicketsFooter() {
    final gradientTheme = Theme.of(context).extension<AppGradientTheme>();
    final backgroundGradient = _resolveBackgroundGradient(gradientTheme);
    final salesTheme = Theme.of(context).extension<SalesPageTheme>();
    final shadowColor = Theme.of(context).shadowColor;

    Color ensureDarkButtonBg(Color c) {
      final hsl = HSLColor.fromColor(c);
      if (hsl.lightness <= 0.28) return c;
      return hsl.withLightness(0.26).toColor();
    }

    Color resolve(Color? c, Color fallback) {
      if (c == null || c.opacity == 0) return fallback;
      return c;
    }

    final baseButtonColor = resolve(
      salesTheme?.footerButtonsBackgroundColor,
      const Color(0xFF0D2B57),
    );
    final unifiedColor = ensureDarkButtonBg(baseButtonColor);
    final unifiedTextColor = resolve(
      salesTheme?.footerButtonsTextColor,
      Colors.white.withOpacity(0.96),
    );
    final unifiedBorderColor =
        salesTheme?.footerButtonsBorderColor ?? Colors.white.withOpacity(0.18);
    return Container(
      height: _ticketsFooterHeight,
      decoration: BoxDecoration(
        gradient: backgroundGradient,
        boxShadow: [
          BoxShadow(
            color: shadowColor.withOpacity(0.54),
            blurRadius: 14,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 520;
            final compactColor = ensureDarkButtonBg(
              resolve(salesTheme?.footerButtonsBackgroundColor, unifiedColor),
            );
            final compactText = resolve(
              salesTheme?.footerButtonsTextColor,
              Colors.white.withOpacity(0.96),
            );

            if (isNarrow) {
              // Mostrar botones compactos flotando también en pantallas pequeñas
              return Row(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildCompactOperationButton(
                          icon: Icons.add_circle_outline,
                          label: 'Entrada',
                          color: compactColor,
                          foregroundColor: compactText,
                          borderColor: unifiedBorderColor,
                          onPressed: () =>
                              _openCashMovement(CashMovementType.income),
                        ),
                        const SizedBox(width: 10),
                        _buildCompactOperationButton(
                          icon: Icons.remove_circle_outline,
                          label: 'Retiro',
                          color: compactColor,
                          foregroundColor: compactText,
                          borderColor: unifiedBorderColor,
                          onPressed: () =>
                              _openCashMovement(CashMovementType.outcome),
                        ),
                        const SizedBox(width: 14),
                        Container(
                          width: 1,
                          height: 28,
                          color: unifiedBorderColor.withOpacity(0.35),
                        ),
                        const SizedBox(width: 14),
                        _buildCompactOperationButton(
                          icon: Icons.account_balance,
                          label: 'Créditos',
                          color: compactColor,
                          foregroundColor: compactText,
                          borderColor: unifiedBorderColor,
                          onPressed: () {
                            AuthzService.guardedAction(
                              context,
                              authz_perm.Permissions.creditsView,
                              () => context.go('/credits-list'),
                              reason: 'Abrir creditos',
                              resourceType: 'route',
                              resourceId: '/credits-list',
                            )();
                          },
                        ),
                        const SizedBox(width: 10),
                        _buildCompactOperationButton(
                          icon: Icons.request_quote_outlined,
                          label: 'Cotizaciones',
                          color: compactColor,
                          foregroundColor: compactText,
                          borderColor: unifiedBorderColor,
                          onPressed: () {
                            AuthzService.guardedAction(
                              context,
                              authz_perm.Permissions.quotesView,
                              () => context.go('/quotes-list'),
                              reason: 'Abrir cotizaciones',
                              resourceType: 'route',
                              resourceId: '/quotes-list',
                            )();
                          },
                        ),
                        const SizedBox(width: 10),
                        _buildCompactOperationButton(
                          icon: Icons.assignment_return_outlined,
                          label: 'Devoluciones',
                          color: compactColor,
                          foregroundColor: compactText,
                          borderColor: unifiedBorderColor,
                          onPressed: () {
                            AuthzService.guardedAction(
                              context,
                              authz_perm.Permissions.returnsView,
                              () => context.go('/returns-list'),
                              reason: 'Abrir devoluciones',
                              resourceType: 'route',
                              resourceId: '/returns-list',
                            )();
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            // En pantallas amplias usamos botones compactos, alineados a la derecha
            return Row(
              children: [
                _buildCompactOperationButton(
                  icon: Icons.add_circle_outline,
                  label: 'Entrada',
                  color: unifiedColor,
                  foregroundColor: unifiedTextColor,
                  borderColor: unifiedBorderColor,
                  onPressed: () => _openCashMovement(CashMovementType.income),
                ),
                SizedBox(width: 10),
                _buildCompactOperationButton(
                  icon: Icons.remove_circle_outline,
                  label: 'Retiro',
                  color: unifiedColor,
                  foregroundColor: unifiedTextColor,
                  borderColor: unifiedBorderColor,
                  onPressed: () => _openCashMovement(CashMovementType.outcome),
                ),
                SizedBox(width: 14),
                Container(
                  width: 1,
                  height: 28,
                  color: unifiedBorderColor.withOpacity(0.35),
                ),
                SizedBox(width: 14),
                const Spacer(),
                _buildCompactOperationButton(
                  icon: Icons.account_balance,
                  label: 'Créditos',
                  color: unifiedColor,
                  foregroundColor: unifiedTextColor,
                  borderColor: unifiedBorderColor,
                  onPressed: () {
                    AuthzService.guardedAction(
                      context,
                      authz_perm.Permissions.creditsView,
                      () => context.go('/credits-list'),
                      reason: 'Abrir creditos',
                      resourceType: 'route',
                      resourceId: '/credits-list',
                    )();
                  },
                ),
                SizedBox(width: 10),
                _buildCompactOperationButton(
                  icon: Icons.request_quote_outlined,
                  label: 'Cotizaciones',
                  color: unifiedColor,
                  foregroundColor: unifiedTextColor,
                  borderColor: unifiedBorderColor,
                  onPressed: () {
                    AuthzService.guardedAction(
                      context,
                      authz_perm.Permissions.quotesView,
                      () => context.go('/quotes-list'),
                      reason: 'Abrir cotizaciones',
                      resourceType: 'route',
                      resourceId: '/quotes-list',
                    )();
                  },
                ),
                SizedBox(width: 10),
                _buildCompactOperationButton(
                  icon: Icons.assignment_return_outlined,
                  label: 'Devoluciones',
                  color: unifiedColor,
                  foregroundColor: unifiedTextColor,
                  borderColor: unifiedBorderColor,
                  onPressed: () {
                    AuthzService.guardedAction(
                      context,
                      authz_perm.Permissions.returnsView,
                      () => context.go('/returns-list'),
                      reason: 'Abrir devoluciones',
                      resourceType: 'route',
                      resourceId: '/returns-list',
                    )();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Panel de ticket refactorizado con 3 cards profesionales
  Widget _buildTicketPanel() {
    final gradientTheme = Theme.of(
      context,
    ).extension<SalesDetailGradientTheme>();
    final panelGradient = _resolveSalesDetailGradient(gradientTheme);

    return LayoutBuilder(
      builder: (context, constraints) {
        // En alturas pequeñas, el diseño "sticky" (con Expanded interno)
        // puede causar overflow. En ese caso hacemos el panel completo
        // scrolleable.
        final isShort =
            constraints.maxHeight.isFinite && constraints.maxHeight < 560;

        final content = !isShort
            ? Column(
                children: [
                  // CARD A: Ticket / Cliente
                  _buildTicketHeaderCard(),
                  const SizedBox(height: 8),

                  // CARD B: Lista de items (scrollable)
                  Expanded(child: _buildItemsListCard()),
                  const SizedBox(height: 8),

                  // CARD C: Resumen + Total + Acciones (sticky)
                  _buildTotalAndActionsCard(),
                ],
              )
            : SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _buildTicketHeaderCard(),
                    const SizedBox(height: 8),
                    _buildItemsListCard(embedded: true),
                    const SizedBox(height: 8),
                    _buildTotalAndActionsCard(),
                  ],
                ),
              );

        // Requisito: la columna (contenedor) de detalle debe ser azul.
        return Container(
          decoration: BoxDecoration(gradient: panelGradient),
          child: content,
        );
      },
    );
  }

  /// CARD A: Ticket / Cliente
  Widget _buildTicketHeaderCard() {
    final totalTickets = _carts.length;
    final itemCount = _currentCart.items.length;
    final gradientTheme = Theme.of(
      context,
    ).extension<SalesDetailGradientTheme>();
    final backgroundGradient = _resolveSalesDetailGradient(gradientTheme);

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      elevation: 2,
      shadowColor: Theme.of(context).shadowColor.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.primary.withOpacity(0.12), width: 1),
      ),
      color: transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: backgroundGradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 360;

            Widget actionIcon({
              required String tooltip,
              required IconData icon,
              required VoidCallback onTap,
            }) {
              return Tooltip(
                message: tooltip,
                child: Material(
                  color: transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: salesDetailTextColor.withOpacity(0.18),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onTap,
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Icon(icon, color: salesDetailTextColor, size: 18),
                    ),
                  ),
                ),
              );
            }

            Widget itemCountPill() {
              if (itemCount <= 0) return const SizedBox.shrink();
              return Tooltip(
                message: 'Artículos en ticket',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: transparent,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: salesDetailTextColor.withOpacity(0.25),
                    ),
                  ),
                  child: Text(
                    '$itemCount',
                    style: TextStyle(
                      color: salesDetailTextColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1.0,
                    ),
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Material(
                      color: transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: salesDetailTextColor.withOpacity(0.18),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _showTicketSelector,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 18,
                                color: salesDetailTextColor,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  totalTickets == 1
                                      ? _currentCart.displayName
                                      : '${_currentCart.displayName} ($totalTickets)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: salesDetailTextColor,
                                    fontSize: isCompact ? 13 : 14,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_drop_down,
                                color: salesDetailTextColor.withOpacity(0.7),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  itemCountPill(),
                  const SizedBox(width: 8),
                  actionIcon(
                    tooltip: 'Clientes',
                    icon: Icons.group,
                    onTap: _showClientPicker,
                  ),
                  const SizedBox(width: 8),
                  actionIcon(
                    tooltip: 'Venta manual',
                    icon: Icons.edit_note,
                    onTap: _showQuickItemDialog,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// CARD B: Detalle de la venta (lista scrollable)
  Widget _buildItemsListCard({bool embedded = false}) {
    final gradientTheme = Theme.of(
      context,
    ).extension<SalesDetailGradientTheme>();
    final backgroundGradient = _resolveSalesDetailGradient(gradientTheme);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      elevation: 2,
      shadowColor: Theme.of(context).shadowColor.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.primary.withOpacity(0.12), width: 1),
      ),
      color: transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Durante el arranque/redimensionado la altura puede llegar a 0–20px.
          // Si está muy pequeña, no renderizar para evitar overflow.
          if (!embedded &&
              constraints.maxHeight > 0 &&
              constraints.maxHeight < 40) {
            return const SizedBox.shrink();
          }

          return Container(
            decoration: BoxDecoration(
              gradient: backgroundGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _currentCart.items.isEmpty
                ? _buildEmptyCartView()
                : embedded
                ? ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 8,
                    ),
                    itemCount: _currentCart.items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 0),
                    itemBuilder: (context, index) {
                      final item = _currentCart.items[index];
                      return _buildCartItemRow(item, index);
                    },
                  )
                : Scrollbar(
                    controller: _ticketItemsScrollController,
                    thumbVisibility: true,
                    child: ListView.separated(
                      controller: _ticketItemsScrollController,
                      primary: false,
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      itemCount: _currentCart.items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 0),
                      itemBuilder: (context, index) {
                        final item = _currentCart.items[index];
                        return _buildCartItemRow(item, index);
                      },
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyCartView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight > 0 && constraints.maxHeight < 120;
        final iconSize = compact ? 34.0 : 48.0;
        final titleSize = compact ? 13.0 : 15.0;
        final subtitleSize = compact ? 11.0 : 12.0;
        final gap1 = compact ? 8.0 : 12.0;
        final gap2 = compact ? 4.0 : 6.0;

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: iconSize,
                  color: salesDetailTextColor.withOpacity(0.35),
                ),
                SizedBox(height: gap1),
                Text(
                  'Ticket vacío',
                  style: TextStyle(
                    color: salesDetailTextColor.withOpacity(0.8),
                    fontSize: titleSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: gap2),
                Text(
                  'Agrega productos desde el catálogo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: salesDetailTextColor.withOpacity(0.55),
                    fontSize: subtitleSize,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCartItemRow(SaleItemModel item, int index) {
    final isSelected = _selectedCartItemIndex == index;
    final subtotal = (item.qty * item.unitPrice) - item.discountLine;
    // Requisito: líneas decorativas del detalle siempre negras.
    final rowDividerColor = Colors.black.withOpacity(0.22);

    return InkWell(
      onTap: () => setState(() => _selectedCartItemIndex = index),
      onDoubleTap: () => _showEditItemDialog(item, index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: scheme.primary.withOpacity(0.32), width: 1.5)
              : Border(bottom: BorderSide(color: rowDividerColor, width: 1)),
        ),
        child: Row(
          children: [
            // Cantidad badge
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: salesDetailTextColor.withOpacity(0.2),
                ),
              ),
              child: Center(
                child: Text(
                  '${item.qty.toInt()}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: salesDetailTextColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Nombre y código del producto
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productNameSnapshot,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: salesDetailTextColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Precio: RD\$${item.unitPrice.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 10,
                      color: salesDetailTextColor.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Controles de cantidad
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCompactStepperButton(Icons.remove, () {
                  if (item.qty > 1) {
                    _updateCurrentCart(
                      () => _currentCart.updateQuantity(index, item.qty - 1),
                    );
                  }
                }),
                const SizedBox(width: 4),
                _buildCompactStepperButton(
                  Icons.add,
                  () => _incrementCartItemQty(item, index),
                ),
              ],
            ),
            const SizedBox(width: 10),

            // Subtotal
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (item.discountLine > 0)
                  Text(
                    '-\$${item.discountLine.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 9,
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  '\$${subtotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: salesDetailTextColor.withOpacity(0.95),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),

            // Botón eliminar
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () =>
                    _updateCurrentCart(() => _currentCart.removeItem(index)),
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Center(
                    child: Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: scheme.error.withOpacity(0.85),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStepperButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: salesDetailTextColor.withOpacity(0.2),
            width: 0.5,
          ),
        ),
        child: Icon(
          icon,
          size: 14,
          color: salesDetailTextColor.withOpacity(0.8),
        ),
      ),
    );
  }

  /// CARD C: Resumen + Total + Acciones (sticky al fondo)
  Widget _buildTotalAndActionsCard() {
    final gradientTheme = Theme.of(
      context,
    ).extension<SalesDetailGradientTheme>();
    final backgroundGradient = _resolveSalesDetailGradient(gradientTheme);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Switches y opciones fiscales
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: salesDetailTextColor.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'ITBIS ${(_currentCart.itbisRate * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: salesDetailTextColor,
                              ),
                            ),
                          ),
                          Switch(
                            value: _currentCart.itbisEnabled,
                            onChanged: _currentCart.fiscalEnabled
                                ? null
                                : (value) => _updateCurrentCart(
                                    () => _currentCart.itbisEnabled = value,
                                  ),
                            activeColor: scheme.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: salesDetailTextColor.withOpacity(0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'NCF',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: salesDetailTextColor,
                              ),
                            ),
                          ),
                          Switch(
                            value: _currentCart.fiscalEnabled,
                            onChanged: (value) async {
                              if (!value) {
                                _updateCurrentCart(() {
                                  _currentCart.fiscalEnabled = false;
                                  _currentCart.selectedNcf = null;
                                });
                                return;
                              }

                              if (!_canEnableFiscalOrNotify()) return;

                              _updateCurrentCart(() {
                                _currentCart.fiscalEnabled = true;
                                _currentCart.itbisEnabled = true;
                              });

                              await _loadAvailableNcfs();
                              if (!mounted) return;

                              if (_availableNcfs.isEmpty) {
                                _updateCurrentCart(() {
                                  _currentCart.fiscalEnabled = false;
                                  _currentCart.selectedNcf = null;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'No hay NCF disponibles. Hable con Administración para agregarlo.',
                                    ),
                                    backgroundColor: scheme.error,
                                  ),
                                );
                                return;
                              }

                              _updateCurrentCart(
                                () => _currentCart.selectedNcf ??=
                                    _availableNcfs.first,
                              );
                            },
                            activeColor: scheme.secondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              if (_currentCart.fiscalEnabled) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _currentCart.selectedNcf == null
                            ? 'NCF: (no seleccionado)'
                            : 'NCF: ${_currentCart.selectedNcf!.type} - ${_currentCart.selectedNcf!.buildNcf()}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _currentCart.selectedNcf == null
                              ? scheme.error
                              : salesDetailTextColor.withOpacity(0.8),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _availableNcfs.isEmpty
                          ? null
                          : () async {
                              final selected = await _presentDialog<NcfBookModel>(
                                builder: (_) => SimpleDialog(
                                  title: const Text('Seleccionar NCF'),
                                  children: _availableNcfs
                                      .map(
                                        (ncf) => SimpleDialogOption(
                                          onPressed: () =>
                                              Navigator.of(context).pop(ncf),
                                          child: Text(
                                            '${ncf.type} - ${ncf.buildNcf()} (${ncf.toN - ncf.nextN + 1})',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                ),
                              );
                              if (!mounted || selected == null) return;
                              _updateCurrentCart(
                                () => _currentCart.selectedNcf = selected,
                              );
                            },
                      child: const Text(
                        'Cambiar',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        Divider(height: 1, color: Colors.black.withOpacity(0.22)),

        // Resumen de totales
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(gradient: backgroundGradient),
          child: Builder(
            builder: (context) {
              final grossSubtotal = _currentCart.calculateGrossSubtotal();
              final discountsCombined = _currentCart
                  .calculateTotalDiscountsCombined();
              final itbisAmount = _currentCart.itbisEnabled
                  ? _currentCart.calculateItbis()
                  : 0.0;
              final totalAmount = _currentCart.calculateTotal();

              return Column(
                children: [
                  _buildSummaryRow('Subtotal:', grossSubtotal, false),
                  if (discountsCombined > 0) ...[
                    const SizedBox(height: 4),
                    _buildSummaryRow(
                      'Descuentos:',
                      discountsCombined,
                      false,
                      color: scheme.error,
                    ),
                  ],
                  if (_currentCart.itbisEnabled) ...[
                    const SizedBox(height: 4),
                    _buildSummaryRow(
                      'ITBIS ${(_currentCart.itbisRate * 100).toInt()}%:',
                      itbisAmount,
                      false,
                    ),
                  ],
                  if (_currentCart.itbisEnabled || discountsCombined > 0) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: const Divider(thickness: 1.5, color: Colors.black),
                    ),
                  ],

                  // Total destacado
                  GestureDetector(
                    onDoubleTap: _showTotalDiscountDialog,
                    child: Tooltip(
                      message: 'Doble click para descuento',
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.secondaryContainer.withOpacity(
                            _currentCart.items.isEmpty ? 0.2 : 0.35,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: scheme.secondary.withOpacity(0.6),
                            width: 2.2,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.attach_money,
                                  size: 20,
                                  color: scheme.onSecondaryContainer,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'TOTAL:',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onSecondaryContainer,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              'RD\$${totalAmount.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: scheme.onSecondaryContainer,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        // Botones de acción
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _currentCart.items.isEmpty
                        ? null
                        : () => _processPayment(SaleKind.invoice),
                    icon: const Icon(Icons.payment, size: 22),
                    label: const Text(
                      'COBRAR (F8)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _currentCart.items.isEmpty
                          ? scheme.surface
                          : scheme.primary,
                      foregroundColor: _currentCart.items.isEmpty
                          ? scheme.onSurface
                          : scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: _currentCart.items.isEmpty ? 0 : 3,
                      shadowColor: scheme.primary.withOpacity(0.25),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 52,
                width: 132,
                child: ElevatedButton.icon(
                  onPressed: _currentCart.items.isEmpty ? null : _saveAsQuote,
                  icon: Icon(
                    Icons.description_outlined,
                    size: 18,
                    color: scheme.onSecondary,
                  ),
                  label: Text(
                    'Cotizar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: scheme.onSecondary,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    backgroundColor: _currentCart.items.isEmpty
                        ? scheme.surface
                        : scheme.secondary,
                    foregroundColor: _currentCart.items.isEmpty
                        ? scheme.onSurface
                        : scheme.onSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: _currentCart.items.isEmpty ? 0 : 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      elevation: 12,
      shadowColor: Theme.of(context).shadowColor.withOpacity(0.25),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.primary.withOpacity(0.08), width: 1),
      ),
      color: transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: backgroundGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, 10),
              spreadRadius: 1,
            ),
          ],
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 460),
          child: content,
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    double amount,
    bool isTotal, {
    Color? color,
  }) {
    final baseColor = salesDetailTextColor;
    final labelColor = color ?? baseColor.withAlpha((0.75 * 255).round());
    final valueColor = color ?? baseColor;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        Text(
          'RD\$${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  // Método legacy mantenido para compatibilidad (ya no se usa)
  // ignore: unused_element
  Widget _buildSalesSummary() {
    return Container(
      color: transparent,
      child: Column(
        children: [
          Container(
            color: scheme.surface,
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildPendingTicketsBar(),
                const SizedBox(height: 12),
                _buildClientSelector(),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showQuickItemDialog,
                    icon: const Icon(Icons.add_shopping_cart, size: 18),
                    label: const Text(
                      'Venta Rápida',
                      style: TextStyle(fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.primary,
                      side: BorderSide(color: scheme.primary),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _currentCart.items.isEmpty
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      const contentHeight = 64 + 8 + 23 + 8 + 19;
                      final topPadding =
                          ((constraints.maxHeight - contentHeight) / 2).clamp(
                            16.0,
                            120.0,
                          );

                      return ListView(
                        padding: EdgeInsets.fromLTRB(12, topPadding, 12, 16),
                        children: [
                          Center(
                            child: Icon(
                              Icons.receipt_long_outlined,
                              size: 64,
                              color: scheme.onSurface.withOpacity(0.3),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'Ticket vacío',
                              style: TextStyle(
                                color: scheme.onSurface.withOpacity(0.6),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'Agrega productos desde el catálogo',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: scheme.onSurface.withOpacity(0.45),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    itemCount: _currentCart.items.length,
                    itemBuilder: (context, index) {
                      final item = _currentCart.items[index];
                      return _buildCartItemCard(item, index);
                    },
                  ),
          ),
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).shadowColor.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  color: scheme.surface,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: scheme.outlineVariant.withOpacity(0.6),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'ITBIS ${(_currentCart.itbisRate * 100).toInt()}%',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Switch(
                              value: _currentCart.itbisEnabled,
                              onChanged: _currentCart.fiscalEnabled
                                  ? null
                                  : (value) => _updateCurrentCart(
                                      () => _currentCart.itbisEnabled = value,
                                    ),
                              activeColor: scheme.primary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: scheme.outlineVariant.withOpacity(0.6),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'NCF',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (_currentCart.fiscalEnabled)
                                    const Text(
                                      'NCF requerido',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _currentCart.fiscalEnabled,
                              onChanged: (value) async {
                                if (!value) {
                                  _updateCurrentCart(() {
                                    _currentCart.fiscalEnabled = false;
                                    _currentCart.selectedNcf = null;
                                  });
                                  return;
                                }

                                if (!_canEnableFiscalOrNotify()) return;

                                // Activar valor fiscal implica ITBIS activo
                                _updateCurrentCart(() {
                                  _currentCart.fiscalEnabled = true;
                                  _currentCart.itbisEnabled = true;
                                });

                                await _loadAvailableNcfs();
                                if (!mounted) return;

                                if (_availableNcfs.isEmpty) {
                                  _updateCurrentCart(() {
                                    _currentCart.fiscalEnabled = false;
                                    _currentCart.selectedNcf = null;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: const Text(
                                        'No hay NCF disponibles. Hable con Administración para agregarlo.',
                                      ),
                                      backgroundColor: scheme.error,
                                    ),
                                  );
                                  return;
                                }

                                // Preseleccionar el primero disponible para que quede listo
                                _updateCurrentCart(() {
                                  _currentCart.selectedNcf ??=
                                      _availableNcfs.first;
                                });
                              },
                              activeColor: scheme.secondary,
                            ),
                          ],
                        ),
                      ),
                      if (_currentCart.fiscalEnabled) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer.withOpacity(0.2),
                            border: Border.all(color: scheme.secondary),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Comprobante Fiscal (NCF)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: scheme.onSecondaryContainer,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_availableNcfs.isEmpty)
                                Text(
                                  'No hay NCF disponibles. Hable con Administración para agregarlo.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.error,
                                  ),
                                )
                              else
                                DropdownButtonFormField<NcfBookModel>(
                                  initialValue: _currentCart.selectedNcf,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                  items: _availableNcfs.map((ncf) {
                                    return DropdownMenuItem(
                                      value: ncf,
                                      child: Text(
                                        '${ncf.type} - ${ncf.buildNcf()} (${ncf.toN - ncf.nextN + 1} disponibles)',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (ncf) => _updateCurrentCart(
                                    () => _currentCart.selectedNcf = ncf,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Divider(height: 1),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: _resolveSalesDetailGradient(
                      Theme.of(context).extension<SalesDetailGradientTheme>(),
                    ),
                  ),
                  child: Builder(
                    builder: (context) {
                      final grossSubtotal = _currentCart
                          .calculateGrossSubtotal();
                      final discountsCombined = _currentCart
                          .calculateTotalDiscountsCombined();
                      final itbisAmount = _currentCart.itbisEnabled
                          ? _currentCart.calculateItbis()
                          : 0.0;
                      final totalAmount = _currentCart.calculateTotal();

                      return Column(
                        children: [
                          _buildTotalRow(
                            'Subtotal:',
                            grossSubtotal,
                            false,
                            isSubtotal: true,
                          ),
                          const SizedBox(height: 6),
                          if (discountsCombined > 0) ...[
                            _buildTotalRow(
                              'Descuentos:',
                              discountsCombined,
                              false,
                              color: scheme.error,
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (_currentCart.itbisEnabled)
                            _buildTotalRow(
                              'ITBIS ${(_currentCart.itbisRate * 100).toInt()}%:',
                              itbisAmount,
                              false,
                              isTax: true,
                            ),
                          if (_currentCart.itbisEnabled ||
                              discountsCombined > 0) ...[
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Divider(
                                thickness: 2,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                          GestureDetector(
                            onDoubleTap: _showTotalDiscountDialog,
                            child: Tooltip(
                              message: 'Doble click para aplicar descuento',
                              child: _buildTotalRow(
                                'TOTAL:',
                                totalAmount,
                                true,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _currentCart.items.isEmpty
                              ? null
                              : () => _processPayment(SaleKind.invoice),
                          icon: const Icon(Icons.payment, size: 24),
                          label: const Text(
                            'COBRAR',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: scheme.primary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _currentCart.items.isEmpty
                              ? null
                              : _saveAsQuote,
                          icon: const Icon(Icons.description),
                          label: const Text('COTIZAR'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: scheme.secondary,
                            foregroundColor: scheme.onSecondary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(SaleItemModel item, int index) {
    final isSelected = _selectedCartItemIndex == index;
    final subtotal = (item.qty * item.unitPrice) - item.discountLine;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) => Transform.scale(
        scale: 0.8 + (0.2 * value.clamp(0.0, 1.0)),
        child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 3),
        elevation: isSelected ? 4 : 2,
        shadowColor: isSelected
            ? scheme.primary.withOpacity(0.3)
            : Theme.of(context).shadowColor.withOpacity(0.26),
        color: isSelected ? scheme.primary.withOpacity(0.08) : transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: isSelected
              ? BorderSide(color: scheme.primary.withOpacity(0.45), width: 1.5)
              : BorderSide(
                  color: scheme.onSurface.withOpacity(0.2),
                  width: 0.5,
                ),
        ),
        child: InkWell(
          onTap: () => setState(() => _selectedCartItemIndex = index),
          onDoubleTap: () => _showEditItemDialog(item, index),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${item.qty.toInt()}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: scheme.primary.withOpacity(0.98),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.productNameSnapshot.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item.productCodeSnapshot.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          color: scheme.onSurface.withOpacity(0.6),
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMiniButton(Icons.remove, () {
                      if (item.qty > 1) {
                        setState(
                          () =>
                              _currentCart.updateQuantity(index, item.qty - 1),
                        );
                      }
                    }),
                    _buildMiniButton(
                      Icons.add,
                      () => _incrementCartItemQty(item, index),
                    ),
                  ],
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 70,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.discountLine > 0)
                        Text(
                          '-${item.discountLine.toStringAsFixed(0)}',
                          style: TextStyle(
                            fontSize: 8,
                            color: scheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        subtotal.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary.withOpacity(0.92),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: () =>
                      _updateCurrentCart(() => _currentCart.removeItem(index)),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: scheme.error.withOpacity(0.8),
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

  Widget _buildMiniButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 22,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: scheme.onSurface.withOpacity(0.3),
            width: 0.5,
          ),
        ),
        child: Icon(icon, size: 12, color: scheme.onSurface.withOpacity(0.7)),
      ),
    );
  }

  Widget _buildTotalRow(
    String label,
    double amount,
    bool isTotal, {
    Color? color,
    bool isSubtotal = false,
    bool isTax = false,
  }) {
    return Container(
      padding: isTotal
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
          : null,
      decoration: isTotal
          ? BoxDecoration(
              color: transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: scheme.primary.withOpacity(0.22),
                width: 2,
              ),
            )
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (isTotal)
                Icon(
                  Icons.attach_money,
                  size: 20,
                  color: scheme.primary.withOpacity(0.92),
                ),
              if (isTotal) const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: isTotal ? 20 : 13,
                  fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
                  color:
                      color ??
                      (isTotal
                          ? scheme.primary
                          : scheme.onSurface.withOpacity(0.7)),
                  letterSpacing: isTotal ? 0.5 : 0,
                ),
              ),
            ],
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isTotal ? 24 : 14,
              fontWeight: FontWeight.bold,
              color:
                  color ??
                  (isTotal
                      ? scheme.primary.withOpacity(0.98)
                      : scheme.onSurface.withOpacity(0.87)),
              letterSpacing: isTotal ? 0.5 : 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientSelector() {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.onSurface.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _currentCart.selectedClient == null
                ? TextButton.icon(
                    onPressed: _showClientPicker,
                    icon: const Icon(Icons.person_add, size: 20),
                    label: const Text('Seleccionar Cliente'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  )
                : InkWell(
                    onTap: _showClientPicker,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.person, size: 20, color: scheme.primary),
                          SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentCart.selectedClient!.nombre,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_currentCart.selectedClient!.telefono !=
                                    null)
                                  Text(
                                    _currentCart.selectedClient!.telefono!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: scheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          if (_currentCart.selectedClient != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: _removeClient,
              tooltip: 'Quitar cliente',
            ),
        ],
      ),
    );
  }

  /// Construye la barra mejorada de tickets pendientes con contador y selector
  Widget _buildPendingTicketsBar() {
    final totalTickets = _carts.length;
    final activeCart = _currentCart;

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _showTicketSelector,
            icon: const Icon(Icons.add_circle_outline, size: 20),
            label: Row(
              children: [
                Text(
                  'Tickets ($totalTickets)',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.confirmation_num_outlined,
                  size: 18,
                  color: scheme.onPrimary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    activeCart.displayName,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Gestor unificado: agregar, seleccionar, renombrar y eliminar en un solo diálogo centrado
  Future<void> _showTicketSelector() async {
    final nameController = TextEditingController(
      text: 'Ticket ${_carts.length + 1}',
    );
    final editController = TextEditingController();
    final ticketListController = ScrollController();
    int? editingIndex;

    Future<void> addTicketAndClose(BuildContext dialogContext) async {
      final raw = nameController.text.trim();
      final ticketName = raw.isEmpty ? 'Ticket ${_carts.length + 1}' : raw;

      if (!mounted) return;
      setState(() {
        final cart = _Cart(name: ticketName);
        _applySalesDefaultsToCart(cart);
        _carts.add(cart);
        _currentCartIndex = _carts.length - 1;
      });

      if (Navigator.of(dialogContext).canPop()) {
        Navigator.of(dialogContext).pop(_currentCartIndex);
      }
    }

    Future<void> deleteTicketInline(
      int index,
      StateSetter setModalState,
    ) async {
      if (_carts.length <= 1) return;
      final cart = _carts[index];
      if (cart.ticketId != null) {
        await TicketsRepository().deleteTicket(cart.ticketId!);
        if (!mounted) return;
      }

      if (!mounted) return;
      setState(() {
        _carts.removeAt(index);
        if (_currentCartIndex >= _carts.length) {
          _currentCartIndex = _carts.isEmpty ? 0 : _carts.length - 1;
        }
      });

      try {
        setModalState(() {
          if (editingIndex == index) editingIndex = null;
        });
      } catch (_) {}
    }

    Future<void> renameTicketInline(
      int index,
      StateSetter setModalState,
    ) async {
      final newName = editController.text.trim();
      if (newName.isEmpty) return;
      if (!mounted) return;
      setState(() => _carts[index].name = newName);
      if (_carts[index].ticketId != null) {
        await TicketsRepository().updateTicketName(
          _carts[index].ticketId!,
          newName,
        );
      }
      if (!mounted) return;
      try {
        setModalState(() => editingIndex = null);
      } catch (_) {}
    }

    try {
      final selected = await _presentDialog<int>(
        barrierDismissible: true,
        builder: (context) {
          return _DialogHotkeys(
            onEnter: () => addTicketAndClose(context),
            child: AlertDialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 32,
              ),
              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Icon(Icons.confirmation_num_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Text('Tickets'),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              content: StatefulBuilder(
                builder: (context, setModalState) {
                  final listHeight = math.min<double>(
                    360,
                    math.max<double>(140, _carts.length * 86),
                  );

                  return SizedBox(
                    width: 520,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: nameController,
                                decoration: const InputDecoration(
                                  labelText: 'Nombre del ticket',
                                  prefixIcon: Icon(Icons.edit_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              tooltip: 'Agregar y seleccionar',
                              onPressed: () => addTicketAndClose(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Icon(
                              Icons.list_alt_outlined,
                              color: scheme.onSurface.withOpacity(0.7),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Selecciona, renombra o elimina',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: listHeight,
                          child: _carts.isEmpty
                              ? Center(
                                  child: Text(
                                    'Sin tickets',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium,
                                  ),
                                )
                              : Scrollbar(
                                  controller: ticketListController,
                                  thumbVisibility: true,
                                  child: ListView.separated(
                                    controller: ticketListController,
                                    primary: false,
                                    shrinkWrap: true,
                                    itemCount: _carts.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(height: 8),
                                    itemBuilder: (context, index) => _TicketRow(
                                      cart: _carts[index],
                                      isActive: index == _currentCartIndex,
                                      isEditing: editingIndex == index,
                                      onTap: () =>
                                          Navigator.pop(context, index),
                                      onRenameToggle: () {
                                        editController.text =
                                            _carts[index].name;
                                        setModalState(
                                          () => editingIndex = index,
                                        );
                                      },
                                      onRenameSave: () => renameTicketInline(
                                        index,
                                        setModalState,
                                      ),
                                      onDelete: _carts.length > 1
                                          ? () => deleteTicketInline(
                                              index,
                                              setModalState,
                                            )
                                          : null,
                                      editController: editController,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        },
      );

      if (!mounted || selected == null) return;
      setState(() => _currentCartIndex = selected);
    } finally {
      ticketListController.dispose();
      nameController.dispose();
      editController.dispose();
    }
  }
}

class _TicketRow extends StatelessWidget {
  const _TicketRow({
    required this.cart,
    required this.isActive,
    required this.isEditing,
    required this.onTap,
    required this.onRenameToggle,
    required this.onRenameSave,
    required this.editController,
    this.onDelete,
  });

  final _Cart cart;
  final bool isActive;
  final bool isEditing;
  final VoidCallback onTap;
  final VoidCallback onRenameToggle;
  final VoidCallback onRenameSave;
  final VoidCallback? onDelete;
  final TextEditingController editController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isActive
                ? scheme.primary.withOpacity(0.08)
                : scheme.surfaceVariant.withOpacity(0.45),
            border: Border.all(
              color: isActive
                  ? scheme.primary.withOpacity(0.4)
                  : scheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isActive
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isActive ? scheme.primary : scheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  if (isEditing)
                    Expanded(
                      child: TextField(
                        controller: editController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Nombre del ticket',
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: Text(
                        cart.displayName,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  if (cart.items.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Chip(
                        label: Text(
                          '${cart.items.length} item${cart.items.length > 1 ? 's' : ''}',
                          style: theme.textTheme.labelSmall,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  const SizedBox(width: 6),
                  IconButton(
                    icon: Icon(
                      isEditing ? Icons.check : Icons.edit_outlined,
                      color: scheme.onSurface.withOpacity(0.8),
                    ),
                    tooltip: isEditing ? 'Guardar nombre' : 'Renombrar',
                    onPressed: isEditing ? onRenameSave : onRenameToggle,
                  ),
                  if (onDelete != null)
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: scheme.error),
                      tooltip: 'Eliminar',
                      onPressed: onDelete,
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                cart.items.isEmpty
                    ? 'Sin items'
                    : '${cart.items.length} item${cart.items.length > 1 ? 's' : ''} - RD\$${cart.calculateTotal().toStringAsFixed(2)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Envuelve diálogos para soportar Escape (cerrar) y Enter (acción primaria opcional).
class _DialogHotkeys extends StatelessWidget {
  const _DialogHotkeys({required this.child, this.onEnter});

  final Widget child;
  final VoidCallback? onEnter;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.numpadEnter): const ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (intent) {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
              return null;
            },
          ),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              onEnter?.call();
              return null;
            },
          ),
        },
        child: FocusScope(autofocus: true, child: child),
      ),
    );
  }
}

class _Cart {
  String name;
  int? ticketId;
  int? tempCartId; // ID del carrito temporal en la base de datos
  bool isCompleted = false; // Marca si la venta fue completada
  final List<SaleItemModel> items = [];
  double discount = 0.0;
  bool itbisEnabled = true;
  double itbisRate = 0.18;
  bool fiscalEnabled = false;
  NcfBookModel? selectedNcf;
  ClientModel? selectedClient;

  String? discountTotalType;
  double? discountTotalValue;

  _Cart({required this.name});

  /// Nombre limpio para mostrar en la UI (elimina "(Copia)" repetidos)
  String get displayName {
    // Si tiene cliente seleccionado, usar nombre del cliente con formato limpio
    if (selectedClient != null) {
      final clientName = selectedClient!.nombre.trim();
      // Si el ticketId existe, usar un formato tipo "Ticket X - Cliente"
      if (ticketId != null) {
        return 'Ticket $ticketId - $clientName';
      }
      return clientName;
    }

    // Limpiar nombre eliminando "(Copia)" repetidos
    String cleanName = name;

    // Remover múltiples "(Copia)" y dejar solo uno si existe
    final copiaRegex = RegExp(r'\s*\(Copia\)', caseSensitive: false);
    final hasCopia = copiaRegex.hasMatch(cleanName);
    cleanName = cleanName.replaceAll(copiaRegex, '').trim();

    // Si tenía (Copia), agregar solo uno
    if (hasCopia) {
      cleanName = '$cleanName (Copia)';
    }

    // Si el nombre está muy largo, truncar
    if (cleanName.length > 25) {
      cleanName = '${cleanName.substring(0, 22)}...';
    }

    return cleanName;
  }

  void addProduct(ProductModel product) {
    final existingIndex = items.indexWhere(
      (item) => item.productId == product.id,
    );
    if (existingIndex >= 0) {
      items[existingIndex] = items[existingIndex].copyWith(
        qty: items[existingIndex].qty + 1,
      );
    } else {
      final now = DateTime.now().millisecondsSinceEpoch;
      items.add(
        SaleItemModel(
          id: null,
          saleId: 0,
          productId: product.id,
          productCodeSnapshot: product.code,
          productNameSnapshot: product.name,
          qty: 1,
          unitPrice: product.salePrice,
          discountLine: 0.0,
          purchasePriceSnapshot: product.purchasePrice,
          totalLine: product.salePrice,
          createdAtMs: now,
        ),
      );
    }
  }

  double getQuantityForProduct(int productId) {
    double total = 0.0;
    for (final item in items) {
      if (item.productId == productId) total += item.qty;
    }
    return total;
  }

  void updateQuantity(int index, double newQty) {
    if (index >= 0 && index < items.length) {
      items[index] = items[index].copyWith(qty: newQty);
    }
  }

  void removeItem(int index) {
    if (index >= 0 && index < items.length) items.removeAt(index);
  }

  void clear() {
    items.clear();
    discount = 0.0;
    discountTotalType = null;
    discountTotalValue = null;
    selectedClient = null;
    selectedNcf = null;
  }

  double calculateGrossSubtotal() {
    double subtotal = 0.0;
    for (var item in items) {
      subtotal += item.qty * item.unitPrice;
    }
    return subtotal;
  }

  double calculateLineDiscounts() {
    double total = 0.0;
    for (var item in items) {
      total += item.discountLine;
    }
    return total;
  }

  double calculateSubtotal() {
    return calculateGrossSubtotal() - calculateLineDiscounts() - discount;
  }

  double calculateTotalDiscount() {
    if (discountTotalValue == null || discountTotalValue! <= 0) return 0.0;
    final subtotal = calculateSubtotal();
    if (discountTotalType == 'percent') {
      return subtotal * (discountTotalValue! / 100);
    }
    return discountTotalValue!;
  }

  double calculateSubtotalAfterDiscount() {
    return (calculateSubtotal() - calculateTotalDiscount()).clamp(
      0.0,
      double.infinity,
    );
  }

  double calculateTotalDiscountsCombined() {
    final total =
        calculateLineDiscounts() + discount + calculateTotalDiscount();
    return total.clamp(0.0, double.infinity);
  }

  double calculateItbis() =>
      itbisEnabled ? calculateSubtotalAfterDiscount() * itbisRate : 0.0;

  double calculateTotal() =>
      calculateSubtotalAfterDiscount() + calculateItbis();
}

// ---- Shortcut intents ----------------------------------------------------
class FocusSearchProductIntent extends Intent {
  const FocusSearchProductIntent();
}

class FocusSearchClientIntent extends Intent {
  const FocusSearchClientIntent();
}

class OpenManualSaleIntent extends Intent {
  const OpenManualSaleIntent();
}

class OpenTicketSelectorIntent extends Intent {
  const OpenTicketSelectorIntent();
}

class NewClientIntent extends Intent {
  const NewClientIntent();
}

class ApplyDiscountIntent extends Intent {
  const ApplyDiscountIntent();
}

class OpenPaymentIntent extends Intent {
  const OpenPaymentIntent();
}

class OpenPaymentAndPrintIntent extends Intent {
  const OpenPaymentAndPrintIntent();
}

class FinalizeSaleIntent extends Intent {
  const FinalizeSaleIntent();
}

class DeleteSelectedItemIntent extends Intent {
  const DeleteSelectedItemIntent();
}

class IncreaseQuantityIntent extends Intent {
  const IncreaseQuantityIntent();
}

class DecreaseQuantityIntent extends Intent {
  const DecreaseQuantityIntent();
}
