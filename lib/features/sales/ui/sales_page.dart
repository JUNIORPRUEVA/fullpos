import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../../../core/debug/app_logger.dart' as debug_log;
import '../../../core/errors/error_handler.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/empresa_service.dart';
import '../../../core/ui/responsive_grid.dart';
import '../../../core/printing/invoice_letter_pdf.dart';
import '../../../core/printing/quote_printer.dart';
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
import '../../../core/utils/currency_display.dart';
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
import '../../settings/data/business_settings_repository.dart';
import '../../settings/data/printer_settings_repository.dart';
import '../../settings/providers/business_settings_provider.dart';
import '../../facturacion_electronica/data/electronic_company_repository.dart';
import '../../facturacion_electronica/data/models/electronic_company_model.dart';
import '../data/app_settings_model.dart';
import '../data/sale_item_model.dart';
import '../data/sale_model.dart';
import '../data/layaway_repository.dart';
import '../data/quote_model.dart';
import '../data/quotes_repository.dart';
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

enum _InlineItemFocus { qty, discount }

/// Pantalla principal de POS con múltiples carritos
class SalesPage extends ConsumerStatefulWidget {
  const SalesPage({super.key, this.initialTicketId});

  /// Si viene seteado, al abrir Ventas intentará seleccionar ese ticket.
  final int? initialTicketId;

  @override
  ConsumerState<SalesPage> createState() => _SalesPageState();
}

class _SalesPageState extends ConsumerState<SalesPage> {
  static const double _productTileHeight = 88.0;
  static const double _productTileMaxExtent = 292.0;
  static const double _productTileMinHeight = 80.0;
  static const double _ticketsFooterHeight = 60.0;
  static const double _gridCrossSpacing = 8.0;
  static const double _gridMainSpacing = 8.0;

  double _productTileHeightFor(double availableWidth) {
    if (!availableWidth.isFinite || availableWidth <= 0) {
      return _productTileMinHeight;
    }
    final scale = (availableWidth / 1320).clamp(0.92, 1.0);
    final size = (_productTileHeight * scale).clamp(
      _productTileMinHeight,
      _productTileHeight,
    );
    return size.isFinite && size > 0 ? size : _productTileMinHeight;
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

  LinearGradient _resolveSalesDetailGradient(
    SalesDetailGradientTheme? gradientTheme,
  ) {
    final fallbackAccent = scheme.primary.withOpacity(0.14);
    return gradientTheme?.backgroundGradient ??
        LinearGradient(
          colors: [scheme.surface, fallbackAccent],
          stops: const [0.0, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
  }

  Color get salesDetailPanelColor {
    final gradientTheme = Theme.of(
      context,
    ).extension<SalesDetailGradientTheme>();
    final base = gradientTheme?.mid ?? scheme.surface;
    return Color.alphaBlend(scheme.surface.withOpacity(0.08), base);
  }

  Color get salesDetailBorderColor => salesDetailTextColor.withOpacity(0.14);

  Color get salesDetailMutedTextColor => salesDetailTextColor.withOpacity(0.7);

  final List<_Cart> _carts = [_Cart(name: 'Ticket 1')];
  int _currentCartIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _clientFocusNode = FocusNode();
  final ScrollController _ticketItemsScrollController = ScrollController();
  Timer? _cartPersistenceTimer;
  bool _cartPersistenceInFlight = false;
  bool _cartPersistenceDirty = false;
  String? _lastPersistedCartToken;
  String? _scheduledCartToken;

  // Optimización: índice de cantidades por producto para evitar O(n*m)
  // (cada tarjeta de producto recorriendo todos los items del carrito).
  Map<int, double> _qtyByProductId = const <int, double>{};

  void _rebuildQtyIndexForCurrentCart() {
    if (_carts.isEmpty) {
      _qtyByProductId = const <int, double>{};
      return;
    }
    final map = <int, double>{};
    for (final item in _currentCart.items) {
      final id = item.productId;
      if (id == null) continue;
      map[id] = (map[id] ?? 0) + item.qty;
    }
    _qtyByProductId = map;
  }

  double _qtyInCart(int? productId) {
    if (productId == null) return 0.0;
    return _qtyByProductId[productId] ?? 0.0;
  }

  void _setHoverStateDeferred<T>(Set<T> target, T value, bool isHovered) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final alreadyHovered = target.contains(value);
      if (alreadyHovered == isHovered) return;
      setState(() {
        if (isHovered) {
          target.add(value);
        } else {
          target.remove(value);
        }
      });
    });
  }

  void _dbgLog(String message, {Map<String, Object?>? data}) {
    assert(() {
      unawaited(
        debug_log.DebugAppLogger.instance.info(
          message,
          module: 'sales/freeze',
          data: data,
        ),
      );
      return true;
    }());
  }

  int? _filteredProductsCacheKey;
  List<ProductModel> _filteredProductsCache = const <ProductModel>[];

  int? _selectedCartItemIndex;

    int? _inlineEditCartItemIndex;
    DiscountType _inlineLineDiscountType = DiscountType.amount;
    final TextEditingController _inlineQtyController = TextEditingController();
    final TextEditingController _inlineLineDiscountController =
      TextEditingController();
    final FocusNode _inlineQtyFocusNode = FocusNode();
    final FocusNode _inlineLineDiscountFocusNode = FocusNode();

    bool _isInlineTotalDiscountOpen = false;
    DiscountType _inlineTotalDiscountType = DiscountType.percent;
    final TextEditingController _inlineTotalDiscountController =
      TextEditingController();
    final FocusNode _inlineTotalDiscountFocusNode = FocusNode();

  bool _keyboardShortcutsEnabled = true;
  ScannerInputController? _scanner;
  late final bool Function(KeyEvent) _globalShortcutHandler;

  String? _lastScanCode;
  int _lastScanAtMs = 0;
  bool? _previousCashOpen;
  int _initialLoadToken = 0;
  bool _loggedFirstBuild = false;
  bool _sessionBootstrapScheduled = false;
  final Set<int> _hoveredProductIndexes = <int>{};
  final Set<String> _hoveredTicketHeaderActions = <String>{};
  final Set<String> _processedPaymentRequestIds = <String>{};
  bool _isProcessingSaleExecution = false;

  List<ProductModel> _allProducts = [];
  List<ProductModel> _searchResults = [];
  bool _isSearching = false;

  ElectronicCompanyModel? _electronicCompany;
  List<CategoryModel> _categories = [];
  List<ClientModel> _clients = [];
  AppSettingsModel? _appSettings;
  ProductFilterModel _productFilter = ProductFilterModel();
  String? _selectedCategory;

  _Cart get _currentCart => _carts[_currentCartIndex];

  bool get _isElectronicInvoicingFeatureEnabled =>
      ref.read(businessSettingsProvider).electronicInvoicingEnabled;

  void _disableElectronicInvoicingForAllCarts() {
    var changed = false;
    for (final cart in _carts) {
      if (!cart.electronicInvoiceEnabled) continue;
      cart.electronicInvoiceEnabled = false;
      changed = true;
    }

    if (!changed || !mounted) return;

    setState(() {});
    unawaited(_saveAllCartsToDatabase());
    _scheduleCartPersistence();
  }

  void _applySalesDefaultsToCart(_Cart cart) {
    final settings = _appSettings;
    if (settings == null) return;

    cart.itbisRate = settings.itbisRate;
    cart.itbisEnabled = settings.itbisEnabledDefault;
    cart.electronicInvoiceEnabled =
        _isElectronicInvoicingFeatureEnabled &&
        settings.electronicInvoiceEnabledDefault;
    if (cart.electronicInvoiceEnabled) {
      // La emisión electrónica implica ITBIS activo.
      cart.itbisEnabled = true;
    }
  }

  BoxConstraints _ticketPanelConstraints(double width) {
    // En layout horizontal, hacemos el panel proporcional para no aplastar
    // el grid cuando el ancho baja.
    if (width < 1350) {
      // +10–15% para que el panel se sienta como un POS real.
      final max = (width * 0.38).clamp(320.0, 450.0);
      final min = (max - 80).clamp(300.0, max);
      return BoxConstraints(minWidth: min, maxWidth: max);
    }
    if (width < 1600) {
      final max = (width * 0.35).clamp(400.0, 520.0);
      final min = (max - 90).clamp(360.0, max);
      return BoxConstraints(minWidth: min, maxWidth: max);
    }
    final max = (width * 0.33).clamp(460.0, 600.0);
    final min = (max - 100).clamp(380.0, max);
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
      unawaited(_refreshCashSession());
      unawaited(_ensureSessionBootstrap());
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
        ticketsRepo.listTickets(userId: await SessionManager.userId()),
        tempCartRepo.getAllCarts(),
        SettingsRepository.getAppSettings(),
        ElectronicCompanyRepository.getOrCreate(),
      ]);
      if (!mounted || token != _initialLoadToken) return;

      final products = results[0] as List<ProductModel>;
      final categories = results[1] as List<CategoryModel>;
      final clients = results[2] as List<ClientModel>;
      final dbTickets = results[3] as List<PosTicketModel>;
      final tempCarts = results[4] as List<Map<String, dynamic>>;
      final appSettings = results[5] as AppSettingsModel;
      final electronicCompany = results[6] as ElectronicCompanyModel;
      final electronicInvoicingFeatureEnabled =
          _isElectronicInvoicingFeatureEnabled;

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
          ..discount = ticketModel.discountTotal
          ..electronicInvoiceEnabled = false;

        final clientId = ticketModel.clientId;
        if (clientId != null) {
          final client = clients.where((c) => c.id == clientId).firstOrNull;
          if (client != null) cart.selectedClient = client;
        }

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

      final ticketCartSignatures = loadedCarts
          .where((cart) => cart.ticketId != null)
          .map(_buildCartPersistenceSignature)
          .toSet();

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
          ..electronicInvoiceEnabled =
              electronicInvoicingFeatureEnabled &&
              (cartMap['electronic_invoice_enabled'] as int) == 1
          ..discountTotalType = cartMap['discount_total_type'] as String?
          ..discountTotalValue = (cartMap['discount_total_value'] as num?)
              ?.toDouble();

        final clientId = cartMap['client_id'] as int?;
        if (clientId != null) {
          final client = clients.where((c) => c.id == clientId).firstOrNull;
          if (client != null) cart.selectedClient = client;
        }

        cart.items.addAll(tempCartItemsById[id] ?? const <SaleItemModel>[]);

        final signature = _buildCartPersistenceSignature(cart);
        if (ticketCartSignatures.contains(signature)) {
          debugPrint(
            '[SALES] Omitiendo carrito temporal duplicado del ticket tempCartId=$id',
          );
          continue;
        }

        loadedCarts.add(cart);
      }

      if (!mounted || token != _initialLoadToken) return;

      var initialCartIndex = 0;
      final openTicketId = widget.initialTicketId;
      if (openTicketId != null && loadedCarts.isNotEmpty) {
        final idx = loadedCarts.indexWhere((c) => c.ticketId == openTicketId);
        if (idx >= 0) initialCartIndex = idx;
      }

      setState(() {
        _allProducts = products;
        _searchResults = products;
        _categories = categories;
        _clients = clients;
        _appSettings = appSettings;
        _electronicCompany = electronicCompany;
        if (loadedCarts.isNotEmpty) {
          _carts.clear();
          _carts.addAll(loadedCarts);
          _currentCartIndex = initialCartIndex;
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
    await ref.read(activeSessionControllerProvider.notifier).refresh();
  }

  int? get _activeSessionId =>
      ref.read(activeSessionControllerProvider).valueOrNull?.shiftId;

  Future<void> _ensureSessionBootstrap({bool force = false}) async {
    if (_sessionBootstrapScheduled && !force) return;
    _sessionBootstrapScheduled = true;
    try {
      await _refreshCashSession();
      final activeSession = ref
          .read(activeSessionControllerProvider)
          .valueOrNull;
      if (activeSession != null || !mounted) return;

      final opened = await CashOpenDialog.show(context);
      if (opened == true) {
        await _refreshCashSession();
      }
    } finally {
      _sessionBootstrapScheduled = false;
    }
  }

  Future<int?> _ensureActiveShiftOrRedirect({bool showMessage = true}) async {
    await _refreshCashSession();
    final liveSessionId = ref
        .read(activeSessionControllerProvider)
        .valueOrNull
        ?.shiftId;
    if (liveSessionId != null) {
      return liveSessionId;
    }
    if (!mounted) return null;
    if (showMessage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No hay una sesión activa. Debes abrir caja para continuar.',
          ),
          backgroundColor: scheme.error,
        ),
      );
    }
    return null;
  }

  Future<void> _openCashMovement(String type) async {
    var sessionId = await _ensureActiveShiftOrRedirect(showMessage: true);
    if (sessionId == null) {
      final opened = await CashOpenDialog.show(context);
      if (opened == true) await _refreshCashSession();
      sessionId = await _ensureActiveShiftOrRedirect(showMessage: false);
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
            electronicInvoiceEnabled: cart.electronicInvoiceEnabled,
            discountTotalType: cart.discountTotalType,
            discountTotalValue: cart.discountTotalValue,
            items: cart.items,
          );
        } catch (e) {
          debugPrint('Error guardando carrito temporal: $e');
          unawaited(
            ErrorHandler.instance.handle(e, module: 'sales/temp_cart_save_all'),
          );
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

  Future<void> _deletePendingTicketFromDatabase(int? ticketId) async {
    if (ticketId == null) return;
    try {
      await TicketsRepository().deleteTicket(ticketId);
    } catch (e) {
      debugPrint('Error eliminando ticket pendiente: $e');
    }
  }

  Future<void> _runSaleOutputs({
    required int saleId,
    required bool shouldPrint,
    required bool shouldDownloadInvoicePdf,
    required bool shouldAutoOpenDrawerWithoutTicket,
    required bool isLayaway,
    required double receivedAmount,
  }) async {
    if (shouldAutoOpenDrawerWithoutTicket) {
      try {
        await UnifiedTicketPrinter.openCashDrawerPulse();
      } catch (e) {
        debugPrint('Error al abrir caja registradora automáticamente: $e');
      }
    }

    if (!shouldPrint && !shouldDownloadInvoicePdf) {
      return;
    }

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
    setState(() {
      update();
      _rebuildQtyIndexForCurrentCart();
    });
    _scheduleCartPersistence();
  }

  void _scheduleCartPersistence() {
    _cartPersistenceDirty = true;
    final token = _buildCartPersistenceToken(_currentCart);
    _scheduledCartToken = token;

    // Si ya persistimos exactamente este estado (y no hay persistencia en curso), no hacer nada.
    if (!_cartPersistenceInFlight && _lastPersistedCartToken == token) {
      return;
    }

    _cartPersistenceTimer?.cancel();
    _cartPersistenceTimer = Timer(const Duration(milliseconds: 550), () {
      unawaited(_persistCurrentCartToDatabase());
    });
  }

  Future<void> _persistCurrentCartToDatabase() async {
    _cartPersistenceTimer = null;
    if (!mounted) return;

    Stopwatch? persistSw;
    assert(() {
      persistSw = Stopwatch()..start();
      _dbgLog(
        'persist_start',
        data: {
          'cartItems': _currentCart.items.length,
          'tempCartId': _currentCart.tempCartId,
          'ticketId': _currentCart.ticketId,
        },
      );
      return true;
    }());

    // Evita ejecuciones simultáneas (puede causar jank/locks en sqlite).
    if (_cartPersistenceInFlight) {
      _cartPersistenceDirty = true;
      return;
    }

    _cartPersistenceInFlight = true;
    try {
      while (mounted) {
        _cartPersistenceDirty = false;
        final token =
            _scheduledCartToken ?? _buildCartPersistenceToken(_currentCart);
        _scheduledCartToken = token;

        if (_lastPersistedCartToken == token) {
          return;
        }

        if (_currentCart.items.isEmpty) {
          await _deleteCurrentCartFromDatabase();
          _lastPersistedCartToken = token;
        } else if (_currentCart.ticketId != null) {
          final staleTempCartId = _currentCart.tempCartId;
          _currentCart.tempCartId = null;
          await _deleteTempCartFromDatabase(staleTempCartId);
          _lastPersistedCartToken = token;
        } else {
          final repo = TempCartRepository();
          final userId = await SessionManager.userId();
          assert(() {
            _dbgLog(
              'persist_saveCart_call',
              data: {
                'cartItems': _currentCart.items.length,
                'tempCartId': _currentCart.tempCartId,
              },
            );
            return true;
          }());
          try {
            final savedId = await repo.saveCart(
              id: _currentCart.tempCartId,
              name: _currentCart.name,
              userId: userId,
              clientId: _currentCart.selectedClient?.id,
              discount: _currentCart.discount,
              itbisEnabled: _currentCart.itbisEnabled,
              itbisRate: _currentCart.itbisRate,
              electronicInvoiceEnabled: _currentCart.electronicInvoiceEnabled,
              discountTotalType: _currentCart.discountTotalType,
              discountTotalValue: _currentCart.discountTotalValue,
              items: _currentCart.items,
            );
            _currentCart.tempCartId = savedId;
            _lastPersistedCartToken = token;
            assert(() {
              _dbgLog(
                'persist_saveCart_ok',
                data: {
                  'savedId': savedId,
                  'cartItems': _currentCart.items.length,
                  'ms': persistSw?.elapsedMilliseconds,
                },
              );
              return true;
            }());
          } catch (e, st) {
            debugPrint('Error guardando carrito temporal: $e $st');
            // Mostrar el error (copiable) para diagnóstico en sitio.
            unawaited(
              ErrorHandler.instance.handle(
                e,
                stackTrace: st,
                module: 'sales/temp_cart_persist',
              ),
            );
            assert(() {
              _dbgLog(
                'persist_saveCart_error',
                data: {
                  'cartItems': _currentCart.items.length,
                  'tempCartId': _currentCart.tempCartId,
                  'ms': persistSw?.elapsedMilliseconds,
                  'error': '$e',
                },
              );
              return true;
            }());
            // No marcar como persistido para permitir retry.
          }
        }

        if (!_cartPersistenceDirty) {
          return;
        }

        // Ceder el event loop antes de reintentar si el carrito cambió durante el guardado.
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      _cartPersistenceInFlight = false;
      assert(() {
        _dbgLog(
          'persist_end',
          data: {
            'cartItems': _currentCart.items.length,
            'ms': persistSw?.elapsedMilliseconds,
          },
        );
        return true;
      }());
    }
  }

  Future<void> _refreshElectronicCompany() async {
    try {
      final company = await ElectronicCompanyRepository.getOrCreate();
      if (!mounted) return;
      setState(() => _electronicCompany = company);
    } catch (e, st) {
      debugPrint('Error loading electronic company settings: $e\\n$st');
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

    _rebuildQtyIndexForCurrentCart();
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

  _SalesDocumentType _deriveSalesDocumentType() {
    if (_currentCart.electronicInvoiceEnabled) {
      return _SalesDocumentType.creditoFiscal;
    }
    if (!_currentCart.itbisEnabled) {
      return _SalesDocumentType.cotizacion;
    }
    return _SalesDocumentType.consumidorFinal;
  }

  payment.PaymentDocumentType _paymentDocumentTypeFromCart() {
    switch (_deriveSalesDocumentType()) {
      case _SalesDocumentType.consumidorFinal:
        return payment.PaymentDocumentType.consumidorFinal;
      case _SalesDocumentType.creditoFiscal:
        return payment.PaymentDocumentType.creditoFiscal;
      case _SalesDocumentType.cotizacion:
        return payment.PaymentDocumentType.cotizacion;
    }
  }

  Future<void> _setSalesDocumentType(_SalesDocumentType type) async {
    if (type == _SalesDocumentType.consumidorFinal) {
      _updateCurrentCart(() {
        _currentCart.electronicInvoiceEnabled = false;
        _currentCart.itbisEnabled = true;
      });
      return;
    }

    if (type == _SalesDocumentType.cotizacion) {
      _updateCurrentCart(() {
        _currentCart.electronicInvoiceEnabled = false;
        _currentCart.itbisEnabled = false;
      });
      return;
    }

    if (!_isElectronicInvoicingFeatureEnabled) return;

    if (!await _canEnableElectronicInvoiceOrNotify()) {
      return;
    }

    _updateCurrentCart(() {
      _currentCart.electronicInvoiceEnabled = true;
      _currentCart.itbisEnabled = true;
    });
    await _refreshElectronicCompany();
  }

  Future<payment.PaymentDocumentType> _setPaymentDocumentType(
    payment.PaymentDocumentType type,
  ) async {
    switch (type) {
      case payment.PaymentDocumentType.consumidorFinal:
        await _setSalesDocumentType(_SalesDocumentType.consumidorFinal);
      case payment.PaymentDocumentType.creditoFiscal:
        await _setSalesDocumentType(_SalesDocumentType.creditoFiscal);
      case payment.PaymentDocumentType.cotizacion:
        await _setSalesDocumentType(_SalesDocumentType.cotizacion);
    }
    return _paymentDocumentTypeFromCart();
  }

  void _openFacturaPage() {
    AuthzService.guardedAction(
      context,
      authz_perm.Permissions.salesHistoryView,
      () => context.go('/factura'),
      reason: 'Abrir factura',
      resourceType: 'route',
      resourceId: '/factura',
    )();
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

    setState(() {
      _inlineEditCartItemIndex = null;
      _isInlineTotalDiscountOpen = !_isInlineTotalDiscountOpen;

      final currentType = _currentCart.discountTotalType == 'amount'
          ? DiscountType.amount
          : DiscountType.percent;
      _inlineTotalDiscountType = currentType;

      final value = _currentCart.discountTotalValue ?? 0.0;
      _inlineTotalDiscountController.text =
          value > 0 ? value.toStringAsFixed(2) : '';
    });

    if (!_isInlineTotalDiscountOpen) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inlineTotalDiscountFocusNode.requestFocus();
      _inlineTotalDiscountController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _inlineTotalDiscountController.text.length,
      );
    });
  }

  bool _isValidTotalDiscount(
    double subtotal,
    DiscountType type,
    double value,
  ) {
    if (value <= 0) return false;
    if (type == DiscountType.percent) {
      return value > 0 && value <= 100;
    }
    return value > 0 && value < subtotal;
  }

  double _computeTotalDiscountAmount(
    double subtotal,
    DiscountType type,
    double value,
  ) {
    if (type == DiscountType.percent) {
      return subtotal * (value / 100);
    }
    return value;
  }

  double _computeInlineTotalDiscountPreviewTotal() {
    final subtotal = _currentCart.calculateSubtotal();
    final raw = double.tryParse(_inlineTotalDiscountController.text) ?? 0.0;
    final discountAmount = _computeTotalDiscountAmount(
      subtotal,
      _inlineTotalDiscountType,
      raw,
    );
    final after = (subtotal - discountAmount).clamp(0.0, double.infinity);
    final itbis = _currentCart.itbisEnabled ? after * _currentCart.itbisRate : 0.0;
    return after + itbis;
  }

  void _removeInlineTotalDiscount() {
    _updateCurrentCart(() {
      _currentCart.discountTotalType = null;
      _currentCart.discountTotalValue = null;
    });
    setState(() => _isInlineTotalDiscountOpen = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Descuento eliminado'),
        backgroundColor: status.success,
      ),
    );
  }

  Future<void> _applyInlineTotalDiscount() async {
    final subtotal = _currentCart.calculateSubtotal();
    final value = double.tryParse(_inlineTotalDiscountController.text) ?? 0.0;
    final type = _inlineTotalDiscountType;

    if (!_isValidTotalDiscount(subtotal, type, value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            type == DiscountType.percent
                ? 'El porcentaje debe ser entre 0% y 100%'
                : 'El monto debe ser menor al subtotal',
          ),
          backgroundColor: scheme.error,
        ),
      );
      return;
    }

    await _applyTotalDiscountResult(DiscountResult(type: type, value: value));
    if (!mounted) return;
    setState(() => _isInlineTotalDiscountOpen = false);
  }

  Future<void> _applyTotalDiscountResult(DiscountResult result) async {
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
      _currentCart.discountTotalType =
          result.type == DiscountType.percent ? 'percent' : 'amount';
      _currentCart.discountTotalValue = result.value;
    });
    final discountLabel = result.type == DiscountType.percent
        ? 'Descuento aplicado: ${result.value.toStringAsFixed(1)}%'
        : 'Descuento aplicado: ${CurrencyDisplay.format(result.value)}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(discountLabel), backgroundColor: status.success),
    );
  }

  void _removeClient() {
    final ticketIndex = _carts.indexOf(_currentCart);
    _updateCurrentCart(() {
      _currentCart.selectedClient = null;
      _currentCart.name = 'Ticket ${ticketIndex + 1}';
    });
  }

  Future<void> _addProductToCart(ProductModel product) async {
    assert(() {
      _dbgLog(
        'add_product_start',
        data: {
          'productId': product.id,
          'cartItems': _currentCart.items.length,
          'tempCartId': _currentCart.tempCartId,
          'ticketId': _currentCart.ticketId,
        },
      );
      return true;
    }());

    if (product.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Producto inválido (sin ID)'),
          backgroundColor: scheme.error,
        ),
      );
      return;
    }

    final qtyInCart = _qtyInCart(product.id);
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

    try {
      _updateCurrentCart(() => _currentCart.addProduct(product));
      assert(() {
        _dbgLog(
          'add_product_setstate_done',
          data: {
            'productId': product.id,
            'cartItems': _currentCart.items.length,
          },
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _dbgLog(
            'add_product_frame_painted',
            data: {
              'productId': product.id,
              'cartItems': _currentCart.items.length,
            },
          );
        });
        return true;
      }());
    } catch (e, st) {
      debugPrint('Error agregando producto al carrito: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo agregar el producto'),
          backgroundColor: scheme.error,
        ),
      );
    }
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
    final available = product.stock - _qtyInCart(item.productId);
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
    _openInlineItemEditor(item, index, focus: _InlineItemFocus.qty);
  }

  void _openInlineItemEditor(
    SaleItemModel item,
    int index, {
    required _InlineItemFocus focus,
  }) {
    setState(() {
      if (_inlineEditCartItemIndex == index) {
        _inlineEditCartItemIndex = null;
        return;
      }
      _inlineEditCartItemIndex = index;
      _inlineLineDiscountType = DiscountType.amount;
      _inlineQtyController.text = _formatQtyForInlineEditor(item.qty);
      _inlineLineDiscountController.text = item.discountLine > 0
          ? item.discountLine.toStringAsFixed(2)
          : '';
      _isInlineTotalDiscountOpen = false;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final (focusNode, controller) = switch (focus) {
        _InlineItemFocus.discount => (
            _inlineLineDiscountFocusNode,
            _inlineLineDiscountController,
          ),
        _InlineItemFocus.qty => (
            _inlineQtyFocusNode,
            _inlineQtyController,
          ),
      };
      focusNode.requestFocus();
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: controller.text.length,
      );
    });
  }

  String _formatQtyForInlineEditor(double qty) {
    if (qty == qty.roundToDouble()) return qty.toStringAsFixed(0);
    return qty.toString();
  }

  double _computeLineDiscountAmount({
    required double qty,
    required double unitPrice,
    required DiscountType type,
    required String rawText,
  }) {
    final base = qty * unitPrice;
    final raw = double.tryParse(rawText) ?? 0.0;
    if (type == DiscountType.percent) {
      final pct = raw.clamp(0.0, 100.0);
      return base * (pct / 100.0);
    }
    return raw.clamp(0.0, base);
  }

  void _applyInlineQtyChanged(int index, String text) {
    if (index < 0 || index >= _currentCart.items.length) return;
    final parsed = double.tryParse(text);
    if (parsed == null) return;
    if (parsed <= 0) return;

    _updateCurrentCart(() {
      if (index < 0 || index >= _currentCart.items.length) return;
      final current = _currentCart.items[index];
      final discountAmount = _computeLineDiscountAmount(
        qty: parsed,
        unitPrice: current.unitPrice,
        type: _inlineLineDiscountType,
        rawText: _inlineLineDiscountController.text,
      );
      _currentCart.items[index] = current.copyWith(
        qty: parsed,
        discountLine: discountAmount,
      );
    });
  }

  void _applyInlineLineDiscountChanged(int index, String text) {
    if (index < 0 || index >= _currentCart.items.length) return;
    _updateCurrentCart(() {
      if (index < 0 || index >= _currentCart.items.length) return;
      final current = _currentCart.items[index];
      final discountAmount = _computeLineDiscountAmount(
        qty: current.qty,
        unitPrice: current.unitPrice,
        type: _inlineLineDiscountType,
        rawText: text,
      );
      _currentCart.items[index] = current.copyWith(discountLine: discountAmount);
    });
  }

  Future<List<String>> _missingElectronicInvoiceRequirements({
    required bool includeItbis,
  }) async {
    final missing = <String>[];
    final client = _currentCart.selectedClient;

    if (client == null) {
      missing.add('Cliente');
    } else {
      final rnc = (client.rnc ?? '').trim();
      if (rnc.isEmpty) missing.add('RNC del cliente');
    }

    if (includeItbis && !_currentCart.itbisEnabled) {
      missing.add('ITBIS');
    }

    final company =
        _electronicCompany ?? await ElectronicCompanyRepository.getOrCreate();
    final empresaConfig = await EmpresaService.getEmpresaConfig();
    if (!mounted) return missing;
    if (_electronicCompany?.updatedAtMs != company.updatedAtMs) {
      setState(() => _electronicCompany = company);
    }
    if (company.automaticEmission != 1) {
      missing.add('Emisión automática e-CF');
    }
    missing.addAll(empresaConfig.missingElectronicInvoicingFields());

    return missing;
  }

  Future<bool> _canEnableElectronicInvoiceOrNotify() async {
    if (!_isElectronicInvoicingFeatureEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'La facturación electrónica está desactivada en configuración.',
          ),
          backgroundColor: scheme.error,
        ),
      );
      return false;
    }

    final missing = await _missingElectronicInvoiceRequirements(
      includeItbis: false,
    );

    if (missing.isEmpty) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No se puede activar e-CF. Falta: ${missing.join(', ')}.',
        ),
        backgroundColor: scheme.error,
      ),
    );
    return false;
  }

  Future<bool> _canProceedWithElectronicInvoiceOrNotify() async {
    if (!_currentCart.electronicInvoiceEnabled) return true;

    final missing = await _missingElectronicInvoiceRequirements(
      includeItbis: true,
    );

    if (missing.isEmpty) return true;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No se puede continuar con e-CF. Falta: ${missing.join(', ')}.',
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
    if (_isProcessingSaleExecution) {
      debugPrint(
        'PAYMENT_EXECUTION_SKIPPED reason=locked time=${DateTime.now().millisecondsSinceEpoch}',
      );
      return;
    }
    if (_currentCart.items.isEmpty) return;

    _isProcessingSaleExecution = true;
    try {
      // Flujo profesional: no permitir ventas sin turno abierto.
      final activeShiftId = await _ensureActiveShiftOrRedirect(
        showMessage: true,
      );
      if (activeShiftId == null) {
        return;
      }

      if (!await _canProceedWithElectronicInvoiceOrNotify()) return;

      final canCharge = await _authorizeAction(
        AppActions.chargeSale,
        resourceType: 'sale',
        resourceId: _currentCart.ticketId?.toString(),
      );
      if (!canCharge) return;

      await _setSalesDocumentType(_SalesDocumentType.consumidorFinal);
      if (!mounted) return;

      // Importante: usar las funciones del carrito como fuente única.
      // Evita doble descuento (bug: totales guardados/impresos en 0).
      final totalDiscount = _currentCart.calculateTotalDiscountsCombined();
      final subtotalAfterDiscount = _currentCart
          .calculateSubtotalAfterDiscount();
      final itbisAmount = _currentCart.calculateItbis();
      final total = _currentCart.calculateTotal();
      final cartFingerprint = _buildCurrentCartFingerprint(total);
      final configuredChargeOutputMode = ref
          .read(businessSettingsProvider)
          .defaultChargeOutputMode;
      final paymentResult = await _presentDialog<Map<String, dynamic>>(
        builder: (context) => payment.PaymentDialog(
          total: total,
          initialPrintTicket: initialPrintTicket,
          allowInvoicePdfDownload: true,
          initialChargeOutputMode: configuredChargeOutputMode,
          cartFingerprint: cartFingerprint,
          selectedClient: _currentCart.selectedClient,
          initialDocumentType: payment.PaymentDocumentType.consumidorFinal,
          allowElectronicInvoiceOption: _isElectronicInvoicingFeatureEnabled,
          onDocumentTypeChanged: _setPaymentDocumentType,
          onSelectClient: _showClientPicker,
        ),
      );

      if (!mounted || paymentResult == null) return;

      final paymentRequestId = (paymentResult['paymentRequestId'] as String?)
          ?.trim();
      final triggerSource =
          (paymentResult['triggerSource'] as String?)?.trim() ?? 'unknown';
      debugPrint(
        'PAYMENT_TRIGGER source=$triggerSource time=${DateTime.now().millisecondsSinceEpoch} cart=$cartFingerprint request=${paymentRequestId ?? 'na'}',
      );

      if (paymentRequestId != null && paymentRequestId.isNotEmpty) {
        if (_processedPaymentRequestIds.contains(paymentRequestId)) {
          debugPrint(
            'PAYMENT_EXECUTION_SKIPPED reason=duplicate_request request=$paymentRequestId cart=$cartFingerprint',
          );
          return;
        }
        _processedPaymentRequestIds.add(paymentRequestId);
        if (_processedPaymentRequestIds.length > 120) {
          _processedPaymentRequestIds.remove(_processedPaymentRequestIds.first);
        }
      }

      final activeShiftIdAfterDialog = await _ensureActiveShiftOrRedirect(
        showMessage: true,
      );
      if (activeShiftIdAfterDialog == null) return;

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

      final selectedDocumentType =
          paymentResult['documentType'] as payment.PaymentDocumentType? ??
          payment.PaymentDocumentType.consumidorFinal;
      if (selectedDocumentType == payment.PaymentDocumentType.cotizacion) {
        await _saveAsQuote(paymentResult: paymentResult);
        return;
      }
      final method = paymentResult['method'] as payment.PaymentMethod;
      final resolvedKind = kind;
      final receivedAmountRaw =
          (paymentResult['received'] as num?)?.toDouble() ?? total;
      final changeAmountRaw =
          (paymentResult['change'] as num?)?.toDouble() ?? 0.0;
      final bool isCreditPayment = method == payment.PaymentMethod.credit;
      final receivedAmount = isCreditPayment ? 0.0 : receivedAmountRaw;
      final changeAmount = isCreditPayment ? 0.0 : changeAmountRaw;
      final shouldPrint = paymentResult['printTicket'] == true;
      final shouldDownloadInvoicePdf =
          paymentResult['downloadInvoicePdf'] == true &&
          resolvedKind == SaleKind.invoice;
      final shouldAutoOpenDrawerOnCharge =
          await _shouldAutoOpenDrawerWithoutTicket();

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

      final localCode =
          (paymentRequestId != null && paymentRequestId.isNotEmpty)
          ? _buildIdempotentLocalCode(resolvedKind, paymentRequestId)
          : await SalesRepository.generateNextLocalCode(resolvedKind);
      String? electronicInvoiceCode;
      String? electronicDocumentType;
      if (_currentCart.electronicInvoiceEnabled) {
        electronicDocumentType = 'eCF';
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
      final mixedCashInput = (paymentResult['cash'] as num?)?.toDouble() ?? 0.0;
      final mixedCardInput = (paymentResult['card'] as num?)?.toDouble() ?? 0.0;
      final mixedTransferInput =
          (paymentResult['transfer'] as num?)?.toDouble() ?? 0.0;
      final paymentCashAmount = switch (method) {
        payment.PaymentMethod.cash => total,
        payment.PaymentMethod.mixed => math.max(
          0.0,
          mixedCashInput - changeAmount,
        ),
        _ => 0.0,
      };
      final paymentCardAmount = switch (method) {
        payment.PaymentMethod.card => total,
        payment.PaymentMethod.mixed => mixedCardInput,
        _ => 0.0,
      };
      final paymentTransferAmount = switch (method) {
        payment.PaymentMethod.transfer => total,
        payment.PaymentMethod.mixed => mixedTransferInput,
        _ => 0.0,
      };

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
      _cartPersistenceTimer?.cancel();
      _cartPersistenceTimer = null;
      final int? tempCartIdToDelete = _currentCart.tempCartId;
      final int? ticketIdToDelete = _currentCart.ticketId;
      final int cartIndexToRemove = _currentCartIndex;
      try {
        if (isLayaway) {
          saleId = await LayawayRepository.createLayawaySale(
            localCode: localCode,
            kind: resolvedKind,
            items: itemsPayload,
            itbisEnabled: _currentCart.itbisEnabled,
            itbisRate: _currentCart.itbisRate,
            discountTotal: totalDiscount,
            subtotalOverride: subtotalAfterDiscount,
            itbisAmountOverride: itbisAmount,
            totalOverride: total,
            electronicInvoiceEnabled: _currentCart.electronicInvoiceEnabled,
            electronicInvoiceCode: electronicInvoiceCode,
            electronicDocumentType: electronicDocumentType,
            sessionId: activeShiftIdAfterDialog,
            customerId: _currentCart.selectedClient?.id,
            customerName: _currentCart.selectedClient?.nombre,
            customerPhone: _currentCart.selectedClient?.telefono,
            initialPayment: receivedAmount,
            note: paymentResult['note'] as String?,
            enforceLocalCodeIdempotency:
                paymentRequestId != null && paymentRequestId.isNotEmpty,
          );
        } else {
          saleId = await SalesRepository.createSale(
            localCode: localCode,
            kind: resolvedKind,
            items: itemsPayload,
            itbisEnabled: _currentCart.itbisEnabled,
            itbisRate: _currentCart.itbisRate,
            discountTotal: totalDiscount,
            subtotalOverride: subtotalAfterDiscount,
            itbisAmountOverride: itbisAmount,
            totalOverride: total,
            paymentMethod: paymentMethodStr,
            paymentCashAmount: paymentCashAmount,
            paymentCardAmount: paymentCardAmount,
            paymentTransferAmount: paymentTransferAmount,
            sessionId: activeShiftIdAfterDialog,
            customerId: _currentCart.selectedClient?.id,
            customerName: _currentCart.selectedClient?.nombre,
            customerPhone: _currentCart.selectedClient?.telefono,
            electronicInvoiceCode: electronicInvoiceCode,
            electronicDocumentType: electronicDocumentType,
            electronicInvoiceEnabled: _currentCart.electronicInvoiceEnabled,
            paidAmount: receivedAmount,
            changeAmount: changeAmount > 0 ? changeAmount : 0,
            enforceLocalCodeIdempotency:
                paymentRequestId != null && paymentRequestId.isNotEmpty,
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
            kind: resolvedKind,
            items: itemsPayload,
            allowNegativeStock: true,
            itbisEnabled: _currentCart.itbisEnabled,
            itbisRate: _currentCart.itbisRate,
            discountTotal: totalDiscount,
            subtotalOverride: subtotalAfterDiscount,
            itbisAmountOverride: itbisAmount,
            totalOverride: total,
            paymentMethod: paymentMethodStr,
            paymentCashAmount: paymentCashAmount,
            paymentCardAmount: paymentCardAmount,
            paymentTransferAmount: paymentTransferAmount,
            sessionId: activeShiftIdAfterDialog,
            customerId: _currentCart.selectedClient?.id,
            customerName: _currentCart.selectedClient?.nombre,
            customerPhone: _currentCart.selectedClient?.telefono,
            electronicInvoiceCode: electronicInvoiceCode,
            electronicDocumentType: electronicDocumentType,
            electronicInvoiceEnabled: _currentCart.electronicInvoiceEnabled,
            paidAmount: receivedAmount,
            changeAmount: changeAmount > 0 ? changeAmount : 0,
            enforceLocalCodeIdempotency:
                paymentRequestId != null && paymentRequestId.isNotEmpty,
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
        _rebuildQtyIndexForCurrentCart();
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
      unawaited(_deletePendingTicketFromDatabase(ticketIdToDelete));
      if (shouldPrint ||
          shouldDownloadInvoicePdf ||
          shouldAutoOpenDrawerOnCharge) {
        unawaited(
          _runSaleOutputs(
            saleId: saleId,
            shouldPrint: shouldPrint,
            shouldDownloadInvoicePdf: shouldDownloadInvoicePdf,
            shouldAutoOpenDrawerWithoutTicket: shouldAutoOpenDrawerOnCharge,
            isLayaway: isLayaway,
            receivedAmount: receivedAmount,
          ),
        );
      }
    } finally {
      _isProcessingSaleExecution = false;
    }
  }

  String _buildCurrentCartFingerprint(double total) {
    final itemTokens = _currentCart.items
        .map(
          (item) =>
              '${item.productId ?? item.productCodeSnapshot}|${item.qty.toStringAsFixed(3)}|${item.unitPrice.toStringAsFixed(2)}|${item.discountLine.toStringAsFixed(2)}',
        )
        .join(';');
    return 'ticket:${_currentCart.ticketId ?? 'na'}|items:${_currentCart.items.length}|total:${total.toStringAsFixed(2)}|hash:${itemTokens.hashCode.abs()}';
  }

  String _buildCartPersistenceSignature(_Cart cart) {
    final sortedItemTokens =
        cart.items
            .map(
              (item) =>
                  '${item.productId ?? item.productCodeSnapshot}|${item.productCodeSnapshot}|${item.productNameSnapshot}|${item.qty.toStringAsFixed(3)}|${item.unitPrice.toStringAsFixed(2)}|${item.discountLine.toStringAsFixed(2)}|${item.totalLine.toStringAsFixed(2)}',
            )
            .toList()
          ..sort();

    final clientToken = cart.selectedClient?.id?.toString() ?? 'no-client';
    final nameToken = cart.name.trim().toLowerCase();

    return [
      nameToken,
      clientToken,
      cart.discount.toStringAsFixed(2),
      cart.itbisEnabled ? 'itbis:1' : 'itbis:0',
      cart.itbisRate.toStringAsFixed(4),
      cart.electronicInvoiceEnabled ? 'electronic:1' : 'electronic:0',
      cart.discountTotalType ?? 'no-discount-type',
      (cart.discountTotalValue ?? 0).toStringAsFixed(2),
      ...sortedItemTokens,
    ].join('||');
  }

  String _buildCartPersistenceToken(_Cart cart) {
    // Importante: NO incluir tempCartId en modo save, porque cambia tras el primer guardado
    // y eso produciría escrituras redundantes.
    if (cart.ticketId != null) {
      final hasTemp = cart.tempCartId != null;
      return 'mode:ticket|ticket:${cart.ticketId}|hasTemp:${hasTemp ? 1 : 0}';
    }
    if (cart.items.isEmpty) {
      return 'mode:empty|temp:${cart.tempCartId ?? 0}';
    }
    return 'mode:save|${_buildCartPersistenceSignature(cart)}';
  }

  String _buildIdempotentLocalCode(String kind, String paymentRequestId) {
    final normalized = paymentRequestId
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase();
    final token = normalized.isEmpty
        ? DateTime.now().millisecondsSinceEpoch.toString()
        : normalized;
    final shortToken = token.length > 22
        ? token.substring(token.length - 22)
        : token;
    final prefix = kind == SaleKind.invoice ? 'V' : 'S';
    return '$prefix-IDEM-$shortToken';
  }

  Future<bool> _shouldAutoOpenDrawerWithoutTicket() async {
    try {
      final settings = await PrinterSettingsRepository.getOrCreate();
      if (settings.autoOpenDrawerOnChargeWithoutTicket != 1) return false;
      final printerName = (settings.selectedPrinterName ?? '').trim();
      return printerName.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _downloadInvoiceLetterPdf(
    legacy_sales.SaleModel sale,
    List<legacy_sales.SaleItemModel> items,
  ) async {
    final business = await BusinessSettingsRepository().loadSettings();
    final printerSettings = await PrinterSettingsRepository.getOrCreate();

    final cashierName = await SessionManager.displayName() ?? 'Cajero';
    final bytes = await InvoiceLetterPdf.generate(
      sale: sale,
      items: items,
      business: business,
      brandColorArgb: scheme.primary.value,
      cashierName: cashierName,
      warrantyPolicy: printerSettings.warrantyPolicy,
      footerMessage: printerSettings.footerMessage,
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

  Future<void> _saveAsQuote({Map<String, dynamic>? paymentResult}) async {
    final canQuote = await _authorizeAction(
      AppActions.createQuote,
      resourceType: 'quote',
      resourceId: _currentCart.ticketId?.toString(),
    );
    if (!canQuote) return;

    if (paymentResult != null) {
      final selectedClient =
          paymentResult['selectedClient'] as ClientModel? ??
          _currentCart.selectedClient;
      if (selectedClient == null || selectedClient.id == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Debe seleccionar un cliente para la cotización',
            ),
            backgroundColor: status.error,
          ),
        );
        return;
      }

      final quoteItems = _currentCart.items
          .map(
            (item) => QuoteItemModel(
              quoteId: 0,
              productId: item.productId,
              productCode: item.productCodeSnapshot,
              productName: item.productNameSnapshot,
              description: item.productNameSnapshot,
              qty: item.qty,
              price: item.unitPrice,
              unitPrice: item.unitPrice,
              cost: item.purchasePriceSnapshot,
              discountLine: item.discountLine,
              totalLine: (item.qty * item.unitPrice) - item.discountLine,
            ),
          )
          .toList();

      final quoteOutputMode =
          paymentResult['quoteOutputMode'] as payment.QuoteOutputMode? ??
          payment.QuoteOutputMode.save;
      final validDays =
          (paymentResult['quoteValidDays'] as num?)?.toInt() ?? 15;
      final quoteNotes = (paymentResult['quoteNotes'] as String?)?.trim();

      try {
        final quoteId = await QuotesRepository().saveQuote(
          clientId: selectedClient.id!,
          userId: null,
          ticketName: _currentCart.name,
          subtotal: _currentCart.calculateSubtotalAfterDiscount(),
          itbisEnabled: _currentCart.itbisEnabled,
          itbisRate: _currentCart.itbisRate,
          itbisAmount: _currentCart.calculateItbis(),
          discountTotal:
              _currentCart.discount + _currentCart.calculateTotalDiscount(),
          total: _currentCart.calculateTotal(),
          notes: quoteNotes?.isEmpty == true ? null : quoteNotes,
          items: quoteItems,
        );

        final shouldPrint = quoteOutputMode == payment.QuoteOutputMode.print;
        final shouldPreview =
            quoteOutputMode == payment.QuoteOutputMode.preview;
        if (shouldPrint || shouldPreview) {
          final quoteDetail = await QuotesRepository().getQuoteById(quoteId);
          if (quoteDetail != null) {
            final business = await SettingsRepository.getBusinessInfo();
            final settings = await PrinterSettingsRepository.getOrCreate();
            if (shouldPreview) {
              if (!mounted) return;
              await QuotePrinter.showPreview(
                context: context,
                quote: quoteDetail.quote,
                items: quoteDetail.items,
                clientName: quoteDetail.clientName,
                clientPhone: quoteDetail.clientPhone,
                clientRnc: quoteDetail.clientRnc,
                business: business,
                validDays: validDays,
              );
            } else {
              await QuotePrinter.printQuote(
                quote: quoteDetail.quote,
                items: quoteDetail.items,
                clientName: quoteDetail.clientName,
                clientPhone: quoteDetail.clientPhone,
                clientRnc: quoteDetail.clientRnc,
                business: business,
                settings: settings,
                validDays: validDays,
              );
            }
          }
        }

        await _deleteCurrentCartFromDatabase();

        if (!mounted) return;
        setState(() {
          _currentCart.clear();
          _selectedCartItemIndex = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              shouldPrint
                  ? 'Cotización guardada e impresa'
                  : (shouldPreview
                        ? 'Cotización guardada y lista para vista previa'
                        : 'Cotización guardada'),
            ),
            backgroundColor: status.success,
          ),
        );
      } catch (e, st) {
        if (!mounted) return;
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: () => _saveAsQuote(paymentResult: paymentResult),
          module: 'sales/quote/save',
        );
      }
      return;
    }

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
    _inlineQtyController.dispose();
    _inlineLineDiscountController.dispose();
    _inlineQtyFocusNode.dispose();
    _inlineLineDiscountFocusNode.dispose();
    _inlineTotalDiscountController.dispose();
    _inlineTotalDiscountFocusNode.dispose();
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
    ref.watch(
      businessSettingsProvider.select(
        (settings) => settings.electronicInvoicingEnabled,
      ),
    );
    ref.listen<bool>(
      businessSettingsProvider.select(
        (settings) => settings.electronicInvoicingEnabled,
      ),
      (previous, next) {
        if (previous == true && !next) {
          _disableElectronicInvoicingForAllCarts();
        }
      },
    );
    final cashSessionState = ref.watch(activeSessionControllerProvider);
    final currentSessionId = cashSessionState.valueOrNull?.shiftId;
    final isCashSessionResolved = cashSessionState is AsyncData;
    final cashIsOpen = currentSessionId != null;
    final showCashClosedOverlay = isCashSessionResolved && !cashIsOpen;

    if (_previousCashOpen == null) {
      // Evitar marcar como "cerrado" durante loading.
      _previousCashOpen = isCashSessionResolved ? cashIsOpen : true;
    } else if (isCashSessionResolved &&
        _previousCashOpen == true &&
        !cashIsOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // Limpieza inmediata del panel/columna de detalle.
        // No redirigir automáticamente desde build para evitar saltos de ruta
        // inesperados mientras el usuario está en pantalla.
        setState(() {
          _selectedCartItemIndex = null;
        });
      });
    }
    if (isCashSessionResolved) {
      _previousCashOpen = cashIsOpen;
    }

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
                final index = _selectedCartItemIndex!;
                _openInlineItemEditor(
                  _currentCart.items[index],
                  index,
                  focus: _InlineItemFocus.discount,
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
                  final panelMargin = constraints.maxWidth < 1150 ? 12.0 : 16.0;
                  final panelGap = constraints.maxWidth < 1180 ? 32.0 : 42.0;
                  final theme = Theme.of(context);
                  final tokens =
                      theme.extension<AppTokens>() ?? AppTokens.defaultTokens;
                  final salesProducts = theme.extension<SalesProductsTheme>();
                  final gridBackground =
                      (salesProducts?.gridBackgroundColor.opacity ?? 0) == 0
                      ? theme.scaffoldBackgroundColor
                      : salesProducts!.gridBackgroundColor;
                  final gridCardColor =
                      (salesProducts?.cardBackgroundColor.opacity ?? 0) == 0
                      ? theme.cardColor
                      : salesProducts!.cardBackgroundColor;
                  final gridBorderColor =
                      (salesProducts?.cardBorderColor.opacity ?? 0) == 0
                      ? tokens.outline
                      : salesProducts!.cardBorderColor;
                  final gridTextColor =
                      (salesProducts?.cardTextColor.opacity ?? 0) == 0
                      ? theme.colorScheme.onSurface
                      : salesProducts!.cardTextColor;
                  final gridMutedTextColor = ColorUtils.ensureReadableColor(
                    gridTextColor.withOpacity(0.7),
                    gridCardColor,
                    minRatio: 3.0,
                  );

                  return Stack(
                    children: [
                      Container(
                        color: gridBackground,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  0,
                                  12,
                                ),
                                child: Column(
                                  children: [
                                    _build3DControlBar(),
                                    const SizedBox(height: 12),
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: gridCardColor,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: gridBorderColor,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: theme.shadowColor
                                                  .withOpacity(0.04),
                                              blurRadius: 16,
                                              offset: const Offset(0, 6),
                                            ),
                                          ],
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Column(
                                          children: [
                                            Padding(
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                    16,
                                                    14,
                                                    16,
                                                    10,
                                                  ),
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          'Catalogo de productos',
                                                          style: TextStyle(
                                                            color:
                                                                gridTextColor,
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Text(
                                                          '${_filteredProducts().length} productos visibles',
                                                          style: TextStyle(
                                                            color:
                                                                gridMutedTextColor,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: scheme
                                                          .surfaceContainerHighest
                                                          .withOpacity(0.55),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            999,
                                                          ),
                                                    ),
                                                    child: Text(
                                                      'Vista compacta',
                                                      style: TextStyle(
                                                        color:
                                                            gridMutedTextColor,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(
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
                                                            if (products
                                                                .isEmpty) {
                                                              return Center(
                                                                child: Column(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .inventory_2_outlined,
                                                                      size: 64,
                                                                      color: gridMutedTextColor
                                                                          .withOpacity(
                                                                            0.5,
                                                                          ),
                                                                    ),
                                                                    const SizedBox(
                                                                      height:
                                                                          12,
                                                                    ),
                                                                    Text(
                                                                      'No hay productos disponibles',
                                                                      style: TextStyle(
                                                                        color:
                                                                            gridTextColor,
                                                                        fontSize:
                                                                            18,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                      ),
                                                                    ),
                                                                    const SizedBox(
                                                                      height: 6,
                                                                    ),
                                                                    Text(
                                                                      'Intenta buscar con otro termino o cambia el filtro',
                                                                      style: TextStyle(
                                                                        color:
                                                                            gridMutedTextColor,
                                                                        fontSize:
                                                                            13,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              );
                                                            }
                                                            return Padding(
                                                              padding:
                                                                  const EdgeInsets.fromLTRB(
                                                                    12,
                                                                    0,
                                                                    12,
                                                                    72,
                                                                  ),
                                                              child: LayoutBuilder(
                                                                builder:
                                                                    (
                                                                      context,
                                                                      constraints,
                                                                    ) {
                                                                      final tileHeight = _productTileHeightFor(
                                                                        constraints
                                                                            .maxWidth,
                                                                      );
                                                                      double
                                                                      maxExtent = stableMaxCrossAxisExtent(
                                                                        availableWidth:
                                                                            constraints.maxWidth,
                                                                        desiredMaxExtent:
                                                                            _productTileMaxExtent,
                                                                        spacing:
                                                                            _gridCrossSpacing,
                                                                        minExtent:
                                                                            240,
                                                                      );
                                                                      if (!maxExtent
                                                                              .isFinite ||
                                                                          maxExtent <=
                                                                              0) {
                                                                        maxExtent =
                                                                            _productTileMaxExtent;
                                                                      }
                                                                      return GridView.builder(
                                                                        padding: const EdgeInsets.only(
                                                                          bottom:
                                                                              8,
                                                                        ),
                                                                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                                                          maxCrossAxisExtent:
                                                                              maxExtent,
                                                                          mainAxisExtent:
                                                                              tileHeight,
                                                                          crossAxisSpacing:
                                                                              _gridCrossSpacing,
                                                                          mainAxisSpacing:
                                                                              _gridMainSpacing,
                                                                        ),
                                                                        itemCount:
                                                                            products.length,
                                                                        itemBuilder:
                                                                            (
                                                                              context,
                                                                              index,
                                                                            ) {
                                                                              final product = products[index];
                                                                              return _buildProductCard(
                                                                                product,
                                                                                index: index,
                                                                                cardSize: tileHeight,
                                                                              );
                                                                            },
                                                                      );
                                                                    },
                                                              ),
                                                            );
                                                          })(),
                                                  ),
                                                  Positioned(
                                                    bottom: 0,
                                                    left: 0,
                                                    right: 0,
                                                    child:
                                                        _buildTicketsFooter(),
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
                            SizedBox(width: panelGap),
                            ConstrainedBox(
                              constraints: ticketPanelConstraints,
                              child: Container(
                                margin: EdgeInsets.fromLTRB(
                                  0,
                                  0,
                                  panelMargin,
                                  panelMargin,
                                ),
                                decoration: BoxDecoration(
                                  // Ligeramente más claro/suave que el fondo principal.
                                  color: Color.alphaBlend(
                                    scheme.onSurface.withOpacity(0.02),
                                    theme.scaffoldBackgroundColor,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: tokens.outline),
                                  boxShadow: [
                                    BoxShadow(
                                      color: theme.shadowColor.withOpacity(
                                        0.12,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: _buildTicketPanel(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (showCashClosedOverlay) _buildCashClosedOverlay(),
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
                  'SESIÓN NO INICIADA',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Debes abrir caja para iniciar tu sesión\nantes de poder realizar ventas.',
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
                      await _ensureSessionBootstrap(force: true);
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

  Widget _buildProductCard(
    ProductModel product, {
    required int index,
    required double cardSize,
  }) {
    final qtyInCart = _qtyInCart(product.id);
    final effectiveStock = product.stock - qtyInCart;
    final isLowStock = effectiveStock > 0 && effectiveStock <= 10;
    final isOutOfStock = effectiveStock <= 0;
    final stockColor = isOutOfStock
        ? scheme.error
        : (isLowStock ? status.warning : scheme.primary.withOpacity(0.85));
    final theme = Theme.of(context);
    final salesProducts = theme.extension<SalesProductsTheme>();
    final rawPrice = product.salePrice;
    final formattedPrice = (rawPrice % 1 == 0)
        ? rawPrice.toStringAsFixed(0)
        : rawPrice.toStringAsFixed(2);
    final isHovered = _hoveredProductIndexes.contains(index);
    final stockLabel = isOutOfStock
        ? 'Sin stock'
        : 'Stock ${effectiveStock.toInt()}';
    final cardColor = isHovered
        ? (salesProducts?.cardAltBackgroundColor.opacity ?? 0) == 0
              ? scheme.surface
              : salesProducts!.cardAltBackgroundColor
        : (salesProducts?.cardBackgroundColor.opacity ?? 0) == 0
        ? scheme.surface.withOpacity(0.7)
        : salesProducts!.cardBackgroundColor;
    final cardBorderColor = isHovered
        ? (salesProducts?.cardAltBorderColor.opacity ?? 0) == 0
              ? scheme.primary.withOpacity(0.22)
              : salesProducts!.cardAltBorderColor
        : (salesProducts?.cardBorderColor.opacity ?? 0) == 0
        ? scheme.outlineVariant
        : salesProducts!.cardBorderColor;
    final cardTextColor = isHovered
        ? (salesProducts?.cardAltTextColor.opacity ?? 0) == 0
              ? scheme.onSurface
              : salesProducts!.cardAltTextColor
        : (salesProducts?.cardTextColor.opacity ?? 0) == 0
        ? scheme.onSurface
        : salesProducts!.cardTextColor;
    final priceColor = (salesProducts?.priceColor.opacity ?? 0) == 0
        ? scheme.onSurface
        : salesProducts!.priceColor;

    return MouseRegion(
      onEnter: (_) =>
          _setHoverStateDeferred(_hoveredProductIndexes, index, true),
      onExit: (_) =>
          _setHoverStateDeferred(_hoveredProductIndexes, index, false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: cardColor,
          border: Border.all(color: cardBorderColor),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withOpacity(isHovered ? 0.07 : 0.03),
              blurRadius: isHovered ? 14 : 10,
              offset: Offset(0, isHovered ? 5 : 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Material(
            color: transparent,
            child: InkWell(
              onTap: isOutOfStock ? null : () => _addProductToCart(product),
              hoverColor: theme.hoverColor,
              child: SizedBox(
                height: cardSize,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: cardBorderColor),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ProductThumbnail.fromProduct(
                              product,
                              width: 54,
                              height: 54,
                              borderRadius: BorderRadius.circular(10),
                              showBorder: false,
                            ),
                          ),
                          if (qtyInCart > 0)
                            Positioned(
                              top: -5,
                              right: -5,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: scheme.primary.withOpacity(0.18),
                                  ),
                                ),
                                child: Text(
                                  qtyInCart.toInt().toString(),
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              product.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cardTextColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${product.code.toUpperCase()}  •  $stockLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: stockColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'RD\$',
                            style: TextStyle(
                              color: cardTextColor.withOpacity(0.72),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formattedPrice,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: priceColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              height: 1,
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
      scheme.surfaceContainerHighest.withOpacity(0.55),
    );
    final dropdownBorder = resolve(
      salesTheme?.controlBarDropdownBorderColor,
      scheme.outlineVariant,
    );
    final dropdownText = resolve(
      salesTheme?.controlBarDropdownTextColor,
      scheme.onSurface,
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
      padding: const EdgeInsets.only(right: 2),
      child: PopupMenuButton<String>(
        tooltip: 'Elegir categoría',
        offset: const Offset(0, 52),
        color: menuBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: dropdownBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: dropdownBorder, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.category_outlined, size: 18, color: dropdownText),
              const SizedBox(width: 6),
              Text(
                _selectedCategory ?? 'Categoría',
                style: TextStyle(
                  fontSize: 12.5,
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
    final salesTheme = Theme.of(context).extension<SalesPageTheme>();

    Color resolve(Color? c, Color fallback) {
      if (c == null || c.opacity == 0) return fallback;
      return c;
    }

    final tokens =
        Theme.of(context).extension<AppTokens>() ?? AppTokens.defaultTokens;
    final controlBarBackground = resolve(
      salesTheme?.controlBarBackgroundColor,
      tokens.panelBackground,
    );
    final controlBorder = resolve(
      salesTheme?.controlBarBorderColor,
      scheme.outlineVariant,
    );
    final controlContentBg = resolve(
      salesTheme?.controlBarContentBackgroundColor,
      scheme.surface,
    );
    final controlTextColor = resolve(
      salesTheme?.controlBarTextColor,
      scheme.onSurface,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isCompact = width < 980;

        final fieldTextColor = ColorUtils.ensureReadableColor(
          controlTextColor,
          controlContentBg,
        );

        final hintCandidate = controlTextColor.withOpacity(0.72);
        var hintColor = ColorUtils.ensureReadableColor(
          hintCandidate,
          controlContentBg,
          minRatio: 3.0,
        );
        final luminance = hintColor.computeLuminance();
        if (luminance < 0.02 || luminance > 0.98) {
          hintColor = hintColor.withOpacity(0.65);
        }

        final searchBarWidth = isCompact ? double.infinity : (width * 0.96);

        final outerPadding = EdgeInsets.all((width * 0.007).clamp(6.0, 8.0));
        final barHeight = isCompact ? 54.0 : 56.0;
        final radius = 16.0;
        final iconSize = isCompact ? 18.0 : 20.0;
        final textSize = 13.5;
        final fieldVPad = 15.0;

        return Container(
          padding: outerPadding,
          decoration: BoxDecoration(
            color: controlBarBackground,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: controlBorder.withOpacity(0.32)),
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
                        color: Color.alphaBlend(
                          scheme.primary.withOpacity(0.015),
                          controlContentBg,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: controlBorder.withOpacity(0.5),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(
                              context,
                            ).shadowColor.withOpacity(0.07),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 18),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Color.alphaBlend(
                                scheme.primary.withOpacity(0.08),
                                controlContentBg,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.search_rounded,
                              color: controlTextColor,
                              size: iconSize,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              focusNode: _searchFocusNode,
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.transparent,
                                hintText:
                                    'Buscar productos, codigo o categoria',
                                hintStyle: TextStyle(
                                  color: hintColor,
                                  fontSize: textSize,
                                  fontWeight: FontWeight.w500,
                                ),
                                border: InputBorder.none,
                                isCollapsed: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
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
                                fontSize: textSize + 0.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 26,
                            color: controlBorder.withOpacity(0.32),
                          ),
                          const SizedBox(width: 8),
                          _buildCategoryDropdown(),
                          const SizedBox(width: 12),
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

    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: contrastColor),
        label: Text(
          label,
          style: TextStyle(
            color: contrastColor,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return Color.alphaBlend(scheme.primary.withOpacity(0.08), color);
            }
            return color;
          }),
          foregroundColor: WidgetStatePropertyAll(contrastColor),
          side: WidgetStatePropertyAll(
            BorderSide(color: borderColor ?? scheme.outlineVariant),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 0),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          elevation: const WidgetStatePropertyAll(0),
          shadowColor: const WidgetStatePropertyAll(Colors.transparent),
          overlayColor: WidgetStatePropertyAll(
            Color.alphaBlend(scheme.primary.withOpacity(0.08), color),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(0, 42)),
        ),
      ),
    );
  }

  Widget _buildTicketsFooter() {
    final salesTheme = Theme.of(context).extension<SalesPageTheme>();
    Color resolve(Color? c, Color fallback) {
      if (c == null || c.opacity == 0) return fallback;
      return c;
    }

    final unifiedColor = resolve(
      salesTheme?.footerButtonsBackgroundColor,
      scheme.surface,
    );
    final unifiedTextColor = ColorUtils.ensureReadableColor(
      resolve(salesTheme?.footerButtonsTextColor, scheme.onSurface),
      unifiedColor,
      minRatio: 4.5,
    );
    final unifiedBorderColor = resolve(
      salesTheme?.footerButtonsBorderColor,
      scheme.outlineVariant,
    );
    return Container(
      height: _ticketsFooterHeight,
      decoration: BoxDecoration(
        color: Color.alphaBlend(unifiedColor.withOpacity(0.18), scheme.surface),
        border: Border(top: BorderSide(color: unifiedBorderColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cashActions = <Widget>[
              _buildCompactOperationButton(
                icon: Icons.add_circle_outline,
                label: 'Ingreso',
                color: unifiedColor,
                foregroundColor: unifiedTextColor,
                borderColor: unifiedBorderColor,
                onPressed: () => _openCashMovement(CashMovementType.income),
              ),
              const SizedBox(width: 8),
              _buildCompactOperationButton(
                icon: Icons.remove_circle_outline,
                label: 'Gastos',
                color: unifiedColor,
                foregroundColor: unifiedTextColor,
                borderColor: unifiedBorderColor,
                onPressed: () => _openCashMovement(CashMovementType.outcome),
              ),
            ];

            final secondaryActions = <Widget>[
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
              const SizedBox(width: 8),
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
            ];

            final divider = Container(
              width: 1,
              height: 28,
              color: unifiedBorderColor.withOpacity(0.75),
            );

            if (constraints.maxWidth >= 760) {
              return SizedBox(
                width: constraints.maxWidth,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: cashActions,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        divider,
                        const SizedBox(width: 14),
                        ...secondaryActions,
                      ],
                    ),
                  ],
                ),
              );
            }

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    ...cashActions,
                    const SizedBox(width: 14),
                    divider,
                    const SizedBox(width: 14),
                    ...secondaryActions,
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Panel de ticket refactorizado con 3 cards profesionales
  Widget _buildTicketPanel() {
    final theme = Theme.of(context);
    final tokens = theme.extension<AppTokens>() ?? AppTokens.defaultTokens;
    final dividerColor = tokens.outline.withOpacity(0.85);

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTicketHeaderCard(embedded: true),
          const SizedBox(height: 8),
          Divider(height: 1, color: dividerColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
            child: Row(
              children: [
                Text(
                  'Detalle',
                  style: TextStyle(
                    color: scheme.onSurface.withOpacity(0.92),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_currentCart.items.length} líneas',
                  style: TextStyle(
                    color: scheme.onSurface.withOpacity(0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildItemsListCard()),
          const SizedBox(height: 8),
          Divider(height: 1, color: dividerColor),
          _buildTotalAndActionsCard(embedded: true),
        ],
      ),
    );
  }

  /// CARD A: Ticket / Cliente
  Widget _buildTicketHeaderCard({bool embedded = false}) {
    final totalTickets = _carts.length;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    Color actionBackground(bool isHovered) {
      if (isDark) {
        final base = scheme.surfaceContainerHighest.withOpacity(0.18);
        final hover = scheme.surfaceContainerHighest.withOpacity(0.26);
        return isHovered ? hover : base;
      }

      final base = Color.alphaBlend(
        scheme.onSurface.withOpacity(0.02),
        scheme.surfaceContainerHighest,
      );
      final hover = Color.alphaBlend(
        scheme.primary.withOpacity(0.06),
        scheme.surfaceContainerHighest,
      );
      return isHovered ? hover : base;
    }

    Widget actionCard({
      required String id,
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool emphasize = false,
    }) {
      final isHovered = _hoveredTicketHeaderActions.contains(id);

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) =>
            _setHoverStateDeferred(_hoveredTicketHeaderActions, id, true),
        onExit: (_) =>
            _setHoverStateDeferred(_hoveredTicketHeaderActions, id, false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          transform: Matrix4.identity()..scale(isHovered ? 1.03 : 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: actionBackground(isHovered),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHovered
                  ? scheme.primary.withOpacity(0.22)
                  : scheme.outlineVariant,
            ),
            boxShadow: [
              if (isHovered)
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: emphasize ? 13 : 12,
                          fontWeight: emphasize
                              ? FontWeight.w700
                              : FontWeight.w600,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    Widget iconActionButton({
      required String id,
      required IconData icon,
      required VoidCallback onTap,
      String? tooltip,
    }) {
      final isHovered = _hoveredTicketHeaderActions.contains(id);

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) =>
            _setHoverStateDeferred(_hoveredTicketHeaderActions, id, true),
        onExit: (_) =>
            _setHoverStateDeferred(_hoveredTicketHeaderActions, id, false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          transform: Matrix4.identity()..scale(isHovered ? 1.03 : 1.0),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            color: actionBackground(isHovered),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHovered
                  ? scheme.primary.withOpacity(0.22)
                  : scheme.outlineVariant,
            ),
            boxShadow: [
              if (isHovered)
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Tooltip(
                message: tooltip ?? '',
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Center(
                    child: Icon(icon, size: 20, color: scheme.primary),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final content = LayoutBuilder(
      builder: (context, constraints) {
        final ticketSelector = actionCard(
          id: 'ticket-selector',
          icon: Icons.receipt_long_outlined,
          label: totalTickets == 1
              ? _currentCart.displayName
              : '${_currentCart.displayName} ($totalTickets)',
          onTap: _showTicketSelector,
          emphasize: true,
        );

        final actionButtons = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconActionButton(
              id: 'client-selector',
              icon: Icons.person_outline,
              onTap: _showClientPicker,
              tooltip: 'Cliente',
            ),
            const SizedBox(width: 6),
            iconActionButton(
              id: 'manual-sale',
              icon: Icons.edit_note,
              onTap: _showQuickItemDialog,
              tooltip: 'Venta manual',
            ),
          ],
        );

        final shouldStack =
            constraints.maxWidth > 0 && constraints.maxWidth < 290;

        if (shouldStack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ticketSelector,
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerRight, child: actionButtons),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: ticketSelector),
            const SizedBox(width: 6),
            actionButtons,
          ],
        );
      },
    );

    if (embedded) return content;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: content,
    );
  }

  /// CARD B: Detalle de la venta (lista scrollable)
  Widget _buildItemsListCard({bool embedded = false}) {
    const emptyKey = ValueKey<String>('ticket_items_empty');
    const listKey = ValueKey<String>('ticket_items_list');

    final listContent = _currentCart.items.isEmpty
        ? KeyedSubtree(key: emptyKey, child: _buildEmptyCartView())
        : embedded
        ? KeyedSubtree(
            key: listKey,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
              itemCount: _currentCart.items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 0),
              itemBuilder: (context, index) {
                final item = _currentCart.items[index];
                return _buildCartItemRow(item, index);
              },
            ),
          )
        : KeyedSubtree(
            key: listKey,
            child: Scrollbar(
              controller: _ticketItemsScrollController,
              thumbVisibility: true,
              child: ListView.separated(
                controller: _ticketItemsScrollController,
                primary: false,
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
                itemCount: _currentCart.items.length,
                separatorBuilder: (context, index) => const SizedBox(height: 0),
                itemBuilder: (context, index) {
                  final item = _currentCart.items[index];
                  return _buildCartItemRow(item, index);
                },
              ),
            ),
          );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: Tween(begin: 0.985, end: 1.0).animate(fade),
            child: child,
          ),
        );
      },
      child: listContent,
    );
  }

  Widget _buildEmptyCartView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight > 0 && constraints.maxHeight < 120;
        final iconSize = compact ? 40.0 : 48.0;
        final titleSize = compact ? 14.0 : 16.0;
        final subtitleSize = compact ? 11.0 : 12.0;
        final gap1 = compact ? 10.0 : 12.0;
        final gap2 = compact ? 4.0 : 6.0;

        return Center(
          child: Padding(
            padding: const EdgeInsets.all(18),
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
                    color: salesDetailTextColor.withOpacity(0.9),
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: gap2),
                Text(
                  'Agrega productos desde el catálogo',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: salesDetailTextColor.withOpacity(0.55),
                    fontSize: subtitleSize,
                    height: 1.2,
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
    final isEditing = _inlineEditCartItemIndex == index;
    final subtotal = (item.qty * item.unitPrice) - item.discountLine;
    final rowDividerColor = salesDetailBorderColor;

    if (isEditing) {
      _maybeSyncInlineItemControllers(item);
    }

    return InkWell(
      onTap: () => setState(() => _selectedCartItemIndex = index),
      onDoubleTap: () => _showEditItemDialog(item, index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withOpacity(0.055)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: scheme.primary.withOpacity(0.18), width: 1.2)
              : Border(bottom: BorderSide(color: rowDividerColor, width: 1)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (isEditing)
              _buildInlineQtyStepperEditor(index, compact: false)
            else
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '${item.qty.toInt()}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: salesDetailTextColor,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productNameSnapshot,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: salesDetailTextColor,
                      height: 1.15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.productCodeSnapshot}  •  Unitario ${CurrencyDisplay.format(item.unitPrice)}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: salesDetailMutedTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isEditing) ...[
                    const SizedBox(height: 8),
                    _buildInlineLineDiscountEditor(index, compact: true),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),

            if (!isEditing) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildCompactStepperButton(Icons.remove, () {
                    if (item.qty > 1) {
                      _updateCurrentCart(
                        () =>
                            _currentCart.updateQuantity(index, item.qty - 1),
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
              const SizedBox(width: 12),
            ],

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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    CurrencyDisplay.format(subtotal),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),

            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _updateCurrentCart(() {
                  if (_inlineEditCartItemIndex == index) {
                    _inlineEditCartItemIndex = null;
                  }
                  if (_selectedCartItemIndex == index) {
                    _selectedCartItemIndex = null;
                  }
                  _currentCart.removeItem(index);
                }),
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withOpacity(0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 14,
          color: salesDetailTextColor.withOpacity(0.86),
        ),
      ),
    );
  }

  void _maybeSyncInlineItemControllers(SaleItemModel item) {
    if (_inlineEditCartItemIndex == null) return;

    if (!_inlineQtyFocusNode.hasFocus) {
      final desired = _formatQtyForInlineEditor(item.qty);
      if (_inlineQtyController.text != desired) {
        _inlineQtyController.text = desired;
      }
    }

    if (!_inlineLineDiscountFocusNode.hasFocus) {
      final desired = item.discountLine > 0
          ? item.discountLine.toStringAsFixed(2)
          : '';
      if (_inlineLineDiscountController.text != desired) {
        _inlineLineDiscountController.text = desired;
      }
    }
  }

  Widget _buildInlineQtyStepperEditor(int index, {required bool compact}) {
    final height = compact ? 28.0 : 30.0;
    final fieldWidth = compact ? 46.0 : 54.0;
    final radius = compact ? 8.0 : 10.0;
    final iconSize = compact ? 16.0 : 18.0;
    final buttonColor = scheme.surfaceContainerHighest.withOpacity(0.55);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    void setQty(double qty) {
      final text = _formatQtyForInlineEditor(qty);
      _inlineQtyController.text = text;
      _inlineQtyController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: text.length,
      );
      _applyInlineQtyChanged(index, text);
    }

    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () {
              if (index < 0 || index >= _currentCart.items.length) return;
              final item = _currentCart.items[index];
              final next = (item.qty - 1).clamp(1.0, double.infinity);
              setQty(next);
            },
            borderRadius: BorderRadius.circular(radius),
            child: Container(
              width: height,
              height: height,
              decoration: BoxDecoration(
                color: buttonColor,
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Icon(
                Icons.remove,
                size: iconSize,
                color: salesDetailTextColor.withOpacity(0.86),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: fieldWidth,
            height: height,
            child: TextField(
              controller: _inlineQtyController,
              focusNode: _inlineQtyFocusNode,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d{0,3}'),
                ),
              ],
              style: TextStyle(
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w800,
                color: salesDetailTextColor,
                height: 1.0,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: compact ? 8 : 9,
                ),
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(
                  borderSide: BorderSide(color: scheme.primary.withOpacity(0.45)),
                ),
              ),
              onChanged: (value) => _applyInlineQtyChanged(index, value),
              onSubmitted: (value) => _applyInlineQtyChanged(index, value),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: () {
              if (index < 0 || index >= _currentCart.items.length) return;
              final item = _currentCart.items[index];
              setQty(item.qty + 1);
            },
            borderRadius: BorderRadius.circular(radius),
            child: Container(
              width: height,
              height: height,
              decoration: BoxDecoration(
                color: buttonColor,
                borderRadius: BorderRadius.circular(radius),
              ),
              child: Icon(
                Icons.add,
                size: iconSize,
                color: salesDetailTextColor.withOpacity(0.86),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineLineDiscountEditor(int index, {required bool compact}) {
    final height = compact ? 28.0 : 30.0;
    final fieldWidth = compact ? 82.0 : 96.0;
    final radius = compact ? 8.0 : 10.0;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );

    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ToggleButtons(
            isSelected: [
              _inlineLineDiscountType == DiscountType.percent,
              _inlineLineDiscountType == DiscountType.amount,
            ],
            onPressed: (i) {
              setState(() {
                _inlineLineDiscountType =
                    i == 0 ? DiscountType.percent : DiscountType.amount;
              });
              _applyInlineLineDiscountChanged(
                index,
                _inlineLineDiscountController.text,
              );
            },
            borderRadius: BorderRadius.circular(radius),
            constraints: BoxConstraints(minHeight: height, minWidth: 44),
            borderColor: scheme.outlineVariant,
            selectedBorderColor: scheme.primary.withOpacity(0.35),
            color: salesDetailMutedTextColor,
            selectedColor: scheme.primary,
            fillColor: scheme.primary.withOpacity(0.10),
            children: const [
              Text('%', style: TextStyle(fontWeight: FontWeight.w800)),
              Text('RD\$', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: fieldWidth,
            height: height,
            child: TextField(
              controller: _inlineLineDiscountController,
              focusNode: _inlineLineDiscountFocusNode,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: TextStyle(
                fontSize: compact ? 11.5 : 12.5,
                fontWeight: FontWeight.w800,
                color: salesDetailTextColor,
                height: 1.0,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: compact ? 8 : 9,
                ),
                border: border,
                enabledBorder: border,
                focusedBorder: border.copyWith(
                  borderSide: BorderSide(color: scheme.primary.withOpacity(0.45)),
                ),
              ),
              onChanged: (value) => _applyInlineLineDiscountChanged(index, value),
              onSubmitted: (value) =>
                  _applyInlineLineDiscountChanged(index, value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineTotalDiscountPanel() {
    final hasCurrentDiscount =
        (_currentCart.discountTotalValue ?? 0.0) > 0.0;
    final previewTotal = _computeInlineTotalDiscountPreviewTotal();
    final radius = 12.0;
    final height = 30.0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ToggleButtons(
                isSelected: [
                  _inlineTotalDiscountType == DiscountType.percent,
                  _inlineTotalDiscountType == DiscountType.amount,
                ],
                onPressed: (i) {
                  setState(() {
                    _inlineTotalDiscountType =
                        i == 0 ? DiscountType.percent : DiscountType.amount;
                  });
                },
                borderRadius: BorderRadius.circular(10),
                constraints: BoxConstraints(minHeight: height, minWidth: 48),
                borderColor: scheme.outlineVariant,
                selectedBorderColor: scheme.primary.withOpacity(0.35),
                color: salesDetailMutedTextColor,
                selectedColor: scheme.primary,
                fillColor: scheme.primary.withOpacity(0.10),
                children: const [
                  Text('%', style: TextStyle(fontWeight: FontWeight.w800)),
                  Text('RD\$', style: TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              const Spacer(),
              Text(
                CurrencyDisplay.format(previewTotal),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: scheme.primary,
                ),
              ),
              if (hasCurrentDiscount) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: _removeInlineTotalDiscount,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: scheme.error.withOpacity(0.85),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: height,
                  child: TextField(
                    controller: _inlineTotalDiscountController,
                    focusNode: _inlineTotalDiscountFocusNode,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: salesDetailTextColor,
                      height: 1.0,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: scheme.primary.withOpacity(0.45),
                        ),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => unawaited(_applyInlineTotalDiscount()),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => unawaited(_applyInlineTotalDiscount()),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: height,
                  height: height,
                  decoration: BoxDecoration(
                    color: scheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: scheme.primary.withOpacity(0.22)),
                  ),
                  child: Icon(
                    Icons.check,
                    size: 18,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalAndActionsCard({bool embedded = false}) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Resumen de venta',
                  style: TextStyle(
                    color: salesDetailTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
        Divider(height: 1, color: salesDetailBorderColor),

        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Builder(
            builder: (context) {
              final grossSubtotal = _currentCart.calculateGrossSubtotal();
              final discountsCombined = _currentCart
                  .calculateTotalDiscountsCombined();
              final itbisAmount = _currentCart.itbisEnabled
                  ? _currentCart.calculateItbis()
                  : 0.0;
              final totalAmount = _currentCart.calculateTotal();
              final subtotalAmount = (grossSubtotal - discountsCombined).clamp(
                0.0,
                double.infinity,
              );

              return Column(
                children: [
                  _buildSummaryRow('Subtotal', subtotalAmount, false),
                  if (discountsCombined > 0) ...[
                    const SizedBox(height: 6),
                    _buildSummaryRow(
                      'Descuentos',
                      discountsCombined,
                      false,
                      color: scheme.error,
                    ),
                  ],
                  const SizedBox(height: 6),
                  _buildSummaryRow('ITBIS (18%)', itbisAmount, false),
                  if (discountsCombined > 0 || _currentCart.itbisEnabled) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(
                        thickness: 1,
                        color: salesDetailBorderColor,
                      ),
                    ),
                  ],

                  GestureDetector(
                    onTap: _showTotalDiscountDialog,
                    onDoubleTap: _showTotalDiscountDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withOpacity(
                          _currentCart.items.isEmpty ? 0.05 : 0.08,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: scheme.primary.withOpacity(0.14),
                        ),
                      ),
                      child: Row(
                        children: [
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.attach_money,
                                  size: 20,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'TOTAL',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: scheme.primary,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FittedBox(
                              alignment: Alignment.centerRight,
                              fit: BoxFit.scaleDown,
                              child: Text(
                                CurrencyDisplay.format(totalAmount),
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 120),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      final fade = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOut,
                      );
                      return FadeTransition(
                        opacity: fade,
                        child: ScaleTransition(
                          scale: Tween(begin: 0.985, end: 1.0).animate(fade),
                          child: child,
                        ),
                      );
                    },
                    child: !_isInlineTotalDiscountOpen
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: _buildInlineTotalDiscountPanel(),
                          ),
                  ),
                ],
              );
            },
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _openFacturaPage,
                    icon: const Icon(Icons.receipt_long_outlined, size: 20),
                    label: const Text(
                      'FACTURA',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.primary,
                      side: BorderSide(color: scheme.primary.withOpacity(0.35)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _currentCart.items.isEmpty
                        ? null
                        : () => _processPayment(
                            SaleKind.invoice,
                            initialPrintTicket: false,
                          ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _currentCart.items.isEmpty
                          ? scheme.surfaceContainerHighest
                          : scheme.primary,
                      foregroundColor: _currentCart.items.isEmpty
                          ? scheme.onSurfaceVariant
                          : scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                      shadowColor: Colors.transparent,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.payment, size: 22),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'COBRAR (F8)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (embedded) return content;

    return Container(
      decoration: BoxDecoration(
        color: salesDetailPanelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: salesDetailBorderColor),
      ),
      margin: EdgeInsets.zero,
      child: content,
    );
  }

  Widget _buildSummaryRow(
    String label,
    double amount,
    bool isTotal, {
    Color? color,
  }) {
    final baseColor = salesDetailTextColor;
    final labelColor = color ?? salesDetailMutedTextColor;
    final valueColor = color ?? baseColor;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 13 : 12,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
              color: labelColor,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          CurrencyDisplay.format(amount),
          style: TextStyle(
            fontSize: isTotal ? 15 : 13,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.bold,
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
                              onChanged: _currentCart.electronicInvoiceEnabled
                                  ? null
                                  : (value) => _updateCurrentCart(
                                      () => _currentCart.itbisEnabled = value,
                                    ),
                              activeColor: scheme.primary,
                            ),
                          ],
                        ),
                      ),
                      if (_isElectronicInvoicingFeatureEnabled) ...[
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
                                      'e-CF',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (_currentCart.electronicInvoiceEnabled)
                                      const Text(
                                        'Envío DGII activo',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _currentCart.electronicInvoiceEnabled,
                                onChanged: (value) async {
                                  if (!value) {
                                    _updateCurrentCart(() {
                                      _currentCart.electronicInvoiceEnabled =
                                          false;
                                    });
                                    return;
                                  }

                                  if (!await _canEnableElectronicInvoiceOrNotify()) {
                                    return;
                                  }

                                  // Activar emisión electrónica implica ITBIS activo
                                  _updateCurrentCart(() {
                                    _currentCart.electronicInvoiceEnabled =
                                        true;
                                    _currentCart.itbisEnabled = true;
                                  });
                                  await _refreshElectronicCompany();
                                },
                                activeColor: scheme.secondary,
                              ),
                            ],
                          ),
                        ),
                        if (_currentCart.electronicInvoiceEnabled) ...[
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
                                  'Factura electrónica DGII',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: scheme.onSecondaryContainer,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _electronicCompany == null
                                            ? 'Cargando configuracion electronica...'
                                            : 'Ambiente ${_electronicCompany!.environment.toUpperCase()} listo para emitir y enviar a DGII.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: () =>
                                          context.push('/electronic-documents'),
                                      icon: const Icon(
                                        Icons.settings_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('Abrir'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
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
                            onTap: _showTotalDiscountDialog,
                            onDoubleTap: _showTotalDiscountDialog,
                            child: _buildTotalRow(
                              'TOTAL:',
                              totalAmount,
                              true,
                            ),
                          ),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 120),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, animation) {
                              final fade = CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOut,
                              );
                              return FadeTransition(
                                opacity: fade,
                                child: ScaleTransition(
                                  scale:
                                      Tween(begin: 0.985, end: 1.0).animate(
                                    fade,
                                  ),
                                  child: child,
                                ),
                              );
                            },
                            child: !_isInlineTotalDiscountOpen
                                ? const SizedBox.shrink()
                                : Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: _buildInlineTotalDiscountPanel(),
                                  ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openFacturaPage,
                          icon: const Icon(
                            Icons.receipt_long_outlined,
                            size: 20,
                          ),
                          label: const Text(
                            'FACTURA',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: scheme.primary,
                            side: BorderSide(
                              color: scheme.primary.withOpacity(0.35),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _currentCart.items.isEmpty
                              ? null
                              : () => _processPayment(
                                  SaleKind.invoice,
                                  initialPrintTicket: false,
                                ),
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
    final isEditing = _inlineEditCartItemIndex == index;
    final subtotal = (item.qty * item.unitPrice) - item.discountLine;

    if (isEditing) {
      _maybeSyncInlineItemControllers(item);
    }

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
        elevation: isSelected ? 2 : 1,
        shadowColor: isSelected
            ? scheme.primary.withOpacity(0.3)
            : Theme.of(context).shadowColor.withOpacity(0.08),
        color: isSelected ? scheme.primary.withOpacity(0.08) : transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isSelected
              ? BorderSide(color: scheme.primary.withOpacity(0.45), width: 1.5)
              : BorderSide(
                  color: scheme.outlineVariant.withOpacity(0.7),
                  width: 1,
                ),
        ),
        child: InkWell(
          onTap: () => setState(() => _selectedCartItemIndex = index),
          onDoubleTap: () => _showEditItemDialog(item, index),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                if (isEditing)
                  _buildInlineQtyStepperEditor(index, compact: true)
                else
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
                      if (isEditing) ...[
                        const SizedBox(height: 6),
                        _buildInlineLineDiscountEditor(index, compact: true),
                      ],
                    ],
                  ),
                ),
                if (!isEditing)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildMiniButton(Icons.remove, () {
                        if (item.qty > 1) {
                          setState(
                            () => _currentCart.updateQuantity(
                              index,
                              item.qty - 1,
                            ),
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
                  onTap: () => _updateCurrentCart(() {
                    if (_inlineEditCartItemIndex == index) {
                      _inlineEditCartItemIndex = null;
                    }
                    if (_selectedCartItemIndex == index) {
                      _selectedCartItemIndex = null;
                    }
                    _currentCart.removeItem(index);
                  }),
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
            CurrencyDisplay.format(amount, symbol: r'$'),
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
        _rebuildQtyIndexForCurrentCart();
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
        _rebuildQtyIndexForCurrentCart();
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
      setState(() {
        _currentCartIndex = selected;
        _rebuildQtyIndexForCurrentCart();
      });
    } finally {
      // Defer disposal to the next frame so the dialog tree has fully
      // unmounted before disposing controllers used by TextFields.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ticketListController.dispose();
        nameController.dispose();
        editController.dispose();
      });
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
                    : '${cart.items.length} item${cart.items.length > 1 ? 's' : ''} - ${CurrencyDisplay.format(cart.calculateTotal())}',
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

enum _SalesDocumentType { consumidorFinal, creditoFiscal, cotizacion }

class _Cart {
  String name;
  int? ticketId;
  int? tempCartId; // ID del carrito temporal en la base de datos
  bool isCompleted = false; // Marca si la venta fue completada
  final List<SaleItemModel> items = [];
  double discount = 0.0;
  bool itbisEnabled = true;
  double itbisRate = 0.18;
  bool electronicInvoiceEnabled = false;
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
