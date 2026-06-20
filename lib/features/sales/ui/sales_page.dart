import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../../core/debug/app_logger.dart' as debug_log;
import '../../../core/errors/error_handler.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/services/empresa_service.dart';
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
import '../../../core/layout/footer_ticket_controller.dart';
import '../../../core/layout/topbar_action_bus.dart';
import '../../../core/notifications/fullpos_notifications.dart';
import '../../../core/theme/app_status_theme.dart';
import '../../../core/theme/color_utils.dart';
import '../../../core/utils/accounting_amount_formatter.dart';
import '../../../core/utils/currency_display.dart';
import '../../../core/theme/sales_page_theme.dart';
import '../../../core/theme/sales_products_theme.dart';
import '../../../core/widgets/branded_loading_view.dart';
import '../../cash/providers/cash_providers.dart';
import '../../cash/data/cash_movement_model.dart';
import '../../cash/data/cash_repository.dart';
import '../../cash/data/operation_flow_service.dart';
import '../../cash/ui/cash_movement_dialog.dart';
import '../../cash/ui/cash_open_dialog.dart';
import '../../cash/ui/cash_panel_sheet.dart';
import '../../clients/data/client_model.dart';
import '../../clients/data/clients_repository.dart';
import '../../clients/ui/widgets/client_form_side_panel.dart';
import '../../products/data/categories_repository.dart';
import '../../products/data/products_repository.dart';
import '../../products/data/suppliers_repository.dart';
import '../../products/models/category_model.dart';
import '../../products/models/product_model.dart';
import '../../products/models/supplier_model.dart';
import '../../products/ui/dialogs/product_form_dialog.dart';
import '../../products/ui/widgets/product_thumbnail.dart';
import '../../settings/data/business_settings_model.dart';
import '../../settings/data/business_settings_repository.dart';
import '../../settings/data/printer_settings_repository.dart';
import '../../settings/providers/business_settings_provider.dart';
import '../../facturacion_electronica/data/electronic_company_repository.dart';
import '../../facturacion_electronica/data/models/electronic_company_model.dart';
import '../../fiscal_receipts/data/fiscal_receipt_models.dart';
import '../../fiscal_receipts/data/fiscal_receipt_repository.dart';
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
import 'factura_page.dart';
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

class _ProductGridMetrics {
  const _ProductGridMetrics({
    required this.crossAxisCount,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.tileWidth,
    required this.tileHeight,
  });

  final int crossAxisCount;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double tileWidth;
  final double tileHeight;
}

class _SalesResponsiveMetrics {
  const _SalesResponsiveMetrics({
    required this.isCompactDesktop,
    required this.isTightDesktop,
    required this.isShortDesktop,
    required this.isVeryShortDesktop,
    required this.ticketPanelWidth,
    required this.productCardWidth,
    required this.productCardHeight,
    required this.productHorizontalMargin,
    required this.productVerticalMargin,
    required this.catalogLeftPadding,
    required this.controlBarTopPadding,
    required this.controlBarRightPadding,
    required this.controlBarHeight,
    required this.productImageSize,
    required this.productImageBoxSize,
    required this.productNameFontSize,
    required this.productPriceFontSize,
    required this.ticketHorizontalPadding,
    required this.ticketHeaderVerticalPadding,
    required this.totalAreaHeight,
    required this.categorySidebarWidth,
    required this.categoryItemHeight,
    required this.categoryAvatarOuterSize,
    required this.categoryAvatarInnerSize,
    required this.footerTicketHeight,
    required this.footerTicketTabHeight,
    required this.spaceBelowControlBar,
  });

  final bool isCompactDesktop;
  final bool isTightDesktop;
  final bool isShortDesktop;
  final bool isVeryShortDesktop;
  final double ticketPanelWidth;
  final double productCardWidth;
  final double productCardHeight;
  final double productHorizontalMargin;
  final double productVerticalMargin;
  final double catalogLeftPadding;
  final double controlBarTopPadding;
  final double controlBarRightPadding;
  final double controlBarHeight;
  final double productImageSize;
  final double productImageBoxSize;
  final double productNameFontSize;
  final double productPriceFontSize;
  final double ticketHorizontalPadding;
  final double ticketHeaderVerticalPadding;
  final double totalAreaHeight;
  final double categorySidebarWidth;
  final double categoryItemHeight;
  final double categoryAvatarOuterSize;
  final double categoryAvatarInnerSize;
  final double footerTicketHeight;
  final double footerTicketTabHeight;
  final double spaceBelowControlBar;
}

class _SalesPageState extends ConsumerState<SalesPage>
    with WidgetsBindingObserver {
  static const Color _allegraBackgroundColor = Color(0xFFF2F6F9);
  static const Color _allegraSurfaceColor = Colors.white;
  static const Color _allegraBorderColor = Color(0xFFDDE5EA);
  static const Color _allegraTextPrimaryColor = Color(0xFF172033);
  static const Color _allegraTextSecondaryColor = Color(0xFF6B7A8C);
  static const Color _allegraAccentColor = Color(0xFF1A56DB);
  static const double _customerRowControlHeight = 36.0;
  static const double _customerRowControlRadius = 10.0;
  static const double _customerNewButtonWidth = 110.0;

  bool _useCompactChromeFor(Size size) {
    final isCompactWidth = size.width <= 1366;
    final isShortHeight = size.height <= 900;
    return isCompactWidth || isShortHeight;
  }

  double _categorySidebarCollapsedWidthFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return _useCompactChromeFor(size) ? 54.0 : 64.0;
  }

  double _categorySidebarExpandedWidthFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return _useCompactChromeFor(size) ? 216.0 : 236.0;
  }

  double _categoryItemHeightFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return _useCompactChromeFor(size) ? 58.0 : 64.0;
  }

  double _categoryCardWidthFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return _useCompactChromeFor(size) ? 46.0 : 50.0;
  }

  double _categoryCardHeightFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return _useCompactChromeFor(size) ? 54.0 : 58.0;
  }

  double _categoryCircleSizeFor(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return _useCompactChromeFor(size) ? 34.0 : 38.0;
  }

  _SalesResponsiveMetrics _salesMetricsFor(Size size) {
    final width = size.width;
    final height = size.height;

    final isTightDesktop = width <= 1280 || height <= 768;
    final isCompactDesktop = width <= 1366 || height <= 900;
    final isShortDesktop = height <= 900;
    final isVeryShortDesktop = height <= 768;

    if (isTightDesktop) {
      return _SalesResponsiveMetrics(
        isCompactDesktop: true,
        isTightDesktop: true,
        isShortDesktop: isShortDesktop,
        isVeryShortDesktop: isVeryShortDesktop,
        ticketPanelWidth: 420,
        productCardWidth: 182,
        productCardHeight: 214,
        productHorizontalMargin: 6,
        productVerticalMargin: 5,
        catalogLeftPadding: 8,
        controlBarTopPadding: isVeryShortDesktop ? 8 : 9,
        controlBarRightPadding: 10,
        controlBarHeight: 39,
        productImageSize: 84,
        productImageBoxSize: 92,
        productNameFontSize: 12.1,
        productPriceFontSize: 15.0,
        ticketHorizontalPadding: 12,
        ticketHeaderVerticalPadding: 9,
        totalAreaHeight: 82,
        categorySidebarWidth: 54,
        categoryItemHeight: 40,
        categoryAvatarOuterSize: 36,
        categoryAvatarInnerSize: 30,
        footerTicketHeight: 36,
        footerTicketTabHeight: 30,
        spaceBelowControlBar: isVeryShortDesktop ? 14 : 16,
      );
    }

    if (isCompactDesktop) {
      return _SalesResponsiveMetrics(
        isCompactDesktop: true,
        isTightDesktop: false,
        isShortDesktop: isShortDesktop,
        isVeryShortDesktop: isVeryShortDesktop,
        ticketPanelWidth: 440,
        productCardWidth: 186,
        productCardHeight: 218,
        productHorizontalMargin: 7,
        productVerticalMargin: 6,
        catalogLeftPadding: 10,
        controlBarTopPadding: 10,
        controlBarRightPadding: 12,
        controlBarHeight: 40,
        productImageSize: 88,
        productImageBoxSize: 94,
        productNameFontSize: 12.3,
        productPriceFontSize: 15.2,
        ticketHorizontalPadding: 14,
        ticketHeaderVerticalPadding: 10,
        totalAreaHeight: 86,
        categorySidebarWidth: 54,
        categoryItemHeight: 40,
        categoryAvatarOuterSize: 36,
        categoryAvatarInnerSize: 30,
        footerTicketHeight: 36,
        footerTicketTabHeight: 30,
        spaceBelowControlBar: 8,
      );
    }

    return _SalesResponsiveMetrics(
      isCompactDesktop: false,
      isTightDesktop: false,
      isShortDesktop: false,
      isVeryShortDesktop: isVeryShortDesktop,
      ticketPanelWidth: 550,
      productCardWidth: 220,
      productCardHeight: 254,
      productHorizontalMargin: 12,
      productVerticalMargin: 10,
      catalogLeftPadding: 14,
      controlBarTopPadding: isShortDesktop ? 16 : 20,
      controlBarRightPadding: 18,
      controlBarHeight: 42,
      productImageSize: 112,
      productImageBoxSize: 118,
      productNameFontSize: 13.4,
      productPriceFontSize: 16.5,
      ticketHorizontalPadding: 18,
      ticketHeaderVerticalPadding: 13,
      totalAreaHeight: 92,
      categorySidebarWidth: 64,
      categoryItemHeight: 48,
      categoryAvatarOuterSize: 44,
      categoryAvatarInnerSize: 36,
      footerTicketHeight: 58,
      footerTicketTabHeight: 46,
      spaceBelowControlBar: 14,
    );
  }

  _ProductGridMetrics _productGridMetricsFor(
    double availableWidth,
    _SalesResponsiveMetrics metrics,
  ) {
    if (!availableWidth.isFinite || availableWidth <= 0) {
      return _ProductGridMetrics(
        crossAxisCount: 1,
        crossAxisSpacing: 0,
        mainAxisSpacing: 0,
        tileWidth: metrics.productCardWidth,
        tileHeight:
            metrics.productCardHeight + (metrics.productVerticalMargin * 2),
      );
    }

    final horizontalInsetPerTile = metrics.productHorizontalMargin * 2;
    final crossSpacing = 0.0;
    final mainSpacing = 0.0;
    final slotWidth = metrics.productCardWidth + horizontalInsetPerTile;

    int crossAxisCount = math.max(1, (availableWidth / slotWidth).floor());
    if (metrics.isTightDesktop) {
      crossAxisCount = math.min(crossAxisCount, 3);
    }

    while (crossAxisCount > 1) {
      final slot = availableWidth / crossAxisCount;
      if (slot >= slotWidth) break;
      crossAxisCount -= 1;
    }

    final tileWidth = metrics.productCardWidth;
    final tileHeight =
        metrics.productCardHeight + (metrics.productVerticalMargin * 2);

    return _ProductGridMetrics(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: crossSpacing,
      mainAxisSpacing: mainSpacing,
      tileWidth: tileWidth,
      tileHeight: tileHeight,
    );
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
  Color get salesDetailBackgroundColor {
    return _allegraSurfaceColor;
  }

  Color get salesDetailTextColor => _allegraTextPrimaryColor;

  Color get salesDetailPanelColor => salesDetailBackgroundColor;

  Color get salesDetailBorderColor => _allegraBorderColor;

  Color get salesDetailMutedTextColor => _allegraTextSecondaryColor;

  Color _salesDetailBlend(double opacity) => Color.alphaBlend(
    _allegraAccentColor.withOpacity(opacity),
    _allegraSurfaceColor,
  );

  Color get salesDetailSurfaceColor => _salesDetailBlend(0.06);

  Color get salesDetailSurfaceStrongColor => _salesDetailBlend(0.12);

  Color get salesDetailSelectedColor => _salesDetailBlend(0.1);

  Color get salesDetailSelectedBorderColor =>
      salesDetailTextColor.withOpacity(0.22);

  Color _gridCanvasColor(BuildContext context) {
    final theme = Theme.of(context);
    final salesProducts = theme.extension<SalesProductsTheme>();
    final isDark = theme.brightness == Brightness.dark;
    final gridBackground =
        (salesProducts?.gridBackgroundColor.opacity ?? 0) == 0
        ? theme.scaffoldBackgroundColor
        : salesProducts!.gridBackgroundColor;

    return isDark
        ? Color.alphaBlend(Colors.white.withOpacity(0.03), gridBackground)
        : _allegraBackgroundColor;
  }

  final List<_Cart> _carts = [_Cart(name: 'Venta principal')];
  int _currentCartIndex = 0;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _clientFocusNode = FocusNode();
  final TextEditingController _clientSearchController = TextEditingController();
  final FocusNode _clientSearchFocusNode = FocusNode();
  final LayerLink _clientSearchLayerLink = LayerLink();
  final GlobalKey _clientSearchFieldKey = GlobalKey();
  OverlayEntry? _clientSearchOverlay;
  String _clientSearchQuery = '';
  int _clientSelectionRevision = 0;
  bool _clientFieldSyncScheduled = false;
  final ScrollController _ticketItemsScrollController = ScrollController();
  Timer? _cartPersistenceTimer;
  bool _cartPersistenceInFlight = false;
  bool _cartPersistenceDirty = false;
  bool _anchoredPopoverOpen = false;
  bool _cashPanelOpen = false;
  final Set<OverlayEntry> _transientOverlayEntries = <OverlayEntry>{};
  String? _lastPersistedCartToken;
  String? _scheduledCartToken;

  // Optimización: índice de cantidades por producto para evitar O(n*m)
  // (cada tarjeta de producto recorriendo todos los items del carrito).
  Map<int, double> _qtyByProductId = const <int, double>{};
  final Map<int, int> _cartItemAnimationTokens = <int, int>{};

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

  void _triggerCartItemEntryAnimation(int index) {
    _cartItemAnimationTokens[index] =
        (_cartItemAnimationTokens[index] ?? 0) + 1;
  }

  Color _categorySidebarColor(int index) {
    const palette = <Color>[
      Color(0xFF1E3A8A),
      Color(0xFF1D4ED8),
      Color(0xFF0F766E),
      Color(0xFF374151),
      Color(0xFF111827),
      Color(0xFF4C1D95),
      Color(0xFF7C2D12),
      Color(0xFF365314),
    ];
    return palette[index % palette.length];
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

  void _handleMovementPanelToggle() {
    if (!mounted) return;
    final pendingAction = TopbarActionBus.consumePendingSalesOverlay();
    if (pendingAction.movementType != null) {
      unawaited(_openCashMovementDialogInCenter(pendingAction.movementType!));
      return;
    }
    if (pendingAction.openCurrentShiftPanel) {
      unawaited(_openCurrentShiftPanelInCenter());
      return;
    }
    setState(() => _showMovementPanel = !_showMovementPanel);
  }

  Future<void> _toggleRecentSalesPanel() async {
    final shouldOpen = !_showRecentSalesPanel;
    if (!mounted) return;
    setState(() => _showRecentSalesPanel = shouldOpen);
    if (shouldOpen) {
      await _loadRecentSales();
    }
  }

  void _closeRecentSalesPanel() {
    if (!mounted || !_showRecentSalesPanel) return;
    setState(() => _showRecentSalesPanel = false);
  }

  Future<void> _loadRecentSales() async {
    if (_isLoadingRecentSales) return;
    if (!mounted) return;
    setState(() => _isLoadingRecentSales = true);
    try {
      final sales = await SalesRepository.listCompletedSales();
      if (!mounted) return;
      setState(() {
        _recentSales
          ..clear()
          ..addAll(sales.take(8));
      });
    } catch (_) {
      if (!mounted) return;
    } finally {
      if (mounted) {
        setState(() => _isLoadingRecentSales = false);
      }
    }
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
  final TextEditingController _inlineQtyController = TextEditingController();
  final TextEditingController _inlineLineDiscountController =
      TextEditingController();
  final FocusNode _inlineQtyFocusNode = FocusNode();
  final FocusNode _inlineLineDiscountFocusNode = FocusNode();

  DiscountType _inlineTotalDiscountType = DiscountType.percent;
  final TextEditingController _inlineTotalDiscountController =
      TextEditingController();
  final FocusNode _inlineTotalDiscountFocusNode = FocusNode();

  bool _keyboardShortcutsEnabled = true;
  FooterTicketController? _footerTicketController;
  ScannerInputController? _scanner;
  late final bool Function(KeyEvent) _globalShortcutHandler;

  NavigatorState? _rootNavigator;
  ScaffoldMessengerState? _scaffoldMessenger;
  final bool _isDisposingSalesPage = false;

  String? _lastScanCode;
  int _lastScanAtMs = 0;
  int _initialLoadToken = 0;
  bool _loggedFirstBuild = false;
  bool _sessionBootstrapScheduled = false;
  bool _showMovementPanel = false;
  bool _isQuickSalePressed = false;
  final Set<int> _hoveredProductIndexes = <int>{};
  final Set<int> _hoveredCartItemIndexes = <int>{};
  final Set<String> _hoveredCartRowActions = <String>{};
  final Set<String> _hoveredTicketHeaderActions = <String>{};
  final Set<String> _processedPaymentRequestIds = <String>{};
  bool _isProcessingSaleExecution = false;
  bool _isQuotePdfFlowRunning = false;
  bool _showRecentSalesPanel = false;
  bool _isLoadingRecentSales = false;
  final List<legacy_sales.SaleModel> _recentSales = <legacy_sales.SaleModel>[];
  final Set<int> _hoveredRecentSaleIds = <int>{};

  List<ProductModel> _allProducts = [];
  List<ProductModel> _searchResults = [];
  bool _isSearching = false;

  ElectronicCompanyModel? _electronicCompany;
  FiscalReceiptSettingsModel _fiscalReceiptSettings =
      const FiscalReceiptSettingsModel(enabled: false);
  List<FiscalReceiptTypeModel> _fiscalReceiptTypes = const [];
  List<CategoryModel> _categories = [];
  final Set<int> _selectedCategoryIds = <int>{};
  bool _isCategorySidebarExpanded = false;
  Timer? _categorySidebarCollapseTimer;
  List<ClientModel> _clients = [];
  AppSettingsModel? _appSettings;
  final ProductFilterModel _productFilter = ProductFilterModel();
  int _lastFooterTicketSignature = 0;

  _Cart get _currentCart => _carts[_currentCartIndex];

  String _firstNameOnly(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts.isEmpty ? '' : parts.first;
  }

  int _compareFeaturedFirst(ProductModel a, ProductModel b) {
    if (a.isFeatured != b.isFeatured) {
      return a.isFeatured ? -1 : 1;
    }
    return 0;
  }

  String _normalizeLabel(String value) {
    return value.trim().toLowerCase();
  }

  bool _labelExists(String label, {int? excludeIndex}) {
    final normalized = _normalizeLabel(label);
    for (var i = 0; i < _carts.length; i++) {
      if (excludeIndex != null && i == excludeIndex) continue;
      if (_normalizeLabel(_carts[i].name) == normalized) return true;
    }
    return false;
  }

  String _nextUniqueSaleLabel() {
    final ventaRegex = RegExp(r'^venta\s+(\d+)$', caseSensitive: false);
    final usedNumbers = <int>{};
    for (final cart in _carts) {
      final match = ventaRegex.firstMatch(cart.name.trim());
      if (match != null) {
        usedNumbers.add(int.parse(match.group(1)!));
      }
    }
    var next = 1;
    while (usedNumbers.contains(next)) {
      next++;
    }
    return 'Venta $next';
  }

  String _ensureUniqueLabel(String proposed, {int? excludeIndex}) {
    final trimmed = proposed.trim();
    if (trimmed.isEmpty) return _nextUniqueSaleLabel();
    if (!_labelExists(trimmed, excludeIndex: excludeIndex)) return trimmed;
    // Si ya existe, generar el siguiente disponible
    return _nextUniqueSaleLabel();
  }

  String _footerTicketLabel(_Cart cart, int index) {
    final clientName = cart.selectedClient?.nombre.trim() ?? '';
    if (clientName.isNotEmpty && !_isDefaultClientName(clientName)) {
      return _firstNameOnly(clientName);
    }

    final raw = cart.name.trim();
    final normalized = raw.toLowerCase();
    final isGenericTicket =
        normalized.isEmpty ||
        RegExp(r'^(ticket|venta)\s*\d*$', caseSensitive: false).hasMatch(raw);

    if (index == 0 && isGenericTicket) {
      return 'Ticket principal';
    }

    if (isGenericTicket) {
      return 'Ticket ${index + 1}';
    }

    return raw.length > 18 ? '${raw.substring(0, 15)}...' : raw;
  }

  List<FooterTicketTabData> _buildFooterTabs() {
    if (_carts.isEmpty) {
      return const <FooterTicketTabData>[];
    }

    return List<FooterTicketTabData>.generate(_carts.length, (index) {
      final cart = _carts[index];
      return FooterTicketTabData(
        label: _footerTicketLabel(cart, index),
        isActive: index == _currentCartIndex,
        showAlertDot: cart.items.isNotEmpty,
        canDelete: _carts.length > 1,
      );
    });
  }

  void _syncFooterTicketsDeferred() {
    final tabs = _buildFooterTabs();
    final signature = Object.hashAll([
      _currentCartIndex,
      tabs.length,
      for (final tab in tabs)
        Object.hash(tab.label, tab.isActive, tab.showAlertDot, tab.canDelete),
    ]);
    if (_lastFooterTicketSignature == signature) return;
    _lastFooterTicketSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(footerTicketControllerProvider).updateTabs(tabs);
    });
  }

  void _bindFooterTicketController() {
    final controller = ref.read(footerTicketControllerProvider);

    _footerTicketController = controller;

    controller.bind(
      onAdd: _addFooterTicket,
      onSelect: _selectFooterTicket,
      onRename: _renameFooterTicket,
      onDelete: _deleteFooterTicket,
    );
  }

  bool get _isElectronicInvoicingFeatureEnabled =>
      ref.read(businessSettingsProvider).electronicInvoicingEnabled;

  void _disableElectronicInvoicingForAllCarts() {
    var changed = false;
    for (final cart in _carts) {
      if (!cart.electronicInvoiceEnabled) continue;
      cart.electronicInvoiceEnabled = false;
      cart.documentType = _SalesDocumentType.consumidorFinal;
      changed = true;
    }

    if (!changed || !mounted) return;

    setState(() {});
    unawaited(_saveAllCartsToDatabase());
    _scheduleCartPersistence();
  }

  double _normalizeItbisRate(double percent) {
    return (percent / 100).clamp(0.0, 1.0).toDouble();
  }

  bool get _isGlobalItbisEnabled =>
      ref.read(businessSettingsProvider).itbisEnabled;

  void _applyConfiguredTaxSettingsToCart(
    _Cart cart,
    BusinessSettings settings, {
    bool useDefaultEnabled = false,
  }) {
    cart.itbisRate = _normalizeItbisRate(settings.defaultTaxRate);
    if (useDefaultEnabled) {
      cart.itbisEnabled = settings.itbisEnabled;
    } else if (cart.itbisEnabled != settings.itbisEnabled) {
      cart.itbisEnabled = settings.itbisEnabled;
    }

    if (!settings.itbisEnabled) {
      cart.electronicInvoiceEnabled = false;
      cart.documentType = _SalesDocumentType.consumidorFinal;
    }
  }

  void _applySalesDefaultsToCart(_Cart cart) {
    final settings = _appSettings;
    final businessSettings = ref.read(businessSettingsProvider);

    _applyConfiguredTaxSettingsToCart(
      cart,
      businessSettings,
      useDefaultEnabled: true,
    );
    cart.electronicInvoiceEnabled =
        _isElectronicInvoicingFeatureEnabled &&
        (settings?.electronicInvoiceEnabledDefault ?? false) &&
        businessSettings.itbisEnabled;
    if (cart.electronicInvoiceEnabled) {
      // La emisión electrónica implica ITBIS activo.
      cart.itbisEnabled = true;
      cart.documentType = _SalesDocumentType.creditoFiscal;
    } else {
      cart.documentType = _SalesDocumentType.consumidorFinal;
    }
    cart.fiscalReceiptTypeId = _fiscalReceiptSettings.enabled
        ? _resolveDefaultFiscalReceiptTypeId()
        : null;
  }

  int? _resolveDefaultFiscalReceiptTypeId() {
    final configured = _fiscalReceiptSettings.defaultReceiptTypeId;
    if (configured != null &&
        _fiscalReceiptTypes.any(
          (type) => type.id == configured && type.isAvailable,
        )) {
      return configured;
    }
    final defaults = _fiscalReceiptTypes.where(
      (type) => type.isDefault && type.isAvailable,
    );
    if (defaults.isNotEmpty) return defaults.first.id;
    final active = _fiscalReceiptTypes.where((type) => type.isAvailable);
    return active.isEmpty ? null : active.first.id;
  }

  BoxConstraints _ticketPanelConstraints(double width) {
    if (width <= 1280) {
      return const BoxConstraints(minWidth: 418, maxWidth: 418);
    }
    if (width <= 1366) {
      return const BoxConstraints(minWidth: 438, maxWidth: 438);
    }
    if (width < 1400) {
      return const BoxConstraints(minWidth: 470, maxWidth: 470);
    }
    if (width < 1600) {
      return const BoxConstraints(minWidth: 500, maxWidth: 500);
    }
    return const BoxConstraints(minWidth: 550, maxWidth: 550);
  }

  Size _salesPanelDialogSize() {
    final screenSize = MediaQuery.sizeOf(context);
    final panelWidth = _ticketPanelConstraints(screenSize.width).maxWidth;
    return Size(panelWidth, screenSize.height);
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _bindFooterTicketController();

    TopbarActionBus.salesMovementToggle.addListener(_handleMovementPanelToggle);

    _loadAccess();
    _loadInitialData();
    unawaited(_loadRecentSales());

    // Evitar modificar providers durante el build inicial.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposingSalesPage) return;

      _showRestoredSessionNoticeIfPending();
      unawaited(_refreshCashSession());
      unawaited(_ensureSessionBootstrap());
      final pendingAction = TopbarActionBus.consumePendingSalesOverlay();
      if (pendingAction.movementType != null) {
        unawaited(_openCashMovementDialogInCenter(pendingAction.movementType!));
      } else if (pendingAction.openCurrentShiftPanel) {
        unawaited(_openCurrentShiftPanelInCenter());
      }
    });

    _loadScannerConfig();

    _globalShortcutHandler = _handleGlobalShortcutKey;
    HardwareKeyboard.instance.addHandler(_globalShortcutHandler);

    RawKeyboard.instance.addListener(_handleScannerKey);
    _clientSearchFocusNode.addListener(_handleClientSearchFocus);
  }

  void _showRestoredSessionNoticeIfPending() {
    final restored = OperationFlowService.consumeRestoredSessionNotice();
    if (restored == null || !mounted || _isDisposingSalesPage) return;

    final openedAt = DateTime.fromMillisecondsSinceEpoch(
      restored.openedAt,
    ).toLocal();
    final formatted = DateFormat('dd/MM/yyyy HH:mm').format(openedAt);
    FullPosNotifications.show(
      type: AppNotificationType.shift,
      title: 'Turno restaurado',
      message:
          'Se restauró tu turno abierto del $formatted. '
          'Puedes continuar trabajando donde lo dejaste.',
      deduplicationKey: 'restored-shift-${restored.openedAt}',
      duration: const Duration(seconds: 6),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Guardamos referencias seguras para no llamar Navigator.of(context)
    // cuando el widget ya esté desmontado.
    _rootNavigator = Navigator.of(context, rootNavigator: true);
    _scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  }

  Future<void> _loadAccess() async {
    final enabled = await UiPreferences.isKeyboardShortcutsEnabled();

    if (!mounted || _isDisposingSalesPage) return;

    setState(() => _keyboardShortcutsEnabled = enabled);
  }

  void _handleScannerKey(RawKeyEvent event) {
    if (_isDisposingSalesPage || !mounted) return;

    _scanner?.handleKeyEvent(event);
  }

  void _handleClientSearchFocus() {
    if (_isDisposingSalesPage || !mounted) return;

    if (_clientSearchFocusNode.hasFocus) {
      _openClientSearchOverlay();
    } else {
      _closeClientSearchOverlay();
      _syncClientFieldText();
    }
  }

  void _syncClientFieldText({bool force = false}) {
    if (_isDisposingSalesPage || !mounted) return;
    if (_clientSearchFocusNode.hasFocus && !force) return;

    final client = _currentCart.selectedClient;

    final clientName = client?.nombre.trim().isNotEmpty == true
        ? client!.nombre.trim()
        : '';

    final clientMeta = client == null
        ? ''
        : (client.rnc?.trim().isNotEmpty == true
              ? client.rnc!.trim()
              : (client.cedula?.trim().isNotEmpty == true
                    ? client.cedula!.trim()
                    : (client.telefono?.trim().isNotEmpty == true
                          ? client.telefono!.trim()
                          : '')));

    final display = clientName.isEmpty
        ? ''
        : (clientMeta.isEmpty ? clientName : '$clientName ($clientMeta)');

    if (_clientSearchController.text != display) {
      _clientSearchController.text = display;
      _clientSearchController.selection = TextSelection.collapsed(
        offset: display.length,
      );
    }
  }

  void _scheduleClientFieldSync() {
    if (_clientFieldSyncScheduled || _isDisposingSalesPage || !mounted) return;
    _clientFieldSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _clientFieldSyncScheduled = false;
      if (!mounted || _isDisposingSalesPage) return;
      _syncClientFieldText();
    });
  }

  void _handleCurrentCartChanged() {
    _clientSelectionRevision++;
    _closeClientSearchOverlay();
    _clientSearchQuery = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isDisposingSalesPage) return;
      _syncClientFieldText(force: true);
    });
  }

  void _openClientSearchOverlay() {
    if (_isDisposingSalesPage || !mounted) return;
    if (_clientSearchOverlay != null) return;

    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;

    _clientSearchOverlay = OverlayEntry(
      builder: (overlayContext) {
        final renderBox =
            _clientSearchFieldKey.currentContext?.findRenderObject()
                as RenderBox?;

        final fieldSize = renderBox?.size;
        final width = fieldSize?.width ?? 320;
        final height = fieldSize?.height ?? 48;

        return Positioned.fill(
          child: Stack(
            children: [
              GestureDetector(
                onTap: () {
                  _closeClientSearchOverlay();
                  _clientSearchFocusNode.unfocus();
                  _syncClientFieldText(force: true);
                },
                behavior: HitTestBehavior.translucent,
                child: const SizedBox.expand(),
              ),
              CompositedTransformFollower(
                link: _clientSearchLayerLink,
                showWhenUnlinked: false,
                offset: Offset(0, height + 6),
                child: Material(
                  color: Colors.transparent,
                  child: TextFieldTapRegion(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: width,
                        minWidth: width,
                        maxHeight: 320,
                      ),
                      child: _buildClientSearchDropdown(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    overlayState.insert(_clientSearchOverlay!);
  }

  void _closeClientSearchOverlay() {
    _clientSearchOverlay?.remove();
    _clientSearchOverlay = null;
  }

  bool _handleGlobalShortcutKey(KeyEvent event) {
    if (_isDisposingSalesPage) return false;
    if (!mounted) return false;
    if (event is! KeyDownEvent) return false;

    final navigator = _rootNavigator;
    if (navigator == null) return false;

    // No usar Navigator.of(context) aquí.
    // Esa línea era la que provocaba:
    // Looking up a deactivated widget's ancestor is unsafe.
    if (navigator.canPop()) return false;

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.f1) {
      if (_searchFocusNode.canRequestFocus) {
        _searchFocusNode.requestFocus();
      }
      return true;
    }

    if (key == LogicalKeyboardKey.f8) {
      if (_currentCart.items.isEmpty) {
        _scaffoldMessenger?.showSnackBar(
          const SnackBar(
            content: Text('Agrega productos antes de cobrar'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return true;
      }

      unawaited(_processPayment(SaleKind.invoice, initialPrintTicket: true));

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

    if (!mounted || _isDisposingSalesPage) return;

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
    if (_isDisposingSalesPage || !mounted) return;

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

    if (!mounted || _isDisposingSalesPage) return;

    if (product == null && code.toUpperCase() != code) {
      product = await ErrorHandler.instance.runSafe<ProductModel?>(
        () => repo.getByCode(code.toUpperCase()),
        context: context,
        onRetry: () =>
            _handleBarcodeScan(code, clearSearchField: clearSearchField),
        module: 'sales/scan/code_upper',
      );
    }

    if (!mounted || _isDisposingSalesPage) return;

    if (product == null) {
      final results = await ErrorHandler.instance.runSafe<List<ProductModel>>(
        () => repo.search(code),
        context: context,
        onRetry: () =>
            _handleBarcodeScan(code, clearSearchField: clearSearchField),
        module: 'sales/scan/search',
      );

      if (!mounted || _isDisposingSalesPage) return;

      if (results != null && results.length == 1) {
        product = results.first;
      }
    }

    if (!mounted || _isDisposingSalesPage) return;

    if (product == null) {
      _scaffoldMessenger?.showSnackBar(
        SnackBar(
          content: Text('No se encontró producto con código: $code'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
      return;
    }

    await _addProductToCart(product);

    if (!mounted || _isDisposingSalesPage) return;

    if (clearSearchField) {
      _searchController.clear();

      if (_searchFocusNode.canRequestFocus) {
        _searchFocusNode.requestFocus();
      }

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
        FiscalReceiptRepository.getSettings(),
        FiscalReceiptRepository.getActiveTypes(),
      ]);
      if (!mounted || token != _initialLoadToken) return;

      final products = results[0] as List<ProductModel>;
      final categories = results[1] as List<CategoryModel>;
      final clients = results[2] as List<ClientModel>;
      final dbTickets = results[3] as List<PosTicketModel>;
      final tempCarts = results[4] as List<Map<String, dynamic>>;
      final appSettings = results[5] as AppSettingsModel;
      final electronicCompany = results[6] as ElectronicCompanyModel;
      final fiscalReceiptSettings = results[7] as FiscalReceiptSettingsModel;
      final fiscalReceiptTypes = results[8] as List<FiscalReceiptTypeModel>;
      final electronicInvoicingFeatureEnabled =
          _isElectronicInvoicingFeatureEnabled;

      _fiscalReceiptSettings = fiscalReceiptSettings;
      _fiscalReceiptTypes = fiscalReceiptTypes;

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
          ..electronicInvoiceEnabled = false
          ..documentType = _SalesDocumentType.consumidorFinal;

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

        _applyConfiguredTaxSettingsToCart(
          cart,
          ref.read(businessSettingsProvider),
          useDefaultEnabled: true,
        );

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
        cart.documentType = cart.electronicInvoiceEnabled
            ? _SalesDocumentType.creditoFiscal
            : _SalesDocumentType.consumidorFinal;

        final clientId = cartMap['client_id'] as int?;
        if (clientId != null) {
          final client = clients.where((c) => c.id == clientId).firstOrNull;
          if (client != null) cart.selectedClient = client;
        }

        cart.items.addAll(tempCartItemsById[id] ?? const <SaleItemModel>[]);

        _applyConfiguredTaxSettingsToCart(
          cart,
          ref.read(businessSettingsProvider),
          useDefaultEnabled: true,
        );

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
        _fiscalReceiptSettings = fiscalReceiptSettings;
        _fiscalReceiptTypes = fiscalReceiptTypes;
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
      _handleCurrentCartChanged();

      await _ensureDefaultCustomerSelected();

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

  Future<void> _openCashMovementDialogInCenter(String type) async {
    var sessionId = await _ensureActiveShiftOrRedirect(showMessage: true);
    if (sessionId == null) {
      final opened = await CashOpenDialog.show(context);
      if (opened == true) await _refreshCashSession();
      sessionId = await _ensureActiveShiftOrRedirect(showMessage: false);
    }

    if (!mounted) return;
    if (sessionId == null) return;
    final int safeSessionId = sessionId;

    final isIncome = type == CashMovementType.income;
    final screenSize = MediaQuery.sizeOf(context);
    final dialogSize = math.min(screenSize.width, screenSize.height) * 0.42;
    final clampedSize = dialogSize.clamp(340.0, 440.0);

    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.4),
      useSafeArea: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) Navigator.of(dialogContext).pop();
          },
          child: Stack(
            children: [
              // Blur overlay
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(color: Colors.transparent),
                ),
              ),
              Center(
                child: _AnimatedCashDialog(
                  size: clampedSize,
                  child: _CompactCashMovementForm(
                    type: type,
                    sessionId: safeSessionId,
                    isIncome: isIncome,
                    onDone: () {
                      Navigator.of(dialogContext).pop();
                      _refreshCashSession();
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openCurrentShiftPanelInCenter() async {
    if (_cashPanelOpen || !mounted) return;
    _cashPanelOpen = true;
    _closeClientSearchOverlay();

    try {
      var sessionId = await _ensureActiveShiftOrRedirect(showMessage: true);
      if (sessionId == null) {
        final opened = await CashOpenDialog.show(context);
        if (opened == true) await _refreshCashSession();
        sessionId = await _ensureActiveShiftOrRedirect(showMessage: false);
      }

      if (!mounted || sessionId == null) return;
      await CashPanelSheet.show(context, sessionId: sessionId, centered: true);
      if (!mounted) return;
      await _refreshCashSession();
    } finally {
      _cashPanelOpen = false;
    }
  }

  /// Guarda todos los carritos temporales en la base de datos
  // ignore: unused_element
  Future<void> _saveAllCartsToDatabase() async {
    final tempCartRepo = TempCartRepository();
    final userId = await SessionManager.userId();

    for (final cart in _carts) {
      // Persistir todos los tickets temporales, incluso vacios, para que
      // sobrevivan al cerrar y reabrir la app hasta que el usuario los elimine.
      if (cart.ticketId == null) {
        try {
          final savedId = await tempCartRepo.saveCart(
            id: cart.tempCartId,
            name: cart.name,
            userId: userId,
            clientId: cart.selectedClient?.id,
            discount: cart.discount,
            itbisEnabled: cart.itbisEnabled,
            itbisRate: cart.itbisRate,
            electronicInvoiceEnabled: cart.electronicInvoiceEnabled,
            discountTotalType: cart.discountTotalType,
            discountTotalValue: cart.discountTotalValue,
            items: cart.items,
          );
          cart.tempCartId = savedId;
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

  Future<void> _cancelCurrentCart() async {
    if (_currentCart.items.isEmpty) return;

    final shouldCancel = await _presentDialog<bool>(
      builder: (context) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
        child: SizedBox(
          width: 455,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(50, 14, 46, 12),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Cancelar venta',
                        style: TextStyle(
                          color: Color(0xFF172033),
                          fontSize: 22,
                          fontWeight: FontWeight.w400,
                          height: 1.1,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.of(context).pop(false),
                      borderRadius: BorderRadius.circular(20),
                      child: const SizedBox(
                        width: 28,
                        height: 28,
                        child: Icon(
                          Icons.close_rounded,
                          color: Color(0xFFA3A3A3),
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(height: 1, color: Color(0xFFE5E7EB)),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(46, 28, 46, 30),
                child: Text(
                  'Los productos serán eliminados de la venta actual\n'
                  '¿Desea continuar?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    height: 1.55,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Divider(height: 1, color: Color(0xFFE5E7EB)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(50, 16, 50, 34),
                child: Row(
                  children: [
                    const Text(
                      '*',
                      style: TextStyle(
                        color: Color(0xFF2563EB),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Campos obligatorios',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 102,
                      height: 40,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          foregroundColor: const Color(0xFF0F172A),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 92,
                      height: 40,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1A56DB),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: const Text(
                          'Aceptar',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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
    );

    if (!mounted || shouldCancel != true) return;

    await _deleteCurrentCartFromDatabase();
    if (!mounted) return;

    setState(() {
      _currentCart.clear();
      _selectedCartItemIndex = null;
      _rebuildQtyIndexForCurrentCart();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Venta cancelada'),
        backgroundColor: status.warning,
      ),
    );
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
              overrideCopies: sale.kind == 'invoice' ? 1 : null,
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

        if (_currentCart.ticketId != null) {
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

  // Ajusta el stock localmente tras completar una venta para reflejar el inventario actualizado
  void _applyStockAdjustments(List<SaleItemModel> items) {
    if (!mounted) return;
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

    if (!mounted) return;
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
    final selectedCategoryIds = _selectedCategoryIds.toList()..sort();

    final cacheKey = Object.hash(
      _searchController.text.trim().isEmpty,
      identityHashCode(source),
      source.length,
      identityHashCode(_categories),
      _categories.length,
      Object.hashAll(selectedCategoryIds),
      _productFilter.onlyWithStock,
      _productFilter.minPrice,
      _productFilter.maxPrice,
      _productFilter.sortBy,
    );
    if (_filteredProductsCacheKey == cacheKey) {
      return _filteredProductsCache;
    }

    final filtered = source.where((p) {
      if (_selectedCategoryIds.isNotEmpty &&
          !_selectedCategoryIds.contains(p.categoryId)) {
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
        filtered.sort((a, b) {
          final featured = _compareFeaturedFirst(a, b);
          if (featured != 0) return featured;
          return a.name.compareTo(b.name);
        });
        break;
      case ProductSortBy.nameDesc:
        filtered.sort((a, b) {
          final featured = _compareFeaturedFirst(a, b);
          if (featured != 0) return featured;
          return b.name.compareTo(a.name);
        });
        break;
      case ProductSortBy.priceAsc:
        filtered.sort((a, b) {
          final featured = _compareFeaturedFirst(a, b);
          if (featured != 0) return featured;
          return a.salePrice.compareTo(b.salePrice);
        });
        break;
      case ProductSortBy.priceDesc:
        filtered.sort((a, b) {
          final featured = _compareFeaturedFirst(a, b);
          if (featured != 0) return featured;
          return b.salePrice.compareTo(a.salePrice);
        });
        break;
      case ProductSortBy.stockAsc:
        filtered.sort((a, b) {
          final featured = _compareFeaturedFirst(a, b);
          if (featured != 0) return featured;
          return a.stock.compareTo(b.stock);
        });
        break;
      case ProductSortBy.stockDesc:
        filtered.sort((a, b) {
          final featured = _compareFeaturedFirst(a, b);
          if (featured != 0) return featured;
          return b.stock.compareTo(a.stock);
        });
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

  Future<void> _refreshCatalogAfterProductChanges() async {
    final productsRepo = ProductsRepository();
    final categoriesRepo = CategoriesRepository();
    final trimmed = _searchController.text.trim();

    final results = await Future.wait([
      trimmed.isEmpty ? productsRepo.getAll() : productsRepo.search(trimmed),
      categoriesRepo.getAll(),
    ]);

    if (!mounted) return;

    final products = results[0] as List<ProductModel>;
    final categories = results[1] as List<CategoryModel>;

    setState(() {
      _searchResults = products;
      if (trimmed.isEmpty) {
        _allProducts = products;
      }
      _categories = categories;
      final validCategoryIds = categories
          .map((category) => category.id)
          .whereType<int>()
          .toSet();
      _selectedCategoryIds.removeWhere(
        (categoryId) => !validCategoryIds.contains(categoryId),
      );
      _filteredProductsCacheKey = null;
      _isSearching = false;
    });
  }

  Future<void> _toggleProductFeatured(ProductModel product) async {
    final productId = product.id;
    if (productId == null) return;

    final repo = ProductsRepository();
    final nextValue = !product.isFeatured;
    final updated = product.copyWith(isFeatured: nextValue);

    if (!mounted) return;
    setState(() {
      _allProducts = _allProducts
          .map((p) => p.id == productId ? updated : p)
          .toList(growable: false);
      _searchResults = _searchResults
          .map((p) => p.id == productId ? updated : p)
          .toList(growable: false);
      _filteredProductsCacheKey = null;
    });

    await repo.setFeatured(productId, nextValue);
    if (!mounted) return;
    await _searchProducts(_searchController.text);
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
    double? dialogWidth,
    double? dialogHeight,
    EdgeInsets? insetPadding,
    AlignmentGeometry? alignment,
    BorderRadius? borderRadius,
  }) async {
    if (!mounted) return null;
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel: barrierLabel,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      builder: (dialogContext) {
        Widget child = builder(dialogContext);
        if (dialogWidth != null ||
            dialogHeight != null ||
            insetPadding != null ||
            alignment != null ||
            borderRadius != null) {
          child = Dialog(
            insetPadding:
                insetPadding ??
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            alignment: alignment,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius ?? BorderRadius.circular(20),
            ),
            child: SizedBox(
              width: dialogWidth,
              height: dialogHeight,
              child: child,
            ),
          );
        }
        return child;
      },
    );
  }

  void _onCategorySelected(int? categoryId) {
    setState(() {
      if (categoryId == null) {
        _selectedCategoryIds.clear();
      } else if (_selectedCategoryIds.contains(categoryId)) {
        _selectedCategoryIds.remove(categoryId);
      } else {
        _selectedCategoryIds.add(categoryId);
      }
      _filteredProductsCacheKey = null;
    });
  }

  void _clearCategoryFilter() {
    setState(() {
      _selectedCategoryIds.clear();
      _filteredProductsCacheKey = null;
    });
  }

  void _expandCategorySidebar() {
    _categorySidebarCollapseTimer?.cancel();
    _categorySidebarCollapseTimer = null;
    if (_isCategorySidebarExpanded || !mounted) return;
    setState(() => _isCategorySidebarExpanded = true);
  }

  void _scheduleCategorySidebarCollapse() {
    _categorySidebarCollapseTimer?.cancel();
    _categorySidebarCollapseTimer = Timer(const Duration(milliseconds: 90), () {
      if (!mounted || !_isCategorySidebarExpanded) return;
      setState(() => _isCategorySidebarExpanded = false);
      _categorySidebarCollapseTimer = null;
    });
  }

  Future<ClientModel?> _showClientPicker() async {
    _closeClientSearchOverlay();
    _clientSearchFocusNode.unfocus();

    final dialogSize = _salesPanelDialogSize();
    final result = await _presentDialog<ClientModel>(
      builder: (context) => ClientPickerDialog(
        clients: _clients,
        onCreateClient: _showClientFormFromSales,
        dialogWidth: dialogSize.width,
        dialogHeight: dialogSize.height,
        insetPadding: EdgeInsets.zero,
        alignment: Alignment.centerRight,
        borderRadius: BorderRadius.zero,
      ),
    );

    if (!mounted || result == null) return null;
    await _applySelectedClient(result);
    return result;
  }

  Future<ClientModel?> _showCreateClientFromSales() async {
    final result = await _showClientFormFromSales();
    if (!mounted || result == null) return result;
    await _applySelectedClient(result);
    return result;
  }

  Future<ClientModel?> _showEditClientFromSales(ClientModel client) async {
    final cart = _currentCart;
    final wasSelected = cart.selectedClient?.id == client.id;
    final result = await _showClientFormFromSales(initialClient: client);
    if (!mounted || result == null) return result;
    if (wasSelected && identical(cart, _currentCart)) {
      await _applySelectedClient(result, cart: cart);
    } else {
      _clientSearchOverlay?.markNeedsBuild();
    }
    return result;
  }

  Future<ClientModel?> _showClientFormFromSales({
    ClientModel? initialClient,
  }) async {
    final screenSize = MediaQuery.sizeOf(context);
    final panelWidth = _ticketPanelConstraints(screenSize.width).maxWidth;
    final result = await showClientFormSidePanel(
      context,
      initialClient: initialClient,
      panelWidth: panelWidth,
    );

    if (!mounted || result == null) return null;

    setState(() {
      _clients.removeWhere((item) => item.id == result.id);
      _clients.add(result);
    });
    return result;
  }

  Future<void> _applySelectedClient(
    ClientModel result, {
    bool automatic = false,
    _Cart? cart,
  }) async {
    final targetCart = cart ?? _currentCart;
    if (!automatic) {
      _clientSelectionRevision++;
    }

    _closeClientSearchOverlay();
    _clientSearchQuery = '';
    _updateCurrentCart(() {
      targetCart.selectedClient = result;
    });
    _syncClientFieldText(force: true);
    _clientSearchFocusNode.unfocus();

    if (targetCart.ticketId != null) {
      final ticketId = targetCart.ticketId!;
      await ErrorHandler.instance.runSafe<void>(
        () async {
          final repository = TicketsRepository();
          await repository.updateTicketClient(ticketId, result.id);
        },
        context: context,
        module: 'sales/ticket_client',
      );
    }

    if (!mounted || targetCart.selectedClient?.id != result.id) return;

    await ErrorHandler.instance.runSafe<void>(
      () => _applyDefaultDocumentTypeForClient(result, cart: targetCart),
      context: context,
      module: 'sales/client_document_type',
    );

    if (mounted && identical(targetCart, _currentCart)) {
      _syncClientFieldText(force: true);
    }
  }

  Future<void> _applyDefaultDocumentTypeForClient(
    ClientModel client, {
    required _Cart cart,
  }) async {
    if (!mounted) return;
    if (client.normalizedRnc != null) {
      await _setSalesDocumentType(_SalesDocumentType.creditoFiscal, cart: cart);
      return;
    }
    await _setSalesDocumentType(_SalesDocumentType.consumidorFinal, cart: cart);
  }

  static const Set<String> _defaultClientNameTokens = <String>{
    'consumidorfinal',
    'clientegeneral',
    'clientepordefecto',
    'clientedefecto',
    'clientecontado',
    'generico',
    'generico01',
  };

  String _normalizeClientLookupValue(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[áàäâ]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöô]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _isDefaultClientName(String? name) {
    if (name == null) return false;
    final token = _normalizeClientLookupValue(name);
    return _defaultClientNameTokens.contains(token);
  }

  ClientModel? _findDefaultClientIn(Iterable<ClientModel> clients) {
    for (final client in clients) {
      if (_isDefaultClientName(client.nombre) && client.id != null) {
        return client;
      }
    }
    return null;
  }

  ClientModel? _resolveKnownClient(ClientModel? candidate) {
    if (candidate == null) return null;
    if (candidate.id != null) {
      final byId = _clients
          .where((item) => item.id == candidate.id)
          .firstOrNull;
      return byId ?? candidate;
    }

    final normalizedName = _normalizeClientLookupValue(candidate.nombre);
    final normalizedPhone = candidate.normalizedPhone;
    final normalizedRnc = candidate.normalizedRnc;

    for (final client in _clients) {
      if (client.id == null) continue;
      if (normalizedRnc != null && client.normalizedRnc == normalizedRnc) {
        return client;
      }
      if (normalizedPhone != null &&
          client.normalizedPhone == normalizedPhone) {
        return client;
      }
      if (_normalizeClientLookupValue(client.nombre) == normalizedName) {
        return client;
      }
    }
    return null;
  }

  void _upsertClientInMemory(ClientModel client) {
    final currentIndex = _clients.indexWhere((item) => item.id == client.id);
    setState(() {
      if (currentIndex >= 0) {
        _clients[currentIndex] = client;
      } else {
        _clients.add(client);
      }
    });
  }

  Future<ClientModel?> _resolveOrCreateDefaultClient() async {
    final cachedDefault = _findDefaultClientIn(_clients);
    if (cachedDefault != null) return cachedDefault;

    final clients = await ClientsRepository.getAll();
    if (!mounted) return null;

    final repoDefault = _findDefaultClientIn(clients);
    if (repoDefault != null) {
      _upsertClientInMemory(repoDefault);
      return repoDefault;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final fallback = ClientModel(
      nombre: 'Consumidor Final',
      telefono: '8090000000',
      createdAtMs: now,
      updatedAtMs: now,
    );

    try {
      final newId = await ClientsRepository.create(fallback);
      final created = await ClientsRepository.getById(newId);
      if (!mounted) return created ?? fallback.copyWith(id: newId);
      final resolved = created ?? fallback.copyWith(id: newId);
      _upsertClientInMemory(resolved);
      return resolved;
    } catch (_) {
      final refreshed = await ClientsRepository.getAll();
      if (!mounted) return _findDefaultClientIn(refreshed);
      final restored = _findDefaultClientIn(refreshed);
      if (restored != null) {
        _upsertClientInMemory(restored);
      }
      return restored;
    }
  }

  Future<ClientModel?> _ensureDefaultCustomerSelected() async {
    final cart = _currentCart;
    final selectionRevision = _clientSelectionRevision;
    final selected = _resolveKnownClient(cart.selectedClient);

    if (selected != null && selected.id != null) {
      if (!identical(selected, cart.selectedClient)) {
        _updateCurrentCart(() {
          cart.selectedClient = selected;
        });
      }

      _syncClientFieldText();
      return selected;
    }

    final fallback = await _resolveOrCreateDefaultClient();

    if (!mounted || fallback == null || fallback.id == null) {
      return null;
    }

    if (_clientSelectionRevision != selectionRevision ||
        !identical(cart, _currentCart) ||
        cart.selectedClient != null) {
      return _resolveKnownClient(cart.selectedClient);
    }

    await _applySelectedClient(fallback, automatic: true, cart: cart);
    _syncClientFieldText(force: true);

    return fallback;
  }

  Future<void> _showQuickItemDialog() async {
    if (!mounted) return;

    setState(() => _isQuickSalePressed = true);

    final screenSize = MediaQuery.sizeOf(context);
    final ticketPanelConstraints = _ticketPanelConstraints(screenSize.width);

    final isTightDesktop = screenSize.width <= 1280 || screenSize.height <= 768;
    final isCompactDesktop =
        screenSize.width <= 1366 || screenSize.height <= 820;

    // Debe coincidir con el ancho del QuickItemDialog.
    final dialogWidth = isTightDesktop
        ? math.min(366.0, screenSize.width - 24)
        : isCompactDesktop
        ? math.min(386.0, screenSize.width - 24)
        : math.min(420.0, screenSize.width - 24);

    final rightOffset = ticketPanelConstraints.maxWidth + 8;

    final blurRightInset = ticketPanelConstraints.maxWidth;

    // No tapa el topbar.
    const blurTopOffset = 40.0;

    // No tapa footer/tabs inferiores.
    const footerSafeInset = 45.0;
    // Más hacia abajo, como en la referencia.
    final topOffset = math.max(72.0, screenSize.height * 0.10);

    final result = await showGeneralDialog<SaleItemModel>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Material(
          type: MaterialType.transparency,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: blurTopOffset,
                bottom: footerSafeInset,
                right: blurRightInset,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(dialogContext).maybePop(),
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                      child: Container(
                        color: const Color(0xFFF4F7FB).withOpacity(0.34),
                      ),
                    ),
                  ),
                ),
              ),

              Positioned(
                top: topOffset,
                right: rightOffset.clamp(
                  4.0,
                  screenSize.width - dialogWidth - 4,
                ),
                width: dialogWidth,
                child: const QuickItemDialog(),
              ),
            ],
          ),
        );
      },
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.08, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (mounted) {
      setState(() => _isQuickSalePressed = false);
    }

    if (!mounted || result == null) return;

    _updateCurrentCart(() {
      _currentCart.items.add(result);
    });
  }

  Future<void> _showNewProductDialog() async {
    if (!mounted) return;

    try {
      final categoriesRepo = CategoriesRepository();
      final suppliersRepo = SuppliersRepository();

      final results = await Future.wait([
        categoriesRepo.getAll(),
        suppliersRepo.getAll(),
      ]);

      if (!mounted) return;

      final categories = results[0] as List<CategoryModel>;
      final suppliers = results[1] as List<SupplierModel>;

      final screenSize = MediaQuery.sizeOf(context);
      final ticketPanelConstraints = _ticketPanelConstraints(screenSize.width);

      // Deja libre el panel derecho de factura.
      final blurRightInset = ticketPanelConstraints.maxWidth;

      // No tapa el topbar.
      const blurTopOffset = 40.0;

      // No tapa footer/tabs inferiores.
      const footerSafeInset = 45.0;

      final created = await showGeneralDialog<bool>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.transparent,
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: blurTopOffset,
                  bottom: footerSafeInset,
                  right: blurRightInset,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(dialogContext).maybePop(),
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                        child: Container(
                          color: const Color(0xFFF4F7FB).withOpacity(0.34),
                        ),
                      ),
                    ),
                  ),
                ),

                Center(
                  child: ProductFormDialog(
                    categories: categories,
                    suppliers: suppliers,
                  ),
                ),
              ],
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 220),
        transitionBuilder:
            (dialogContext, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );

              return FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
                  child: child,
                ),
              );
            },
      );

      if (created == true && mounted) {
        await _refreshCatalogAfterProductChanges();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Producto creado correctamente'),
            backgroundColor: status.success,
          ),
        );
      }
    } catch (e, st) {
      if (!mounted) return;

      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _showNewProductDialog,
        module: 'sales/new_product',
      );
    }
  }

  Future<void> _setSalesDocumentType(
    _SalesDocumentType type, {
    _Cart? cart,
  }) async {
    final targetCart = cart ?? _currentCart;
    if (type == _SalesDocumentType.consumidorFinal) {
      _updateCurrentCart(() {
        targetCart.documentType = type;
        targetCart.electronicInvoiceEnabled = false;
        targetCart.itbisEnabled = _isGlobalItbisEnabled;
      });
      return;
    }

    // El comprobante fiscal local no depende de la configuración e-CF.
    // La emisión electrónica se valida por separado al momento de cobrar.
    _updateCurrentCart(() {
      targetCart.documentType = type;
      targetCart.electronicInvoiceEnabled = false;
      targetCart.itbisEnabled = true;
    });
  }

  _SalesDocumentType get _currentSalesDocumentType => _currentCart.documentType;

  String _salesDocumentTypeLabel(_SalesDocumentType type) {
    switch (type) {
      case _SalesDocumentType.consumidorFinal:
        return 'Consumidor final (02)';
      case _SalesDocumentType.creditoFiscal:
        return 'Crédito fiscal (01)';
    }
  }

  void _openFacturaPage({int? saleId, bool openRefund = false}) {
    _closeClientSearchOverlay();
    if (_showRecentSalesPanel) {
      setState(() => _showRecentSalesPanel = false);
    }
    final query = <String, String>{
      if (saleId != null) 'saleId': '$saleId',
      if (openRefund) 'refund': '1',
    };
    final uri = Uri(
      path: '/factura',
      queryParameters: query.isEmpty ? null : query,
    );
    AuthzService.guardedAction(
      context,
      authz_perm.Permissions.salesHistoryView,
      () => context.go(uri.toString()),
      reason: 'Abrir factura',
      resourceType: 'route',
      resourceId: '/factura',
    )();
  }

  Future<void> _showRecentSaleRefundDialog(legacy_sales.SaleModel sale) async {
    try {
      final result = await showSaleRefundDialog(context, sale);
      if (!mounted || result == null) return;

      if (result == SaleRefundOutcome.refunded) {
        FullPosNotifications.success(
          'La devolución de ${sale.localCode} fue procesada correctamente.',
          title: 'Devolución completada',
          deduplicationKey: 'recent-sale-refunded-${sale.id}',
        );
      } else {
        FullPosNotifications.success(
          'La factura ${sale.localCode} fue anulada y el stock restaurado.',
          title: 'Factura anulada',
          deduplicationKey: 'recent-sale-cancelled-${sale.id}',
        );
      }

      await _loadRecentSales();
    } catch (error, stackTrace) {
      if (!mounted) return;
      await debug_log.DebugAppLogger.instance.error(
        'No se pudo abrir la devolución rápida',
        module: 'sales/recent_sales/refund',
        error: error,
        stackTrace: stackTrace,
      );
      final message = error.toString().replaceFirst('Exception: ', '').trim();
      FullPosNotifications.error(
        message.isEmpty
            ? 'No se pudo abrir la factura para devolución.'
            : message,
        title: 'Devolución no disponible',
        deduplicationKey: 'recent-refund-open-${sale.id}',
        actionLabel: 'Reintentar',
        onAction: () => _showRecentSaleRefundDialog(sale),
      );
    }
  }

  Future<void> _printRecentSale(legacy_sales.SaleModel sale) async {
    final saleId = sale.id;
    if (saleId == null) return;
    try {
      final settings = await PrinterSettingsRepository.getOrCreate();
      if (settings.selectedPrinterName == null ||
          settings.selectedPrinterName!.trim().isEmpty) {
        if (!mounted) return;
        FullPosNotifications.printer(
          'Configura una impresora antes de volver a intentarlo.',
          title: 'No hay impresora configurada',
          success: false,
          deduplicationKey: 'recent-sale-printer-not-configured',
        );
        return;
      }

      final items = await SalesRepository.getItemsBySaleId(saleId);
      final cashierName = await SessionManager.displayName() ?? 'Cajero';
      final result = await UnifiedTicketPrinter.printSaleTicket(
        sale: sale,
        items: items,
        cashierName: cashierName,
        overrideCopies: 1,
      );
      if (!mounted) return;
      FullPosNotifications.printer(
        result.success
            ? 'El ticket fue enviado correctamente.'
            : 'Revisa la impresora y vuelve a intentarlo.',
        title: result.success
            ? 'Ticket enviado a impresión'
            : 'No se pudo imprimir el ticket',
        success: result.success,
        deduplicationKey: 'recent-sale-print-$saleId-${result.success}',
        actionLabel: result.success ? null : 'Reintentar',
        onAction: result.success ? null : () => _printRecentSale(sale),
      );
    } catch (e, st) {
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => _printRecentSale(sale),
        module: 'sales/recent_sales/print',
      );
    }
  }

  String _recentSaleTitle(legacy_sales.SaleModel sale) {
    final code = sale.localCode.trim();
    final prefix = sale.electronicInvoiceEnabled == 1 ? 'e-Factura' : 'Factura';
    return '$prefix $code';
  }

  String _recentSaleStatusLabel(legacy_sales.SaleModel sale) {
    final statusLabel = switch (sale.status.toUpperCase()) {
      'REFUNDED' => 'Devuelta',
      'PARTIAL_REFUND' => 'Parcial',
      _ => 'Activa',
    };
    final documentLabel = sale.electronicInvoiceEnabled == 1
        ? 'electrónica'
        : 'no electrónica';
    return '$statusLabel · $documentLabel';
  }

  Future<T?> _showAnchoredPopover<T>({
    required BuildContext anchorContext,
    required double width,
    required double maxHeight,
    required Widget Function(BuildContext dialogContext, VoidCallback close)
    childBuilder,
  }) async {
    if (_anchoredPopoverOpen || !mounted) return null;
    _anchoredPopoverOpen = true;
    _closeClientSearchOverlay();

    final overlayState = Overlay.of(context, rootOverlay: true);
    final overlayBox = overlayState.context.findRenderObject() as RenderBox?;
    final targetBox = anchorContext.findRenderObject() as RenderBox?;
    if (overlayBox == null || targetBox == null) {
      _anchoredPopoverOpen = false;
      return null;
    }

    final targetTopLeft = targetBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final targetRect = targetTopLeft & targetBox.size;
    final size = overlayBox.size;
    const margin = 8.0;

    final effectiveWidth = math.min(width, size.width - margin * 2);
    final effectiveMaxHeight = math.min(maxHeight, size.height - margin * 2);

    final availableBelow = size.height - targetRect.bottom - margin;
    final showAbove = availableBelow < effectiveMaxHeight;

    final left = (targetRect.right - effectiveWidth)
        .clamp(margin, size.width - effectiveWidth - margin)
        .toDouble();

    final desiredTop = showAbove
        ? targetRect.top - effectiveMaxHeight - margin
        : targetRect.bottom + margin;
    final top = desiredTop
        .clamp(margin, size.height - effectiveMaxHeight - margin)
        .toDouble();

    try {
      return await showGeneralDialog<T>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: effectiveWidth,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: effectiveMaxHeight),
                    child: childBuilder(
                      dialogContext,
                      () => Navigator.of(
                        dialogContext,
                        rootNavigator: true,
                      ).maybePop(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        transitionBuilder:
            (dialogContext, animation, secondaryAnimation, child) {
              final fade = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              );
              return FadeTransition(
                opacity: fade,
                child: ScaleTransition(
                  scale: Tween(begin: 0.98, end: 1.0).animate(fade),
                  child: child,
                ),
              );
            },
      );
    } finally {
      _anchoredPopoverOpen = false;
    }
  }

  // ignore: unused_element
  Future<void> _showTotalDiscountDialog(BuildContext anchorContext) async {
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
      final currentType = _currentCart.discountTotalType == 'percent'
          ? DiscountType.percent
          : DiscountType.amount;
      _inlineTotalDiscountType = currentType;

      final value = _currentCart.discountTotalValue ?? 0.0;
      _inlineTotalDiscountController.text = value > 0
          ? value.toStringAsFixed(2)
          : '';
    });

    var requestedFocus = false;

    Future<void> applyAndClose(VoidCallback close) async {
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
      close();
    }

    await _showAnchoredPopover<void>(
      anchorContext: anchorContext,
      width: 360,
      maxHeight: 170,
      childBuilder: (dialogContext, close) {
        return StatefulBuilder(
          builder: (context, setPopoverState) {
            if (!requestedFocus) {
              requestedFocus = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                _inlineTotalDiscountFocusNode.requestFocus();
                _inlineTotalDiscountController.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _inlineTotalDiscountController.text.length,
                );
              });
            }

            final hasCurrentDiscount =
                (_currentCart.discountTotalValue ?? 0.0) > 0.0;

            final subtotal = _currentCart.calculateSubtotal();
            final raw =
                double.tryParse(_inlineTotalDiscountController.text) ?? 0.0;
            final discountAmount = _computeTotalDiscountAmount(
              subtotal,
              _inlineTotalDiscountType,
              raw,
            );
            final after = (subtotal - discountAmount).clamp(
              0.0,
              double.infinity,
            );
            final itbis = _currentCart.itbisEnabled
                ? after * _currentCart.itbisRate
                : 0.0;
            final previewTotal = after + itbis;

            return Material(
              color: scheme.surface,
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
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
                            setPopoverState(() {
                              _inlineTotalDiscountType = i == 0
                                  ? DiscountType.percent
                                  : DiscountType.amount;
                            });
                          },
                          borderRadius: BorderRadius.circular(10),
                          constraints: const BoxConstraints(
                            minHeight: 30,
                            minWidth: 48,
                          ),
                          borderColor: scheme.outlineVariant,
                          selectedBorderColor: scheme.primary.withOpacity(0.35),
                          color: salesDetailMutedTextColor,
                          selectedColor: scheme.primary,
                          fillColor: scheme.primary.withOpacity(0.10),
                          children: const [
                            Text(
                              '%',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              'RD\$',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          CurrencyDisplay.format(
                            previewTotal,
                            decimalDigits: 2,
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                          ),
                        ),
                        if (hasCurrentDiscount) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () {
                              _removeInlineTotalDiscount();
                              close();
                            },
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
                            height: 30,
                            child: TextField(
                              controller: _inlineTotalDiscountController,
                              focusNode: _inlineTotalDiscountFocusNode,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                                  borderSide: BorderSide(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: scheme.outlineVariant,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: scheme.primary.withOpacity(0.45),
                                  ),
                                ),
                              ),
                              onChanged: (_) => setPopoverState(() {}),
                              onSubmitted: (_) =>
                                  unawaited(applyAndClose(close)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => unawaited(applyAndClose(close)),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: scheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: scheme.primary.withOpacity(0.22),
                              ),
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
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showItemEditPopover(
    BuildContext anchorContext,
    int index, {
    required _InlineItemFocus focus,
  }) async {
    if (index < 0 || index >= _currentCart.items.length) return;

    setState(() {
      _selectedCartItemIndex = index;
    });

    final item = _currentCart.items[index];

    var discountType = DiscountType.amount;
    _inlineQtyController.text = _formatQtyForInlineEditor(item.qty);
    _inlineLineDiscountController.text = item.discountLine > 0
        ? item.discountLine.toStringAsFixed(2)
        : '';

    var requestedFocus = false;

    await _showAnchoredPopover<void>(
      anchorContext: anchorContext,
      width: 480,
      maxHeight: 260,
      childBuilder: (dialogContext, close) {
        return StatefulBuilder(
          builder: (context, setPopoverState) {
            if (!requestedFocus) {
              requestedFocus = true;
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

            final hasDiscount =
                (double.tryParse(_inlineLineDiscountController.text) ?? 0) > 0;

            void setQty(double qty) {
              final text = _formatQtyForInlineEditor(qty);
              _inlineQtyController.text = text;
              _inlineQtyController.selection = TextSelection(
                baseOffset: 0,
                extentOffset: text.length,
              );
              setPopoverState(() {});
            }

            Future<void> applyAndClose() async {
              final qty = double.tryParse(_inlineQtyController.text);
              if (qty == null || qty <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Cantidad inválida'),
                    backgroundColor: scheme.error,
                  ),
                );
                return;
              }

              if (index < 0 || index >= _currentCart.items.length) {
                close();
                return;
              }

              final current = _currentCart.items[index];
              final discountAmount = _computeLineDiscountAmount(
                qty: qty,
                unitPrice: current.unitPrice,
                type: discountType,
                rawText: _inlineLineDiscountController.text,
              );

              _updateCurrentCart(() {
                if (index < 0 || index >= _currentCart.items.length) return;
                final latest = _currentCart.items[index];
                _currentCart.items[index] = latest.copyWith(
                  qty: qty,
                  discountLine: discountAmount,
                );
              });

              close();
            }

            return Material(
              color: Colors.white,
              elevation: 16,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.productNameSnapshot,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: salesDetailTextColor,
                              height: 1.2,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: close,
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: Icon(
                              Icons.close,
                              size: 20,
                              color: salesDetailMutedTextColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Cantidad',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: salesDetailMutedTextColor,
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          height: 36,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () {
                                  final currentQty =
                                      double.tryParse(
                                        _inlineQtyController.text,
                                      ) ??
                                      item.qty;
                                  setQty((currentQty - 1).clamp(1.0, 999999));
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.remove,
                                    size: 18,
                                    color: salesDetailTextColor.withOpacity(
                                      0.86,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              SizedBox(
                                width: 90,
                                height: 36,
                                child: TextField(
                                  controller: _inlineQtyController,
                                  focusNode: _inlineQtyFocusNode,
                                  textAlign: TextAlign.center,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,3}'),
                                    ),
                                  ],
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: salesDetailTextColor,
                                    height: 1.0,
                                  ),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF8FAFC),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: scheme.primary.withOpacity(0.55),
                                      ),
                                    ),
                                  ),
                                  onChanged: (_) => setPopoverState(() {}),
                                  onSubmitted: (_) =>
                                      unawaited(applyAndClose()),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  final currentQty =
                                      double.tryParse(
                                        _inlineQtyController.text,
                                      ) ??
                                      item.qty;
                                  setQty((currentQty + 1).clamp(1.0, 999999));
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.add,
                                    size: 18,
                                    color: salesDetailTextColor.withOpacity(
                                      0.86,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Descuento',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: salesDetailMutedTextColor,
                          ),
                        ),
                        const Spacer(),
                        if (hasDiscount)
                          InkWell(
                            onTap: () {
                              _inlineLineDiscountController.text = '';
                              setPopoverState(() {});
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: Icon(
                                Icons.close,
                                size: 20,
                                color: scheme.error.withOpacity(0.85),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ToggleButtons(
                          isSelected: [
                            discountType == DiscountType.percent,
                            discountType == DiscountType.amount,
                          ],
                          onPressed: (i) {
                            setPopoverState(() {
                              discountType = i == 0
                                  ? DiscountType.percent
                                  : DiscountType.amount;
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          constraints: const BoxConstraints(
                            minHeight: 34,
                            minWidth: 56,
                          ),
                          borderColor: const Color(0xFFE2E8F0),
                          selectedBorderColor: scheme.primary.withOpacity(0.35),
                          color: salesDetailMutedTextColor,
                          selectedColor: scheme.primary,
                          fillColor: scheme.primary.withOpacity(0.10),
                          children: const [
                            Text(
                              '%',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              'RD\$',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 36,
                            child: TextField(
                              controller: _inlineLineDiscountController,
                              focusNode: _inlineLineDiscountFocusNode,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}'),
                                ),
                              ],
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: salesDetailTextColor,
                                height: 1.0,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE2E8F0),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFE2E8F0),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                    color: scheme.primary.withOpacity(0.55),
                                  ),
                                ),
                              ),
                              onChanged: (_) => setPopoverState(() {}),
                              onSubmitted: (_) => unawaited(applyAndClose()),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => unawaited(applyAndClose()),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: scheme.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: scheme.primary.withOpacity(0.22),
                              ),
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
              ),
            );
          },
        );
      },
    );
  }

  bool _isValidTotalDiscount(double subtotal, DiscountType type, double value) {
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

  void _removeInlineTotalDiscount() {
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
      _currentCart.discountTotalType = result.type == DiscountType.percent
          ? 'percent'
          : 'amount';
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
    _clientSelectionRevision++;
    _updateCurrentCart(() {
      _currentCart.selectedClient = null;
    });
    _clientSearchQuery = '';
    _scheduleClientFieldSync();
    unawaited(_ensureDefaultCustomerSelected());
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
      FullPosNotifications.error(
        'El producto no tiene un identificador válido.',
        title: 'No se pudo agregar el producto',
        deduplicationKey: 'invalid-product-${product.code}',
      );
      return;
    }

    final qtyInCart = _qtyInCart(product.id);
    final effectiveStock = product.stock - qtyInCart;
    if (effectiveStock <= 0) {
      FullPosNotifications.inventory(
        '${product.name} no tiene unidades disponibles.',
        title: 'Producto sin stock',
        deduplicationKey: 'out-of-stock-${product.id}',
      );
      return;
    }

    try {
      _updateCurrentCart(() {
        _currentCart.addProduct(product);
        final animatedIndex = _currentCart.items.lastIndexWhere(
          (item) => item.productId == product.id,
        );
        if (animatedIndex >= 0) {
          _triggerCartItemEntryAnimation(animatedIndex);
        }
      });
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
      FullPosNotifications.error(
        'Intenta nuevamente o actualiza el catálogo.',
        title: 'No se pudo agregar el producto',
        deduplicationKey: 'add-product-error-${product.id}',
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
      FullPosNotifications.inventory(
        'No hay más unidades de ${product.name} para agregar.',
        title: 'Stock insuficiente',
        deduplicationKey: 'insufficient-stock-${product.id}',
      );
      return;
    }

    if (!mounted) return;
    _updateCurrentCart(() => _currentCart.updateQuantity(index, item.qty + 1));
  }

  void _openInlineItemEditor(
    SaleItemModel item,
    int index, {
    required _InlineItemFocus focus,
  }) {
    unawaited(_showItemEditPopover(context, index, focus: focus));
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

  Future<List<String>> _missingElectronicInvoiceRequirements({
    required bool includeItbis,
  }) async {
    final missing = <String>[];

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
    if (!_isGlobalItbisEnabled) {
      FullPosNotifications.error(
        'Activa el ITBIS en Configuración para emitir un e-CF.',
        title: 'Facturación electrónica no disponible',
        deduplicationKey: 'ecf-itbis-disabled',
      );
      return false;
    }

    if (!_isElectronicInvoicingFeatureEnabled) {
      FullPosNotifications.error(
        'La facturación electrónica está desactivada en Configuración.',
        title: 'e-CF desactivado',
        deduplicationKey: 'ecf-feature-disabled',
      );
      return false;
    }

    final missing = await _missingElectronicInvoiceRequirements(
      includeItbis: false,
    );

    if (missing.isEmpty) return true;

    FullPosNotifications.error(
      'Completa: ${missing.join(', ')}.',
      title: 'Faltan datos para emitir e-CF',
      deduplicationKey: 'ecf-missing-${missing.join('|')}',
      isPersistent: true,
    );
    return false;
  }

  Future<bool> _canProceedWithElectronicInvoiceOrNotify() async {
    if (!_currentCart.electronicInvoiceEnabled) return true;

    final missing = await _missingElectronicInvoiceRequirements(
      includeItbis: true,
    );

    if (missing.isEmpty) return true;

    FullPosNotifications.error(
      'Completa: ${missing.join(', ')}.',
      title: 'No se puede continuar con e-CF',
      deduplicationKey: 'ecf-proceed-missing-${missing.join('|')}',
      isPersistent: true,
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
          onSelectClient: _showClientPicker,
          onCreateClient: _showCreateClientFromSales,
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

      await WidgetsBinding.instance.endOfFrame;
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
      if (!mounted) return;

      final electronicInvoiceRequested =
          paymentResult['electronicInvoiceRequested'] == true;
      final effectiveClient = paymentResult['selectedClient'] as ClientModel?;

      if (!mounted) return;
      if (electronicInvoiceRequested &&
          !await _canEnableElectronicInvoiceOrNotify()) {
        return;
      }

      if (effectiveClient != null) {
        _updateCurrentCart(() {
          _currentCart.selectedClient = effectiveClient;
        });
        if (effectiveClient.id != null) {
          _clients.removeWhere((client) => client.id == effectiveClient.id);
          _clients.add(effectiveClient);
        }
      } else if (!electronicInvoiceRequested) {
        _updateCurrentCart(() {});
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
      if (electronicInvoiceRequested) {
        electronicDocumentType =
            _currentSalesDocumentType == _SalesDocumentType.creditoFiscal
            ? '31'
            : '32';
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
      final selectedClientTaxId = (effectiveClient?.rnc ?? '').trim().isNotEmpty
          ? effectiveClient?.rnc
          : effectiveClient?.cedula;
      final resolvedCustomerName =
          effectiveClient?.nombre ??
          (electronicInvoiceRequested
              ? 'Consumidor final'
              : _currentCart.selectedClient?.nombre);
      final resolvedCustomerPhone = effectiveClient?.telefono;
      final resolvedCustomerId = effectiveClient?.id;
      final fiscalReceiptTypeId = _currentCart.fiscalReceiptTypeId;
      if (_fiscalReceiptSettings.enabled && fiscalReceiptTypeId != null) {
        final fiscalType = _fiscalReceiptTypes
            .where((type) => type.id == fiscalReceiptTypeId)
            .firstOrNull;
        if (fiscalType == null || !fiscalType.isAvailable) {
          FullPosNotifications.error(
            'El comprobante seleccionado no está disponible.',
            title: 'Comprobante fiscal',
            deduplicationKey: 'ncf-type-unavailable',
          );
          return;
        }
        if (fiscalType.requiresCustomerTaxId &&
            (selectedClientTaxId ?? '').trim().isEmpty) {
          FullPosNotifications.error(
            'Este comprobante requiere cliente con RNC/Cédula.',
            title: 'Comprobante fiscal',
            deduplicationKey: 'ncf-customer-tax-id-required',
          );
          return;
        }
        if (fiscalType.requiresCustomerName &&
            (resolvedCustomerName ?? '').trim().isEmpty) {
          FullPosNotifications.error(
            'Este comprobante requiere nombre fiscal del cliente.',
            title: 'Comprobante fiscal',
            deduplicationKey: 'ncf-customer-name-required',
          );
          return;
        }
      }
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
            electronicInvoiceEnabled: electronicInvoiceRequested,
            electronicInvoiceCode: electronicInvoiceCode,
            electronicDocumentType: electronicDocumentType,
            sessionId: activeShiftIdAfterDialog,
            customerId: resolvedCustomerId,
            customerName: resolvedCustomerName,
            customerPhone: resolvedCustomerPhone,
            customerRnc: selectedClientTaxId,
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
            customerId: resolvedCustomerId,
            customerName: resolvedCustomerName,
            customerPhone: resolvedCustomerPhone,
            customerRnc: selectedClientTaxId,
            electronicInvoiceCode: electronicInvoiceCode,
            electronicDocumentType: electronicDocumentType,
            electronicInvoiceEnabled: electronicInvoiceRequested,
            fiscalReceiptTypeId: fiscalReceiptTypeId,
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
            customerId: resolvedCustomerId,
            customerName: resolvedCustomerName,
            customerPhone: resolvedCustomerPhone,
            customerRnc: selectedClientTaxId,
            electronicInvoiceCode: electronicInvoiceCode,
            electronicDocumentType: electronicDocumentType,
            electronicInvoiceEnabled: electronicInvoiceRequested,
            fiscalReceiptTypeId: fiscalReceiptTypeId,
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

      final refreshedFiscalTypes = _fiscalReceiptSettings.enabled
          ? await FiscalReceiptRepository.getActiveTypes()
          : _fiscalReceiptTypes;

      if (!mounted) return;
      setState(() {
        _fiscalReceiptTypes = refreshedFiscalTypes;
        if (cartIndexToRemove >= 0 && cartIndexToRemove < _carts.length) {
          _carts[cartIndexToRemove].isCompleted = true;
          _carts.removeAt(cartIndexToRemove);
        }

        if (_carts.isNotEmpty) {
          _currentCartIndex = 0;
        } else {
          final cart = _Cart(name: 'Venta principal');
          _applySalesDefaultsToCart(cart);
          _carts.add(cart);
          _currentCartIndex = 0;
        }
        _selectedCartItemIndex = null;
        _rebuildQtyIndexForCurrentCart();
      });
      _handleCurrentCartChanged();

      unawaited(_loadRecentSales());

      FullPosNotifications.show(
        type: AppNotificationType.payment,
        title: 'Venta completada',
        message: 'La venta $localCode fue registrada correctamente.',
        deduplicationKey: 'sale-completed-$saleId',
        duration: const Duration(seconds: 4),
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
      'document:${cart.documentType.name}',
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Se difiere el clear para evitar modificar un provider de Riverpod
    // mientras el widget tree se está destruyendo.
    Future(() {
      _footerTicketController?.clear();
    });
    _footerTicketController = null;
    TopbarActionBus.salesMovementToggle.removeListener(
      _handleMovementPanelToggle,
    );
    RawKeyboard.instance.removeListener(_handleScannerKey);
    HardwareKeyboard.instance.removeHandler(_globalShortcutHandler);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _clientFocusNode.dispose();
    _clientSearchOverlay?.remove();
    _clientSearchController.dispose();
    _clientSearchFocusNode.removeListener(_handleClientSearchFocus);
    _clientSearchFocusNode.dispose();
    for (final entry in _transientOverlayEntries.toList()) {
      if (entry.mounted) entry.remove();
    }
    _transientOverlayEntries.clear();
    _ticketItemsScrollController.dispose();
    _inlineQtyController.dispose();
    _inlineLineDiscountController.dispose();
    _inlineQtyFocusNode.dispose();
    _inlineLineDiscountFocusNode.dispose();
    _inlineTotalDiscountController.dispose();
    _inlineTotalDiscountFocusNode.dispose();
    _scanner?.dispose();
    _cartPersistenceTimer?.cancel();
    _categorySidebarCollapseTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveAllCartsToDatabase());
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncFooterTicketsDeferred();
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
    ref.listen<BusinessSettings>(businessSettingsProvider, (previous, next) {
      final rateChanged =
          previous == null ||
          (previous.defaultTaxRate - next.defaultTaxRate).abs() > 0.0001;
      final enabledChanged =
          previous == null || previous.itbisEnabled != next.itbisEnabled;
      if (!rateChanged && !enabledChanged) {
        return;
      }

      final nextRate = _normalizeItbisRate(next.defaultTaxRate);
      var changed = false;
      for (final cart in _carts) {
        if ((cart.itbisRate - nextRate).abs() > 0.0001) {
          cart.itbisRate = nextRate;
          changed = true;
        }
        if (cart.itbisEnabled != next.itbisEnabled) {
          cart.itbisEnabled = next.itbisEnabled;
          changed = true;
        }
        if (!next.itbisEnabled && cart.electronicInvoiceEnabled) {
          cart.electronicInvoiceEnabled = false;
          cart.documentType = _SalesDocumentType.consumidorFinal;
          changed = true;
        }
      }

      if (!changed || !mounted) return;
      setState(() {});
    });

    final activeSessionAsync = ref.watch(activeSessionControllerProvider);
    final hasActiveSession = activeSessionAsync.valueOrNull != null;
    final showCashClosedOverlay =
        !activeSessionAsync.isLoading &&
        !hasActiveSession &&
        !_sessionBootstrapScheduled;

    final Map<ShortcutActivator, Intent> optionalShortcuts =
        _keyboardShortcutsEnabled
        ? <ShortcutActivator, Intent>{
            LogicalKeySet(LogicalKeyboardKey.f2):
                const FocusSearchProductIntent(),
            LogicalKeySet(LogicalKeyboardKey.f3):
                const FocusSearchClientIntent(),
            LogicalKeySet(LogicalKeyboardKey.f4): const NewClientIntent(),
            LogicalKeySet(LogicalKeyboardKey.f6):
                const OpenTicketSelectorIntent(),
            LogicalKeySet(LogicalKeyboardKey.f7): const OpenManualSaleIntent(),
            LogicalKeySet(LogicalKeyboardKey.f8): const OpenPaymentIntent(),
            LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.f8):
                const FinalizeSaleIntent(),
            LogicalKeySet(LogicalKeyboardKey.f9): const ApplyDiscountIntent(),
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
        : const <ShortcutActivator, Intent>{};

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
              await _showCreateClientFromSales();
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
                  final metrics = _salesMetricsFor(
                    Size(constraints.maxWidth, constraints.maxHeight),
                  );
                  final categoryCollapsedWidth =
                      _categorySidebarCollapsedWidthFor(context);
                  final categoryExpandedWidth =
                      _categorySidebarExpandedWidthFor(context);

                  final ticketPanelConstraints = _ticketPanelConstraints(
                    constraints.maxWidth,
                  );

                  final recentPanelWidth = ticketPanelConstraints.maxWidth;
                  const panelGap = 0.0;

                  final theme = Theme.of(context);
                  final salesProducts = theme.extension<SalesProductsTheme>();
                  final gridCanvasColor = _gridCanvasColor(context);

                  final gridCardColor =
                      (salesProducts?.cardBackgroundColor.opacity ?? 0) == 0
                      ? theme.cardColor
                      : salesProducts!.cardBackgroundColor;

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
                      // ─────────────────────────────────────────────────────────
                      // CONTENIDO PRINCIPAL DE VENTAS
                      // ─────────────────────────────────────────────────────────
                      Container(
                        color: _allegraBackgroundColor,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_categories.isNotEmpty)
                              SizedBox(width: categoryCollapsedWidth),

                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                  metrics.catalogLeftPadding,
                                  0,
                                  0,
                                  0,
                                ),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: EdgeInsets.only(
                                        top: metrics.controlBarTopPadding,
                                      ),
                                      child: _build3DControlBar(
                                        metrics: metrics,
                                      ),
                                    ),

                                    SizedBox(
                                      height: metrics.spaceBelowControlBar,
                                    ),

                                    Expanded(
                                      child: Container(
                                        color: gridCanvasColor,
                                        child: Column(
                                          children: [
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
                                                                    .isEmpty &&
                                                                _searchController
                                                                    .text
                                                                    .trim()
                                                                    .isNotEmpty) {
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
                                                                      'Intenta buscar con otro término o cambia el filtro',
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

                                                            return LayoutBuilder(
                                                              builder:
                                                                  (
                                                                    context,
                                                                    gridConstraints,
                                                                  ) {
                                                                    final gridMetrics = _productGridMetricsFor(
                                                                      gridConstraints
                                                                          .maxWidth,
                                                                      metrics,
                                                                    );

                                                                    final totalItems =
                                                                        products
                                                                            .length +
                                                                        1;

                                                                    return GridView.builder(
                                                                      padding: EdgeInsets.only(
                                                                        top:
                                                                            metrics.isTightDesktop
                                                                            ? 2
                                                                            : metrics.isCompactDesktop
                                                                            ? 2
                                                                            : 1,
                                                                        right: metrics
                                                                            .productHorizontalMargin,
                                                                      ),
                                                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                                        crossAxisCount:
                                                                            gridMetrics.crossAxisCount,
                                                                        mainAxisExtent:
                                                                            gridMetrics.tileHeight,
                                                                        crossAxisSpacing:
                                                                            0,
                                                                        mainAxisSpacing:
                                                                            0,
                                                                      ),
                                                                      itemCount:
                                                                          totalItems,
                                                                      itemBuilder:
                                                                          (
                                                                            context,
                                                                            index,
                                                                          ) {
                                                                            if (index ==
                                                                                0) {
                                                                              return Padding(
                                                                                padding: EdgeInsets.fromLTRB(
                                                                                  metrics.productHorizontalMargin,
                                                                                  metrics.productVerticalMargin +
                                                                                      1,
                                                                                  metrics.productHorizontalMargin,
                                                                                  metrics.productVerticalMargin,
                                                                                ),
                                                                                child: Align(
                                                                                  alignment: Alignment.topCenter,
                                                                                  child: SizedBox(
                                                                                    width: gridMetrics.tileWidth,
                                                                                    child: _buildQuickSaleCard(
                                                                                      index: index,
                                                                                      cardSize: metrics.productCardHeight,
                                                                                      metrics: metrics,
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                              );
                                                                            }

                                                                            return Padding(
                                                                              padding: EdgeInsets.fromLTRB(
                                                                                metrics.productHorizontalMargin,
                                                                                metrics.productVerticalMargin +
                                                                                    1,
                                                                                metrics.productHorizontalMargin,
                                                                                metrics.productVerticalMargin,
                                                                              ),
                                                                              child: Align(
                                                                                alignment: Alignment.topCenter,
                                                                                child: SizedBox(
                                                                                  width: gridMetrics.tileWidth,
                                                                                  child: _buildModernProductCard(
                                                                                    products[index -
                                                                                        1],
                                                                                    index: index,
                                                                                    cardSize: metrics.productCardHeight,
                                                                                    metrics: metrics,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            );
                                                                          },
                                                                    );
                                                                  },
                                                            );
                                                          })(),
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

                            // ─────────────────────────────────────────────────────
                            // PANEL DERECHO DE LA VENTA
                            // ─────────────────────────────────────────────────────
                            ConstrainedBox(
                              constraints: ticketPanelConstraints,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  border: Border(
                                    left: BorderSide(
                                      color: Color(0xFFCBD5E1),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    return FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween<Offset>(
                                          begin: const Offset(0.08, 0),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: child,
                                      ),
                                    );
                                  },
                                  child: _showMovementPanel
                                      ? _buildMovementPanel()
                                      : _buildTicketPanel(metrics: metrics),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_categories.isNotEmpty)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: _isCategorySidebarExpanded
                              ? categoryExpandedWidth
                              : categoryCollapsedWidth,
                          child: _buildCategorySidebar(),
                        ),

                      // ─────────────────────────────────────────────────────────
                      // BLOQUEO DE CAJA CERRADA
                      // ─────────────────────────────────────────────────────────
                      if (showCashClosedOverlay) _buildCashClosedOverlay(),

                      // ─────────────────────────────────────────────────────────
                      // BARRERA PARA CERRAR VENTAS RECIENTES
                      // ─────────────────────────────────────────────────────────
                      if (_showRecentSalesPanel)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: _closeRecentSalesPanel,
                            child: const SizedBox.expand(),
                          ),
                        ),

                      // ─────────────────────────────────────────────────────────
                      // PANEL DE VENTAS RECIENTES
                      // ─────────────────────────────────────────────────────────
                      if (_showRecentSalesPanel)
                        Positioned(
                          top: 0,
                          right: 0,
                          bottom: 0,
                          width: recentPanelWidth,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 1, end: 0),
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(recentPanelWidth * value, 0),
                                child: Opacity(
                                  opacity: (1 - value).clamp(0.0, 1.0),
                                  child: child,
                                ),
                              );
                            },
                            child: Material(
                              color: Colors.white,
                              elevation: 18,
                              shadowColor: const Color(
                                0xFF0F172A,
                              ).withOpacity(0.20),
                              child: DecoratedBox(
                                decoration: const BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color: Color(0xFFCBD5E1),
                                      width: 1,
                                    ),
                                  ),
                                ),
                                child: _buildRecentSalesPanel(),
                              ),
                            ),
                          ),
                        ),

                      if (_showRecentSalesPanel)
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: SizedBox(
                              height: 1,
                              child: ColoredBox(color: Color(0xFFB8C4D1)),
                            ),
                          ),
                        ),

                      // ─────────────────────────────────────────────────────────
                      // BORDE INFERIOR DEL TOPBAR
                      //
                      // Debe permanecer al FINAL del Stack para que ningún
                      // contenedor de la pantalla pueda pintarse encima.
                      // ─────────────────────────────────────────────────────────
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: SizedBox(
                            height: 0.3,
                            child: ColoredBox(color: Color(0xFF7C8A99)),
                          ),
                        ),
                      ),
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

  // ignore: unused_element
  Widget _buildProductCard(
    ProductModel product, {
    required int index,
    required double cardSize,
  }) {
    final qtyInCart = _qtyInCart(product.id);
    final effectiveStock = product.stock - qtyInCart;
    final isCriticalStock = effectiveStock <= 1;
    final isLowStock = effectiveStock > 1 && effectiveStock <= 10;
    final isOutOfStock = effectiveStock <= 0;
    final stockColor = isOutOfStock
        ? scheme.error
        : (isCriticalStock
              ? scheme.error
              : (isLowStock ? status.warning : status.success));
    final theme = Theme.of(context);
    final salesProducts = theme.extension<SalesProductsTheme>();
    final rawPrice = product.salePrice;
    final formattedPrice = (rawPrice % 1 == 0)
        ? rawPrice.toStringAsFixed(0)
        : rawPrice.toStringAsFixed(2);
    final isHovered = _hoveredProductIndexes.contains(index);
    final stockLabel = isOutOfStock
        ? 'Sin stock'
        : isCriticalStock
        ? 'Ultima unidad'
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
    final codeColor = cardTextColor.withOpacity(0.74);

    return MouseRegion(
      onEnter: (_) =>
          _setHoverStateDeferred(_hoveredProductIndexes, index, true),
      onExit: (_) =>
          _setHoverStateDeferred(_hoveredProductIndexes, index, false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
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
                                fontWeight: FontWeight.w500,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: product.code.toUpperCase(),
                                    style: TextStyle(
                                      color: codeColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '  •  ',
                                    style: TextStyle(
                                      color: codeColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  TextSpan(
                                    text: stockLabel,
                                    style: TextStyle(
                                      color: stockColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                              fontWeight: FontWeight.w500,
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
                              fontWeight: FontWeight.w600,
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

  Widget _buildModernProductCard(
    ProductModel product, {
    required int index,
    required double cardSize,
    required _SalesResponsiveMetrics metrics,
  }) {
    final m = metrics;
    final qtyInCart = _qtyInCart(product.id);
    final effectiveStock = product.stock - qtyInCart;
    final isCriticalStock = effectiveStock <= 1;
    final isLowStock = effectiveStock > 1 && effectiveStock <= 10;
    final isOutOfStock = effectiveStock <= 0;
    final isSelected = qtyInCart > 0;

    final stockColor = isOutOfStock
        ? scheme.error
        : isCriticalStock
        ? scheme.error
        : isLowStock
        ? status.warning
        : status.success;

    final theme = Theme.of(context);
    final salesProducts = theme.extension<SalesProductsTheme>();
    final rawPrice = product.salePrice;

    final formattedPrice = rawPrice % 1 == 0
        ? rawPrice.toStringAsFixed(0)
        : rawPrice.toStringAsFixed(2);

    final isHovered = _hoveredProductIndexes.contains(index);

    final nameColor = (salesProducts?.cardTextColor.opacity ?? 0) == 0
        ? scheme.onSurface
        : salesProducts!.cardTextColor;

    final priceColorResolved = nameColor;
    final tealAccent = isOutOfStock ? scheme.error : _allegraAccentColor;

    final stockLabel = isOutOfStock
        ? 'Sin stock'
        : 'Disp. ${effectiveStock.toInt()}';

    final displayPrice = 'RD\$$formattedPrice';

    final cardBorderColor = isSelected
        ? tealAccent.withOpacity(0.55)
        : isHovered
        ? tealAccent.withOpacity(0.45)
        : const Color(0xFFE2E8F0);

    final cardShadowColor = tealAccent.withOpacity(isHovered ? 0.15 : 0.055);

    const cardRadius = BorderRadius.only(
      topLeft: Radius.circular(28),
      topRight: Radius.circular(7),
      bottomLeft: Radius.circular(7),
      bottomRight: Radius.circular(28),
    );

    final isCompact = m.isCompactDesktop;
    final imageSize = m.productImageSize;
    final imageBoxSize = m.productImageBoxSize;
    final nameFontSize = m.productNameFontSize;
    final priceFontSize = m.productPriceFontSize;
    final nameBlockHeight = isCompact ? 33.0 : 37.0;
    final priceBlockHeight = isCompact ? 19.0 : 22.0;
    final cardPadding = isCompact
        ? const EdgeInsets.fromLTRB(14, 9, 14, 7)
        : const EdgeInsets.fromLTRB(18, 12, 18, 9);
    final imageContainerHoverSize = isHovered
        ? (isCompact ? imageBoxSize + 4 : imageBoxSize + 4)
        : imageBoxSize;

    return MouseRegion(
      cursor: isOutOfStock
          ? SystemMouseCursors.forbidden
          : SystemMouseCursors.click,
      onEnter: (_) {
        setState(() {
          _hoveredProductIndexes.add(index);
        });
      },
      onExit: (_) {
        setState(() {
          _hoveredProductIndexes.remove(index);
        });
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, isHovered ? -3 : 0, 0),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFF8FBFF) : Colors.white,
              borderRadius: cardRadius,
              border: Border.all(
                color: cardBorderColor,
                width: isSelected ? 1.15 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: cardShadowColor,
                  blurRadius: isHovered ? 16 : 8,
                  spreadRadius: isHovered ? 0.5 : 0,
                  offset: Offset(0, isHovered ? 7 : 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: cardRadius,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: cardRadius,
                  onTap: isOutOfStock ? null : () => _addProductToCart(product),
                  hoverColor: tealAccent.withOpacity(0.035),
                  highlightColor: tealAccent.withOpacity(0.025),
                  splashColor: tealAccent.withOpacity(0.10),
                  child: SizedBox(
                    height: cardSize,
                    child: Padding(
                      padding: cardPadding,
                      child: Column(
                        children: [
                          const SizedBox(height: 4),
                          Expanded(
                            child: Column(
                              children: [
                                SizedBox(height: isCompact ? 4 : 8),
                                Expanded(
                                  child: Center(
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      width: imageContainerHoverSize,
                                      height: imageContainerHoverSize,
                                      child: Center(
                                        child: ProductThumbnail.fromProduct(
                                          product,
                                          size: imageSize,
                                          width: imageSize,
                                          height: imageSize,
                                          borderRadius: BorderRadius.circular(
                                            isCompact ? 14 : 16,
                                          ),
                                          showBorder: false,
                                          showShadow: false,
                                          placeholderBackgroundColor:
                                              Colors.transparent,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: isCompact ? 8 : 12),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                stockLabel,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isOutOfStock ? stockColor : tealAccent,
                                  fontSize: isCompact ? 10.5 : 11,
                                  fontWeight: FontWeight.w600,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: nameBlockHeight,
                                width: double.infinity,
                                child: Center(
                                  child: Text(
                                    product.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false,
                                    style: TextStyle(
                                      color: nameColor.withOpacity(
                                        isOutOfStock ? 0.62 : 1,
                                      ),
                                      fontSize: nameFontSize,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'Inter',
                                      height: 1.1,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(
                                height: priceBlockHeight,
                                width: double.infinity,
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Text(
                                    displayPrice,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: priceColorResolved.withOpacity(
                                        isOutOfStock ? 0.72 : 1,
                                      ),
                                      fontSize: priceFontSize,
                                      fontWeight: FontWeight.w800,
                                      fontFamily: 'Inter',
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
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

          Positioned(
            top: 0,
            right: 0,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _toggleProductFeatured(product),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(7),
                  bottomLeft: Radius.circular(12),
                ),
                child: Ink(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: tealAccent,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(7),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                  child: Icon(
                    product.isFeatured
                        ? Icons.push_pin_rounded
                        : Icons.push_pin_outlined,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),
            ),
          ),

          if (isSelected)
            Positioned(
              top: isCompact ? -6 : -12,
              right: isCompact ? -6 : -12,
              child: Container(
                width: isCompact ? 26 : 30,
                height: isCompact ? 26 : 30,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: tealAccent.withOpacity(0.78),
                    width: 1.35,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tealAccent.withOpacity(0.13),
                      blurRadius: 8,
                      spreadRadius: -3,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    qtyInCart.toInt().toString(),
                    style: TextStyle(
                      color: tealAccent,
                      fontSize: isCompact ? 11 : 12,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),

          Positioned(
            top: 14,
            left: 14,
            child: IgnorePointer(
              child: Text(
                product.code.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: nameColor.withOpacity(0.20),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickSaleCard({
    required int index,
    required double cardSize,
    required _SalesResponsiveMetrics metrics,
  }) {
    final isHovered = _hoveredProductIndexes.contains(index);
    const accentColor = _allegraAccentColor;
    final isActive = isHovered || _isQuickSalePressed;
    final isCompact = metrics.isCompactDesktop;

    final borderColor = isActive
        ? accentColor.withOpacity(0.90)
        : accentColor.withOpacity(0.34);

    const cardRadius = BorderRadius.only(
      topLeft: Radius.circular(30),
      topRight: Radius.circular(7),
      bottomLeft: Radius.circular(7),
      bottomRight: Radius.circular(30),
    );

    const iconRadius = BorderRadius.only(
      topLeft: Radius.circular(26),
      topRight: Radius.circular(12),
      bottomLeft: Radius.circular(12),
      bottomRight: Radius.circular(26),
    );

    // Responsive sizes
    final iconBoxSize = isCompact ? 88.0 : 98.0;
    final iconBoxSizeHover = isCompact ? 94.0 : 106.0;
    final iconSize = isCompact ? 46.0 : 50.0;
    final iconSizeHover = isCompact ? 50.0 : 54.0;
    final titleFontSize = isCompact ? 16.0 : 16.8;
    final hoverFontSize = isCompact ? 14.5 : 15.5;
    final verticalSpacing = isCompact ? 10.0 : 14.0;
    final bottomSpacing = isCompact ? 6.0 : 10.0;
    final paddingH = isCompact ? 14.0 : 18.0;
    final paddingV = isCompact ? 14.0 : 18.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) =>
          _setHoverStateDeferred(_hoveredProductIndexes, index, true),
      onExit: (_) =>
          _setHoverStateDeferred(_hoveredProductIndexes, index, false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..translate(0.0, isHovered ? -3.0 : 0.0)
          ..scale(_isQuickSalePressed ? 0.975 : 1.0),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isHovered
                ? const [Color(0xFFF5F9FF), Color(0xFFEAF2FF)]
                : const [Color(0xFFFFFFFF), Color(0xFFF5F8FC)],
          ),
          borderRadius: cardRadius,
          border: Border.all(color: borderColor, width: isActive ? 1.6 : 1.2),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(isHovered ? 0.16 : 0.07),
              blurRadius: isHovered ? 18 : 10,
              spreadRadius: isHovered ? 0.5 : 0,
              offset: Offset(0, isHovered ? 8 : 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: cardRadius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: cardRadius,
              onTapDown: (_) {
                setState(() => _isQuickSalePressed = true);
              },
              onTapCancel: () {
                setState(() => _isQuickSalePressed = false);
              },
              onTapUp: (_) {
                setState(() => _isQuickSalePressed = false);
              },
              onTap: _showQuickItemDialog,
              hoverColor: Colors.transparent,
              highlightColor: accentColor.withOpacity(0.025),
              splashColor: accentColor.withOpacity(0.10),
              child: SizedBox(
                height: cardSize,
                child: Stack(
                  children: [
                    // Franja distintiva lateral.
                    Positioned(
                      left: 0,
                      top: 32,
                      bottom: 32,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 190),
                        curve: Curves.easeOutCubic,
                        width: isHovered ? 5 : 4,
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(8),
                          ),
                        ),
                      ),
                    ),

                    // Decoración suave de la esquina inferior derecha.
                    Positioned(
                      right: -38,
                      bottom: -38,
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 190),
                          width: isHovered ? 122 : 108,
                          height: isHovered ? 122 : 108,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentColor.withOpacity(
                              isHovered ? 0.075 : 0.045,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Contenido centrado (sin badge "ACCESO RÁPIDO")
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        paddingH,
                        paddingV,
                        paddingH,
                        paddingV,
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 190),
                                curve: Curves.easeOutBack,
                                scale: _isQuickSalePressed
                                    ? 0.94
                                    : isHovered
                                    ? 1.06
                                    : 1.0,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 190),
                                  curve: Curves.easeOutCubic,
                                  width: isHovered
                                      ? iconBoxSizeHover
                                      : iconBoxSize,
                                  height: isHovered
                                      ? iconBoxSizeHover
                                      : iconBoxSize,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: isHovered
                                          ? const [
                                              Color(0xFFE2ECFF),
                                              Color(0xFFD7E6FF),
                                            ]
                                          : const [
                                              Color(0xFFF0F4FA),
                                              Color(0xFFE7EDF5),
                                            ],
                                    ),
                                    borderRadius: iconRadius,
                                    border: Border.all(
                                      color: isHovered
                                          ? accentColor.withOpacity(0.30)
                                          : accentColor.withOpacity(0.13),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: accentColor.withOpacity(
                                          isHovered ? 0.15 : 0.07,
                                        ),
                                        blurRadius: isHovered ? 18 : 10,
                                        spreadRadius: -5,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: AnimatedRotation(
                                    duration: const Duration(milliseconds: 190),
                                    turns: isHovered ? -0.018 : 0,
                                    child: Icon(
                                      Icons.shopping_cart_checkout_rounded,
                                      size: isHovered
                                          ? iconSizeHover
                                          : iconSize,
                                      color: isHovered
                                          ? accentColor
                                          : const Color(0xFF71839A),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          SizedBox(height: verticalSpacing),

                          SizedBox(
                            height: 42,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.12),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                              child: isHovered
                                  ? Text(
                                      'Vender fuera de\ninventario',
                                      key: const ValueKey(
                                        'quick-sale-hover-text',
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Color(0xFF111827),
                                        fontSize: hoverFontSize,
                                        fontWeight: FontWeight.w700,
                                        height: 1.18,
                                      ),
                                    )
                                  : Text(
                                      'Venta común',
                                      key: const ValueKey(
                                        'quick-sale-default-text',
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Color(0xFF111827),
                                        fontSize: titleFontSize,
                                        fontWeight: FontWeight.w800,
                                        height: 1.08,
                                      ),
                                    ),
                            ),
                          ),

                          SizedBox(height: bottomSpacing),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildCategoryDropdown() {
    final salesTheme = Theme.of(context).extension<SalesPageTheme>();

    Color resolve(Color? c, Color fallback) {
      if (c == null || c.opacity == 0) return fallback;
      return c;
    }

    final allOption = 'Todas';
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
    Widget buildCategoryIcon({
      required String label,
      required bool isSelected,
      required VoidCallback onTap,
      String? imagePath,
      IconData? fallbackIcon,
    }) {
      final normalizedPath = (imagePath ?? '').trim();
      final hasImage =
          normalizedPath.isNotEmpty && File(normalizedPath).existsSync();
      final fg = isSelected ? scheme.primary : dropdownText;
      return Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: isSelected ? scheme.primary.withOpacity(0.10) : dropdownBg,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected
                    ? scheme.primary.withOpacity(0.35)
                    : dropdownBorder.withOpacity(0.7),
                width: 0.9,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isSelected ? 0.5 : 0.42),
                  blurRadius: isSelected ? 24 : 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(isSelected ? 0.22 : 0.18),
                  blurRadius: isSelected ? 40 : 32,
                  spreadRadius: 0,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: hasImage
                ? Image.file(File(normalizedPath), fit: BoxFit.cover)
                : Icon(
                    fallbackIcon ?? Icons.category_outlined,
                    size: 16,
                    color: fg,
                  ),
          ),
        ),
      );
    }

    final selectedCategoryIds = _selectedCategoryIds;

    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _categories.length + 1,
          separatorBuilder: (context, index) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            if (index == 0) {
              final isSelected = selectedCategoryIds.isEmpty;
              return buildCategoryIcon(
                label: allOption,
                isSelected: isSelected,
                onTap: () => _onCategorySelected(null),
                fallbackIcon: Icons.filter_alt_off_outlined,
              );
            }

            final category = _categories[index - 1];
            final isSelected =
                category.id != null &&
                selectedCategoryIds.contains(category.id);
            return buildCategoryIcon(
              label: category.name,
              isSelected: isSelected,
              onTap: () => _onCategorySelected(category.id),
              imagePath: category.imagePath,
              fallbackIcon: Icons.category_outlined,
            );
          },
        ),
      ),
    );
  }

  Widget _buildClearCategoryFilterButton({required bool isExpanded}) {
    final selectedCount = _selectedCategoryIds.length;
    return Container(
      width: double.infinity,
      height: 40,
      decoration: const BoxDecoration(color: Color(0xFF1A56DB)),
      child: Tooltip(
        message: 'Limpiar filtro',
        waitDuration: const Duration(milliseconds: 200),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _clearCategoryFilter,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: isExpanded
                ? Center(
                    child: Text(
                      selectedCount == 1
                          ? 'Limpiar (1 filtro)'
                          : 'Limpiar ($selectedCount filtros)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : Center(
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Transform.translate(
                        offset: Offset(2, 0),
                        child: Transform.rotate(
                          angle: 0.08,
                          child: Icon(
                            Icons.delete_forever_rounded,
                            color: Colors.white,
                            size: 32,
                            shadows: [
                              Shadow(
                                color: Color(0x40000000),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySidebar() {
    final hasCategories = _categories.isNotEmpty;
    if (!hasCategories) {
      return const SizedBox.shrink();
    }

    final isExpanded = _isCategorySidebarExpanded;
    final screenSize = MediaQuery.sizeOf(context);
    final useCompactChrome = _useCompactChromeFor(screenSize);
    final collapsedWidth = _categorySidebarCollapsedWidthFor(context);
    final expandedWidth = _categorySidebarExpandedWidthFor(context);
    final avatarLaneWidth = useCompactChrome ? 52.0 : 60.0;
    final categoryItemHeight = _categoryItemHeightFor(context);
    final topPadding = _selectedCategoryIds.isNotEmpty
        ? (useCompactChrome ? 8.0 : 12.0)
        : (useCompactChrome ? 10.0 : 14.0);

    return MouseRegion(
      onEnter: (_) => _expandCategorySidebar(),
      onExit: (_) => _scheduleCategorySidebarCollapse(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: isExpanded ? expandedWidth : collapsedWidth,
        decoration: const BoxDecoration(
          color: Color(0xFFF7FAFC),
          border: Border(
            top: BorderSide(color: Color(0xFFE8EEF6), width: 1),
            right: BorderSide(color: Color(0xFFDCE5F0), width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x080F172A),
              blurRadius: 12,
              offset: Offset(2, 0),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: useCompactChrome ? 3 : 5),
          child: Column(
            children: [
              if (_selectedCategoryIds.isNotEmpty)
                _buildClearCategoryFilterButton(isExpanded: isExpanded),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    useCompactChrome ? 4 : 6,
                    topPadding,
                    useCompactChrome ? 5 : 7,
                    useCompactChrome ? 2 : 4,
                  ),
                  itemCount: _categories.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 0),
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    final isSelected =
                        category.id != null &&
                        _selectedCategoryIds.contains(category.id);
                    final avatarColor = _categorySidebarColor(index);
                    final normalizedPath = (category.imagePath ?? '').trim();
                    final hasImage =
                        normalizedPath.isNotEmpty &&
                        File(normalizedPath).existsSync();
                    final trimmedName = category.name.trim();
                    final initial = trimmedName.isEmpty
                        ? '?'
                        : trimmedName.substring(0, 1).toUpperCase();

                    return _CategorySidebarItem(
                      isSelected: isSelected,
                      categoryItemHeight: categoryItemHeight,
                      isExpanded: isExpanded,
                      useCompactChrome: useCompactChrome,
                      avatarLaneWidth: avatarLaneWidth,
                      onTap: () => _onCategorySelected(category.id),
                      avatar: _buildCategoryAvatar(
                        hasImage: hasImage,
                        imagePath: normalizedPath,
                        initial: initial,
                        isSelected: isSelected,
                        fillColor: avatarColor,
                      ),
                      name: category.name,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryAvatar({
    required bool hasImage,
    required String imagePath,
    required String initial,
    required bool isSelected,
    required Color fillColor,
  }) {
    final screenSize = MediaQuery.sizeOf(context);
    final useCompactChrome = _useCompactChromeFor(screenSize);

    // Tamaños para la mini tarjeta (usando métodos responsive)
    final cardWidth = _categoryCardWidthFor(context);
    final cardHeight = _categoryCardHeightFor(context);
    final circleSize = _categoryCircleSizeFor(context);
    final iconSize = useCompactChrome ? 18.0 : 20.0;
    final borderRadius = 14.0;

    // Colores del diseño
    const Color primaryBlue = Color(0xFF1A56DB);
    const Color softBlueBg = Color(0xFFEFF6FF);
    const Color softBlueBorder = Color(0xFFBFDBFE);
    const Color cardBorder = Color(0xFFD9E3F0);

    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isSelected ? primaryBlue : cardBorder,
          width: isSelected ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Barra lateral azul cuando está seleccionado
          if (isSelected)
            Positioned(
              left: 0,
              top: 4,
              bottom: 4,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  color: primaryBlue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          Center(
            child: Container(
              width: circleSize,
              height: circleSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFDBEAFE) : softBlueBg,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? primaryBlue : softBlueBorder,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasImage
                  ? ClipOval(
                      child: Image.file(
                        File(imagePath),
                        width: circleSize,
                        height: circleSize,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildCategoryFallbackIcon(primaryBlue, iconSize),
                      ),
                    )
                  : _buildCategoryFallbackIcon(primaryBlue, iconSize),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFallbackIcon(Color color, double size) {
    return Icon(Icons.category_outlined, color: color, size: size);
  }

  Widget _build3DControlBar({_SalesResponsiveMetrics? metrics}) {
    final m =
        metrics ??
        _SalesResponsiveMetrics(
          isCompactDesktop: false,
          isTightDesktop: false,
          isShortDesktop: false,
          isVeryShortDesktop: false,
          ticketPanelWidth: 550,
          productCardWidth: 220,
          productCardHeight: 254,
          productHorizontalMargin: 12,
          productVerticalMargin: 10,
          catalogLeftPadding: 14,
          controlBarTopPadding: 20,
          controlBarRightPadding: 18,
          controlBarHeight: 42,
          productImageSize: 112,
          productImageBoxSize: 118,
          productNameFontSize: 13.4,
          productPriceFontSize: 16.5,
          ticketHorizontalPadding: 18,
          ticketHeaderVerticalPadding: 13,
          totalAreaHeight: 86,
          categorySidebarWidth: 64,
          categoryItemHeight: 48,
          categoryAvatarOuterSize: 44,
          categoryAvatarInnerSize: 36,
          footerTicketHeight: 58,
          footerTicketTabHeight: 46,
          spaceBelowControlBar: 14,
        );
    void showSearchNotice({required IconData icon, required String message}) {
      final overlayState = Overlay.of(context, rootOverlay: true);

      late OverlayEntry entry;
      var removed = false;

      void removeEntry() {
        if (removed) return;
        removed = true;
        _transientOverlayEntries.remove(entry);

        if (entry.mounted) {
          entry.remove();
        }
      }

      entry = OverlayEntry(
        builder: (overlayContext) {
          return Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Material(
              color: Colors.transparent,
              child: Center(
                child: GestureDetector(
                  onTap: removeEntry,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 300,
                      maxWidth: 410,
                    ),
                    padding: const EdgeInsets.fromLTRB(10, 8, 15, 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(6),
                        bottomLeft: Radius.circular(6),
                        bottomRight: Radius.circular(14),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 18,
                          spreadRadius: -5,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: const BoxDecoration(
                            color: Color(0xFF1A56DB),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(9),
                              topRight: Radius.circular(4),
                              bottomLeft: Radius.circular(4),
                              bottomRight: Radius.circular(9),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Icon(icon, size: 18, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
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
        },
      );

      overlayState.insert(entry);
      _transientOverlayEntries.add(entry);

      Future<void>.delayed(const Duration(milliseconds: 1700), removeEntry);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 760;

        const fullposBlue = Color(0xFF1A56DB);
        const darkScanner = Color(0xFF111827);
        const borderColor = Color(0xFFAEBBC9);
        const textColor = Color(0xFF172033);
        const hintColor = Color(0xFF64748B);

        final barHeight = m.controlBarHeight;
        const iconButtonWidth = 50.0;

        const completeRadius = BorderRadius.only(
          topLeft: Radius.circular(13),
          topRight: Radius.circular(5),
          bottomLeft: Radius.circular(5),
          bottomRight: Radius.circular(13),
        );

        const leftRadius = BorderRadius.only(
          topLeft: Radius.circular(12),
          bottomLeft: Radius.circular(12),
        );

        const rightRadius = BorderRadius.only(
          topRight: Radius.circular(5),
          bottomRight: Radius.circular(13),
        );

        const productRadius = BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(5),
          bottomLeft: Radius.circular(5),
          bottomRight: Radius.circular(12),
        );

        Widget buildActionButton({
          required Widget icon,
          required String tooltip,
          required VoidCallback onTap,
          required Color backgroundColor,
          required BorderRadius radius,
        }) {
          return Tooltip(
            message: tooltip,
            waitDuration: const Duration(milliseconds: 350),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                hoverColor: Colors.white.withOpacity(0.08),
                splashColor: Colors.white.withOpacity(0.14),
                child: Ink(
                  width: iconButtonWidth,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: radius,
                  ),
                  child: Center(child: icon),
                ),
              ),
            ),
          );
        }

        final searchBorder = OutlineInputBorder(
          borderRadius: rightRadius,
          borderSide: const BorderSide(color: borderColor, width: 0.65),
        );
        final controlRightPadding = math.max(
          m.controlBarRightPadding,
          m.isCompactDesktop ? 16.0 : 30.0,
        );
        final productButtonMinWidth = isCompact ? 46.0 : 162.0;

        return Padding(
          padding: EdgeInsets.only(left: 8, right: controlRightPadding),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: completeRadius,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.025),
                        blurRadius: 7,
                        spreadRadius: -3,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      buildActionButton(
                        tooltip: 'Buscar producto',
                        backgroundColor: fullposBlue,
                        radius: leftRadius,
                        onTap: () {
                          _searchFocusNode.requestFocus();

                          showSearchNotice(
                            icon: Icons.search_rounded,
                            message: 'Escribe el nombre o código del producto.',
                          );
                        },
                        icon: Image.asset(
                          'assets/imagen/iconos/lupa.png',
                          width: 20,
                          height: 20,
                          color: Colors.white,
                          errorBuilder: (_, _, _) {
                            return const Icon(
                              Icons.search_rounded,
                              color: Colors.white,
                              size: 21,
                            );
                          },
                        ),
                      ),

                      buildActionButton(
                        tooltip: 'Escanear código de barras',
                        backgroundColor: darkScanner,
                        radius: BorderRadius.zero,
                        onTap: () {
                          _searchFocusNode.requestFocus();

                          showSearchNotice(
                            icon: Icons.qr_code_scanner_rounded,
                            message:
                                'Escanea el código de barras del producto.',
                          );
                        },
                        icon: Image.asset(
                          'assets/imagen/iconos/lectura-de-codigo-de-barras.png',
                          width: 21,
                          height: 21,
                          color: Colors.white,
                          errorBuilder: (_, _, _) {
                            return const Icon(
                              Icons.qr_code_scanner_rounded,
                              color: Colors.white,
                              size: 21,
                            );
                          },
                        ),
                      ),

                      Expanded(
                        child: SizedBox(
                          height: barHeight,
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            expands: true,
                            minLines: null,
                            maxLines: null,
                            textAlignVertical: TextAlignVertical.center,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText:
                                  'Buscar producto por nombre o código...',
                              hintStyle: const TextStyle(
                                color: hintColor,
                                fontSize: 14.4,
                                fontWeight: FontWeight.w400,
                              ),
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 0,
                              ),
                              border: searchBorder,
                              enabledBorder: searchBorder,
                              focusedBorder: searchBorder.copyWith(
                                borderSide: const BorderSide(
                                  color: fullposBlue,
                                  width: 0.95,
                                ),
                              ),
                              suffixIcon: _searchController.text.trim().isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Limpiar búsqueda',
                                      splashRadius: 18,
                                      onPressed: () {
                                        _searchController.clear();
                                        _searchProducts('');
                                        _searchFocusNode.requestFocus();

                                        if (mounted) {
                                          setState(() {});
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                        color: hintColor,
                                      ),
                                    ),
                            ),
                            style: const TextStyle(
                              color: textColor,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w500,
                            ),
                            onChanged: (value) {
                              _searchProducts(value);

                              if (mounted) {
                                setState(() {});
                              }
                            },
                            onSubmitted: (value) async {
                              final query = value.trim();

                              if (query.isEmpty || query.contains(' ')) {
                                return;
                              }

                              await _handleBarcodeScan(
                                query,
                                clearSearchField: true,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(width: m.isCompactDesktop ? 12 : 16),

              Tooltip(
                message: 'Crear un producto nuevo',
                waitDuration: const Duration(milliseconds: 350),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _showNewProductDialog,
                    borderRadius: productRadius,
                    hoverColor: fullposBlue.withOpacity(0.06),
                    splashColor: fullposBlue.withOpacity(0.10),
                    child: Container(
                      height: barHeight,
                      constraints: BoxConstraints(
                        minWidth: productButtonMinWidth,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 11 : 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: productRadius,
                        border: Border.all(color: fullposBlue, width: 0.95),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (!isCompact) ...[
                            const Text(
                              'Nuevo producto',
                              style: TextStyle(
                                color: fullposBlue,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                height: 1,
                              ),
                            ),
                            const SizedBox(width: 9),
                          ],
                          const Icon(
                            Icons.add_rounded,
                            size: 21,
                            color: fullposBlue,
                          ),
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

  Widget _buildMovementPanel() {
    final dividerColor = salesDetailBorderColor;

    Widget movementCard({
      required String title,
      required String subtitle,
      required IconData icon,
      required VoidCallback onTap,
      required Color accent,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: salesDetailSurfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: salesDetailBorderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: salesDetailTextColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: salesDetailMutedTextColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: salesDetailMutedTextColor,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      key: const ValueKey<String>('movement-panel'),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: salesDetailSurfaceStrongColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: salesDetailBorderColor),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.swap_horiz_rounded,
                  color: salesDetailTextColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Movimiento de efectivo',
                    style: TextStyle(
                      color: salesDetailTextColor,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _showMovementPanel = false),
                  tooltip: 'Cerrar',
                  icon: Icon(Icons.close_rounded, color: salesDetailTextColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: dividerColor),
          const SizedBox(height: 14),
          Text(
            'Opciones de efectivo',
            style: TextStyle(
              color: salesDetailTextColor,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Registra ingresos, salidas o consulta el historial de movimientos.',
            style: TextStyle(
              color: salesDetailMutedTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          movementCard(
            title: 'Registrar Ingreso',
            subtitle: 'Entrada de efectivo a caja',
            icon: Icons.add_circle_outline_rounded,
            accent: status.success,
            onTap: () {
              setState(() => _showMovementPanel = false);
              _openCashMovementDialogInCenter(CashMovementType.income);
            },
          ),
          const SizedBox(height: 12),
          movementCard(
            title: 'Registrar Salida',
            subtitle: 'Salida o gasto operativo',
            icon: Icons.remove_circle_outline_rounded,
            accent: status.warning,
            onTap: () {
              setState(() => _showMovementPanel = false);
              _openCashMovementDialogInCenter(CashMovementType.outcome);
            },
          ),
          const SizedBox(height: 12),
          movementCard(
            title: 'Movimiento de Efectivo',
            subtitle: 'Ver historial de movimientos',
            icon: Icons.history_rounded,
            accent: const Color(0xFF2563EB),
            onTap: () {
              setState(() => _showMovementPanel = false);
              context.push('/cash/history');
            },
          ),
          const Spacer(),
        ],
      ),
    );
  }

  /// Panel de ticket refactorizado con 3 cards profesionales
  Widget _buildTicketPanel({_SalesResponsiveMetrics? metrics}) {
    final m =
        metrics ??
        _SalesResponsiveMetrics(
          isCompactDesktop: false,
          isTightDesktop: false,
          isShortDesktop: false,
          isVeryShortDesktop: false,
          ticketPanelWidth: 550,
          productCardWidth: 220,
          productCardHeight: 254,
          productHorizontalMargin: 12,
          productVerticalMargin: 10,
          catalogLeftPadding: 14,
          controlBarTopPadding: 20,
          controlBarRightPadding: 18,
          controlBarHeight: 42,
          productImageSize: 112,
          productImageBoxSize: 118,
          productNameFontSize: 13.4,
          productPriceFontSize: 16.5,
          ticketHorizontalPadding: 18,
          ticketHeaderVerticalPadding: 13,
          totalAreaHeight: 86,
          categorySidebarWidth: 64,
          categoryItemHeight: 48,
          categoryAvatarOuterSize: 44,
          categoryAvatarInnerSize: 36,
          footerTicketHeight: 58,
          footerTicketTabHeight: 46,
          spaceBelowControlBar: 14,
        );
    final dividerColor = salesDetailBorderColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildInvoicePanelHeader(metrics: m),
        const SizedBox(height: 5),
        Divider(height: 1, color: dividerColor),
        Expanded(child: _buildItemsListCard(metrics: m)),
        Divider(height: 1, color: dividerColor),
        Padding(
          padding: EdgeInsets.fromLTRB(0, 0, m.ticketHorizontalPadding, 2),
          child: _buildTotalAndActionsCard(embedded: true, metrics: m),
        ),
      ],
    );
  }

  Widget _buildRecentSalesPanel() {
    const dividerColor = Color(0xFFE2E8F0);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth <= 1366;
    final hp = isCompact ? 12.0 : 18.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRecentSalesPanelHeader(isCompact: isCompact, hp: hp),
        const SizedBox(height: 10),
        const Divider(height: 1, color: dividerColor),
        _buildRecentSalesTableHeader(),
        Expanded(child: _buildRecentSalesTable()),
        const Divider(height: 1, color: dividerColor),
        Padding(
          padding: EdgeInsets.fromLTRB(
            hp,
            isCompact ? 10 : 14,
            hp,
            isCompact ? 12 : 18,
          ),
          child: SizedBox(
            height: isCompact ? 40 : 46,
            child: OutlinedButton(
              onPressed: _openFacturaPage,
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F172A),
                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Ir al historial de ventas',
                    style: TextStyle(
                      fontSize: 14.2,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                  SizedBox(width: 10),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSalesPanelHeader({
    bool isCompact = false,
    double hp = 18,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hp, isCompact ? 12 : 18, hp, 0),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFDBE5FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 18,
              color: Color(0xFF1A56DB),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Ventas recientes',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 17.5,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _closeRecentSalesPanel,
              borderRadius: BorderRadius.circular(10),
              child: const SizedBox(
                width: 34,
                height: 34,
                child: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSalesTableHeader() {
    const textStyle = TextStyle(
      color: Color(0xFF0F172A),
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.1,
    );

    Widget cell(
      String label, {
      required int flex,
      Alignment alignment = Alignment.centerLeft,
      bool showRightDivider = true,
    }) {
      return Expanded(
        flex: flex,
        child: Container(
          alignment: alignment,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            border: showRightDivider
                ? const Border(
                    right: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  )
                : null,
          ),
          child: Text(label, style: textStyle),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          cell('Venta', flex: 34),
          cell('Total', flex: 30),
          cell('Estado', flex: 24),
          cell(
            '',
            flex: 20,
            alignment: Alignment.center,
            showRightDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentSalesTable() {
    if (_isLoadingRecentSales) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }

    if (_recentSales.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(
                Icons.receipt_long_outlined,
                size: 40,
                color: Color(0xFFB8C4D1),
              ),
              SizedBox(height: 10),
              Text(
                'No hay ventas recientes',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      itemCount: _recentSales.length,
      separatorBuilder: (_, index) =>
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
      itemBuilder: (context, index) {
        return _buildRecentSaleRow(_recentSales[index], index);
      },
    );
  }

  Widget _buildRecentSaleRow(legacy_sales.SaleModel sale, int index) {
    final saleId = sale.id ?? -1;
    final isHovered = _hoveredRecentSaleIds.contains(saleId);
    final isHighlighted = index == 0;
    final backgroundColor = isHovered
        ? const Color(0xFFEAF7FB)
        : (isHighlighted ? const Color(0xFFF1FBFC) : Colors.white);

    return MouseRegion(
      onEnter: (_) =>
          _setHoverStateDeferred(_hoveredRecentSaleIds, saleId, true),
      onExit: (_) =>
          _setHoverStateDeferred(_hoveredRecentSaleIds, saleId, false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        color: backgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 34,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _recentSaleTitle(sale),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 13.8,
                    fontWeight: FontWeight.w500,
                    height: 1.15,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 30,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    CurrencyDisplay.format(sale.total),
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 13.2,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 24,
              child: Text(
                _recentSaleStatusLabel(sale),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w400,
                  height: 1.15,
                ),
              ),
            ),
            Expanded(
              flex: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: 'Imprimir factura',
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: sale.id == null
                            ? null
                            : () => unawaited(_printRecentSale(sale)),
                        borderRadius: BorderRadius.circular(10),
                        child: const SizedBox(
                          width: 26,
                          height: 30,
                          child: Icon(
                            Icons.print_outlined,
                            size: 17,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (sale.id != null &&
                      sale.status.toUpperCase() != 'REFUNDED') ...[
                    const SizedBox(width: 0),
                    Tooltip(
                      message: 'Reembolsar factura',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () =>
                              unawaited(_showRecentSaleRefundDialog(sale)),
                          borderRadius: BorderRadius.circular(10),
                          child: const SizedBox(
                            width: 26,
                            height: 30,
                            child: Icon(
                              Icons.assignment_return_outlined,
                              size: 17,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoicePanelHeader({_SalesResponsiveMetrics? metrics}) {
    final m =
        metrics ??
        _SalesResponsiveMetrics(
          isCompactDesktop: false,
          isTightDesktop: false,
          isShortDesktop: false,
          isVeryShortDesktop: false,
          ticketPanelWidth: 550,
          productCardWidth: 220,
          productCardHeight: 254,
          productHorizontalMargin: 12,
          productVerticalMargin: 10,
          catalogLeftPadding: 14,
          controlBarTopPadding: 20,
          controlBarRightPadding: 18,
          controlBarHeight: 42,
          productImageSize: 112,
          productImageBoxSize: 118,
          productNameFontSize: 13.4,
          productPriceFontSize: 16.5,
          ticketHorizontalPadding: 18,
          ticketHeaderVerticalPadding: 13,
          totalAreaHeight: 86,
          categorySidebarWidth: 64,
          categoryItemHeight: 48,
          categoryAvatarOuterSize: 44,
          categoryAvatarInnerSize: 36,
          footerTicketHeight: 58,
          footerTicketTabHeight: 46,
          spaceBelowControlBar: 14,
        );

    const fullposBlue = Color(0xFF1A56DB);
    const panelBackground = Color(0xFFF8FAFC);
    const activeGreen = Color(0xFF16A34A);

    const statusRadius = BorderRadius.only(
      topLeft: Radius.circular(9),
      topRight: Radius.circular(4),
      bottomLeft: Radius.circular(4),
      bottomRight: Radius.circular(9),
    );

    final isCompact = m.isCompactDesktop;
    final hp = m.ticketHorizontalPadding;
    final vp = m.ticketHeaderVerticalPadding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: EdgeInsets.fromLTRB(hp - 2, vp, hp - 2, isCompact ? 9 : 11),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.8),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 3,
                height: isCompact ? 34 : 38,
                decoration: const BoxDecoration(
                  color: fullposBlue,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
              ),
              SizedBox(width: isCompact ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Factura de venta',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: salesDetailTextColor,
                              fontSize: isCompact ? 15.2 : 16.6,
                              fontWeight: FontWeight.w700,
                              height: 1.05,
                              letterSpacing: -0.28,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Tooltip(
                          message: 'Venta activa',
                          waitDuration: const Duration(milliseconds: 350),
                          child: Container(
                            width: isCompact ? 23 : 25,
                            height: isCompact ? 23 : 25,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: statusRadius,
                              border: Border.all(
                                color: activeGreen.withOpacity(0.20),
                                width: 0.8,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  Icons.point_of_sale_rounded,
                                  size: isCompact ? 13 : 14,
                                  color: fullposBlue.withOpacity(0.82),
                                ),
                                Positioned(
                                  right: 3,
                                  top: 3,
                                  child: Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: activeGreen,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 0.8,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cliente, comprobante y productos de la venta',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: salesDetailMutedTextColor,
                        fontSize: isCompact ? 9.8 : 10.6,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildQuickDiscountButton(),
              const SizedBox(width: 6),
              _buildQuoteHeaderIconAction(
                id: 'save-quote-header',
                icon: Icons.description_outlined,
                tooltip: 'Convertir venta en cotización PDF',
                onTap: _currentCart.items.isEmpty || _isQuotePdfFlowRunning
                    ? null
                    : () => unawaited(_saveQuoteFromHeaderAndShowDialog()),
              ),
            ],
          ),
        ),

        Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(
            hp - 2,
            isCompact ? 8 : 10,
            hp - 2,
            isCompact ? 8 : 10,
          ),
          child: Container(
            padding: EdgeInsets.fromLTRB(
              isCompact ? 8 : 10,
              isCompact ? 7 : 8,
              isCompact ? 8 : 10,
              isCompact ? 7 : 8,
            ),
            decoration: BoxDecoration(
              color: panelBackground,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 0.75),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPanelDocumentTypeDropdown(),

                const SizedBox(height: 7),

                SizedBox(
                  height: _customerRowControlHeight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildPanelClientControl()),

                      const SizedBox(width: 7),

                      SizedBox(
                        width: _customerNewButtonWidth,
                        height: _customerRowControlHeight,
                        child: _buildPanelNewClientButton(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickDiscountButton() {
    const fullposBlue = Color(0xFF1A56DB);
    const softBlueBg = Color(0xFFF8FAFC);
    const borderColor = Color(0xFFD9E3F0);
    const size = 36.0;

    return Tooltip(
      message: 'Descuento rápido',
      waitDuration: const Duration(milliseconds: 350),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showQuickDiscountMenu(),
          borderRadius: BorderRadius.circular(11),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: softBlueBg,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: borderColor, width: 0.9),
            ),
            child: const Icon(
              Icons.flash_on_rounded,
              size: 17,
              color: fullposBlue,
            ),
          ),
        ),
      ),
    );
  }

  void _showQuickDiscountMenu() {
    if (_currentCart.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Agrega productos antes de aplicar descuento.'),
          backgroundColor: status.warning,
        ),
      );
      return;
    }
    final screenSize = MediaQuery.sizeOf(context);
    final panelWidth = _ticketPanelConstraints(screenSize.width).maxWidth;
    final discountController = TextEditingController(
      text: (_currentCart.discountTotalValue ?? 0) > 0
          ? (_currentCart.discountTotalValue!).toStringAsFixed(2)
          : '',
    );
    final subtotal = _currentCart.calculateSubtotal();
    final currentIsPercent = _currentCart.discountTotalType == 'percent';

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        var isPercent = currentIsPercent;
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Widget quickChip(String label, double percent) {
              return InkWell(
                onTap: () {
                  isPercent = true;
                  discountController.text = percent.toStringAsFixed(0);
                  setLocalState(() {});
                },
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFBFD1F7)),
                  ),
                  child: Text(
                    '$label%',
                    style: const TextStyle(
                      color: Color(0xFF1A56DB),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }

            Future<void> applyDiscount() async {
              final value =
                  double.tryParse(discountController.text.trim()) ?? 0;
              if (value <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Indica un descuento válido.'),
                    backgroundColor: status.error,
                  ),
                );
                return;
              }
              if (isPercent) {
                if (value > 100) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'El porcentaje no puede ser mayor a 100%.',
                      ),
                      backgroundColor: status.error,
                    ),
                  );
                  return;
                }
                _updateCurrentCart(() {
                  _currentCart.discountTotalType = 'percent';
                  _currentCart.discountTotalValue = value;
                });
              } else {
                if (value >= subtotal) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        'El monto debe ser menor al total de la venta.',
                      ),
                      backgroundColor: status.error,
                    ),
                  );
                  return;
                }
                _updateCurrentCart(() {
                  _currentCart.discountTotalType = 'amount';
                  _currentCart.discountTotalValue = value;
                });
              }
              if (mounted) Navigator.of(dialogContext).pop();
            }

            return Material(
              color: Colors.transparent,
              child: Stack(
                children: [
                  Positioned(
                    right: 12,
                    top: 92,
                    width: math.min(320.0, panelWidth - 18),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFDCE5F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 30,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.flash_on_rounded,
                                color: Color(0xFF1A56DB),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Descuento',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF17324D),
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildDiscountPanelTypeChip(
                                  label: 'Porcentaje',
                                  selected: isPercent,
                                  onTap: () => setLocalState(() {
                                    isPercent = true;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildDiscountPanelTypeChip(
                                  label: 'Monto fijo',
                                  selected: !isPercent,
                                  onTap: () => setLocalState(() {
                                    isPercent = false;
                                  }),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              quickChip('5', 5),
                              quickChip('10', 10),
                              quickChip('15', 15),
                              quickChip('20', 20),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: discountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'^\d*\.?\d{0,2}'),
                              ),
                            ],
                            decoration: InputDecoration(
                              labelText: isPercent
                                  ? 'Porcentaje de descuento'
                                  : 'Monto de descuento',
                              prefixText: isPercent ? '' : 'RD\$ ',
                              suffixText: isPercent ? '%' : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Total actual: ${CurrencyDisplay.format(_currentCart.calculateTotal(), decimalDigits: 2)}',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              if ((_currentCart.discountTotalValue ?? 0) > 0)
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      _removeQuickDiscount();
                                      Navigator.of(dialogContext).pop();
                                    },
                                    child: const Text('Quitar descuento'),
                                  ),
                                ),
                              if ((_currentCart.discountTotalValue ?? 0) > 0)
                                const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton(
                                  onPressed: applyDiscount,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF1A56DB),
                                  ),
                                  child: const Text('Aplicar descuento'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.12, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    ).whenComplete(discountController.dispose);
  }

  Widget _buildDiscountPanelTypeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF1A56DB) : const Color(0xFFD7E0EA),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? const Color(0xFF1A56DB) : const Color(0xFF5E7186),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  void _removeQuickDiscount() {
    _updateCurrentCart(() {
      _currentCart.discountTotalType = null;
      _currentCart.discountTotalValue = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Descuento eliminado.'),
        backgroundColor: status.success,
      ),
    );
  }

  Widget _buildQuoteHeaderIconAction({
    required String id,
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final isHovered = _hoveredTicketHeaderActions.contains(id);
    final isDisabled = onTap == null;

    const brandColor = Color(0xFF1A56DB);
    const softBrandBg = Color(0xFFEFF6FF);
    const borderColor = Color(0xFFD9E3F0);

    return MouseRegion(
      cursor: isDisabled ? SystemMouseCursors.basic : SystemMouseCursors.click,
      onEnter: (_) {
        if (!isDisabled) {
          _setHoverStateDeferred(_hoveredTicketHeaderActions, id, true);
        }
      },
      onExit: (_) {
        if (!isDisabled) {
          _setHoverStateDeferred(_hoveredTicketHeaderActions, id, false);
        }
      },
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 350),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: isDisabled ? 0.45 : 1,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(11),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isHovered
                      ? softBrandBg.withOpacity(0.75)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: isHovered
                        ? brandColor.withOpacity(0.30)
                        : borderColor,
                    width: 0.9,
                  ),
                  boxShadow: [
                    if (isHovered && !isDisabled)
                      BoxShadow(
                        color: brandColor.withOpacity(0.08),
                        blurRadius: 9,
                        offset: const Offset(0, 4),
                      ),
                  ],
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: isDisabled ? const Color(0xFF94A3B8) : brandColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveQuoteFromHeaderAndShowDialog() async {
    return _handleSaveSaleAsQuotationPdf();
    // ignore: dead_code
    if (_currentCart.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Agrega productos antes de guardar una cotización.',
          ),
          backgroundColor: status.warning,
        ),
      );
      return;
    }

    final confirmed = await _confirmQuoteClientBeforeSaving();
    if (!mounted || confirmed != true) return;

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

    if (!mounted || result?.saved != true) return;

    await _deleteCurrentCartFromDatabase();

    if (!mounted) return;

    setState(() {
      _currentCart.clear();
      _selectedCartItemIndex = null;
      _rebuildQtyIndexForCurrentCart();
    });

    await _showQuoteSavedActionsDialog(result?.quoteId);
  }

  Future<void> _showQuoteSavedActionsDialog(int? quoteId) async {
    await _showQuoteSavedOptionsDialog(quoteId: quoteId);
  }

  Future<void> _openSavedQuotePdfPreview(int quoteId) async {
    final quoteDetail = await QuotesRepository().getQuoteById(quoteId);
    if (!mounted) return;

    if (quoteDetail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No se pudo cargar la cotización guardada.'),
          backgroundColor: status.error,
        ),
      );
      return;
    }

    final business = await SettingsRepository.getBusinessInfo();
    if (!mounted) return;

    await QuotePrinter.showPreview(
      context: context,
      quote: quoteDetail.quote,
      items: quoteDetail.items,
      clientName: quoteDetail.clientName,
      clientPhone: quoteDetail.clientPhone,
      clientRnc: quoteDetail.clientRnc,
      business: business,
    );
  }

  Future<bool?> _confirmQuoteClientBeforeSaving() async {
    final client = _currentCart.selectedClient;
    final rawClientName = client?.name;
    final rawClientPhone = client?.phone;

    final clientName = rawClientName?.trim().isNotEmpty == true
        ? rawClientName!.trim()
        : 'Consumidor Final';

    final clientPhone = rawClientPhone?.trim().isNotEmpty == true
        ? rawClientPhone!.trim()
        : null;

    const brandColor = Color(0xFF1A56DB);
    const textColor = Color(0xFF0F172A);
    const mutedTextColor = Color(0xFF64748B);
    const borderColor = Color(0xFFE2E8F0);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            width: 460,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 22, 20, 18),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Confirmar cliente',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.of(dialogContext).pop(false),
                        borderRadius: BorderRadius.circular(100),
                        child: const SizedBox(
                          width: 32,
                          height: 32,
                          child: Icon(
                            Icons.close_rounded,
                            size: 24,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, color: borderColor),

                // Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                  child: Column(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBE5FF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          color: brandColor,
                          size: 30,
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text(
                        '¿Deseas guardar esta cotización para este cliente?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),

                      const SizedBox(height: 18),

                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderColor, width: 1),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.account_circle_outlined,
                                color: brandColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    clientName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: textColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    clientPhone ?? 'Sin teléfono registrado',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: mutedTextColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        client == null
                            ? 'No hay un cliente específico seleccionado. Se usará Consumidor Final.'
                            : 'Verifica que el cliente sea correcto antes de continuar.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: mutedTextColor,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, color: borderColor),

                // Footer
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 22),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(42),
                            foregroundColor: textColor,
                            side: const BorderSide(
                              color: Color(0xFFCBD5E1),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(42),
                            backgroundColor: brandColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: const Text('Confirmar'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showQuoteSavedOptionsDialog({int? quoteId}) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            width: 430,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDBE5FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.request_quote_outlined,
                    color: Color(0xFF1A56DB),
                    size: 30,
                  ),
                ),

                const SizedBox(height: 16),

                const Text(
                  'Cotización guardada',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'La cotización fue creada correctamente. Puedes verla, enviarla o salir.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.35,
                  ),
                ),

                const SizedBox(height: 24),

                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: quoteId == null
                        ? null
                        : () {
                            Navigator.of(dialogContext).pop();
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              unawaited(_openSavedQuotePdfPreview(quoteId));
                            });
                          },
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                    label: const Text('Ver cotización'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A56DB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'La opción de enviar PDF se conectará al módulo de envío.',
                          ),
                          backgroundColor: status.info,
                        ),
                      );
                    },
                    icon: const Icon(Icons.send_outlined, size: 20),
                    label: const Text('Enviar cotización PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A56DB),
                      side: const BorderSide(
                        color: Color(0xFFBFD1FF),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Salir'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleSaveSaleAsQuotationPdf() async {
    if (_isQuotePdfFlowRunning || !mounted) return;

    if (_currentCart.items.isEmpty) {
      await _showQuoteStatusCard(
        title: 'Venta incompleta',
        message: 'Agrega al menos un producto antes de crear una cotización.',
        icon: Icons.inventory_2_outlined,
        accentColor: const Color(0xFFF59E0B),
        primaryLabel: 'Entendido',
      );
      return;
    }

    setState(() => _isQuotePdfFlowRunning = true);

    var progressVisible = false;

    Future<void> hideProgress() async {
      if (!mounted || !progressVisible) return;
      progressVisible = false;
      Navigator.of(context, rootNavigator: true).pop();
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    try {
      final selectedClient = await _ensureDefaultCustomerSelected();
      if (!mounted) return;

      if (selectedClient == null || selectedClient.id == null) {
        await _showQuoteStatusCard(
          title: 'Cliente no disponible',
          message: 'No se pudo asignar un cliente por defecto para continuar.',
          icon: Icons.person_off_outlined,
          accentColor: const Color(0xFFDC2626),
          primaryLabel: 'Cerrar',
        );
        return;
      }

      final confirmed = await _showConvertToQuotationConfirmationDialog(
        selectedClient,
      );
      if (!mounted || confirmed != true) return;

      progressVisible = true;
      unawaited(_showQuotationLoadingDialog());

      final quoteDetail = await _createQuotationPdfFlow(
        selectedClient: selectedClient,
      );

      try {
        await _prepareQuotationPdf(quoteDetail);
      } catch (_) {
        await hideProgress();
        final action = await _showQuotationPdfFlowWarningDialog(quoteDetail);
        if (!mounted) return;
        if (action == _QuoteFlowDialogAction.goToQuotation) {
          context.go('/quotes-list');
        }
        return;
      }

      await hideProgress();
      await _clearCurrentCartAfterQuotationPdfSuccess();
      if (!mounted) return;

      final action = await _showQuotationCreatedSuccessDialog(quoteDetail);
      if (!mounted) return;

      switch (action) {
        case _QuoteFlowDialogAction.viewPdf:
          final quoteId = quoteDetail.quote.id;
          if (quoteId != null) {
            await _openSavedQuotePdfPreview(quoteId);
          }
          break;
        case _QuoteFlowDialogAction.goToQuotation:
          context.go('/quotes-list');
          break;
        case _QuoteFlowDialogAction.backToSales:
        case null:
          break;
      }
    } catch (e, st) {
      await hideProgress();
      if (!mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: _handleSaveSaleAsQuotationPdf,
        module: 'sales/quote/pdf_flow',
      );
    } finally {
      if (mounted) {
        setState(() => _isQuotePdfFlowRunning = false);
      }
    }
  }

  Future<QuoteDetailDto> _createQuotationPdfFlow({
    required ClientModel selectedClient,
  }) async {
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
        .toList(growable: false);

    final quoteId = await QuotesRepository().saveQuote(
      clientId: selectedClient.id!,
      userId: await SessionManager.userId(),
      ticketName: _currentCart.name,
      subtotal: _currentCart.calculateSubtotalAfterDiscount(),
      itbisEnabled: _currentCart.itbisEnabled,
      itbisRate: _currentCart.itbisRate,
      itbisAmount: _currentCart.calculateItbis(),
      discountTotal:
          _currentCart.discount + _currentCart.calculateTotalDiscount(),
      total: _currentCart.calculateTotal(),
      items: quoteItems,
    );

    final quoteDetail = await QuotesRepository().getQuoteById(quoteId);
    if (quoteDetail == null) {
      throw StateError('No se pudo cargar la cotización creada.');
    }
    return quoteDetail;
  }

  Future<void> _prepareQuotationPdf(QuoteDetailDto quoteDetail) async {
    final business = await SettingsRepository.getBusinessInfo();
    await QuotePrinter.generatePdf(
      quote: quoteDetail.quote,
      items: quoteDetail.items,
      clientName: quoteDetail.clientName,
      clientPhone: quoteDetail.clientPhone,
      clientRnc: quoteDetail.clientRnc,
      business: business,
    );
  }

  Future<void> _clearCurrentCartAfterQuotationPdfSuccess() async {
    await _deleteCurrentCartFromDatabase();
    if (!mounted) return;

    setState(() {
      _currentCart.clear();
      _selectedCartItemIndex = null;
      _rebuildQtyIndexForCurrentCart();
    });

    await _ensureDefaultCustomerSelected();
  }

  Future<bool?> _showConvertToQuotationConfirmationDialog(
    ClientModel client,
  ) async {
    final clientName = client.name.trim().isNotEmpty
        ? client.name.trim()
        : 'Consumidor Final';
    final clientDocument = client.documentLabel;
    final clientPhone = client.phone?.trim().isNotEmpty == true
        ? client.phone!.trim()
        : null;

    const brandColor = Color(0xFF1A56DB);
    const textColor = Color(0xFF0F172A);
    const mutedTextColor = Color(0xFF64748B);
    const borderColor = Color(0xFFE2E8F0);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            width: 460,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 20, 18),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Convertir venta en cotización',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => Navigator.of(dialogContext).pop(false),
                        borderRadius: BorderRadius.circular(100),
                        child: const SizedBox(
                          width: 32,
                          height: 32,
                          child: Icon(
                            Icons.close_rounded,
                            size: 24,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: borderColor),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                  child: Column(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBE5FF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.request_quote_outlined,
                          color: brandColor,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '¿Seguro que deseas pasar esta venta a cotización?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'La cotización se guardará primero y luego se preparará el PDF con el formato profesional del sistema.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: mutedTextColor,
                          fontSize: 12.5,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor, width: 1),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.account_circle_outlined,
                                color: brandColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    clientName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: textColor,
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    clientDocument ??
                                        clientPhone ??
                                        'Cliente general',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: mutedTextColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
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
                ),
                const Divider(height: 1, color: borderColor),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 18, 28, 22),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(42),
                            foregroundColor: textColor,
                            side: const BorderSide(
                              color: Color(0xFFCBD5E1),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              Navigator.of(dialogContext).pop(true),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(42),
                            backgroundColor: brandColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('Convertir'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<_QuoteFlowDialogAction?> _showQuotationCreatedSuccessDialog(
    QuoteDetailDto quoteDetail,
  ) async {
    if (!mounted) return null;

    final quote = quoteDetail.quote;
    final quoteLabel = quote.id == null
        ? 'Pendiente'
        : 'COT-${quote.id!.toString().padLeft(5, '0')}';

    return showDialog<_QuoteFlowDialogAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            width: 430,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDBE5FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.request_quote_outlined,
                    color: Color(0xFF1A56DB),
                    size: 30,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Cotización creada correctamente',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'La venta fue convertida en cotización y el PDF ya está listo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _buildQuotePdfSummaryRow('Cotización', quoteLabel),
                      const SizedBox(height: 8),
                      _buildQuotePdfSummaryRow(
                        'Cliente',
                        quoteDetail.clientName,
                      ),
                      const SizedBox(height: 8),
                      _buildQuotePdfSummaryRow(
                        'Total',
                        CurrencyDisplay.format(quote.total),
                        emphasize: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_QuoteFlowDialogAction.viewPdf),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                    label: const Text('Ver PDF'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A56DB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_QuoteFlowDialogAction.goToQuotation),
                    icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    label: const Text('Ir a cotización'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1A56DB),
                      side: const BorderSide(
                        color: Color(0xFFBFD1FF),
                        width: 1,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: TextButton(
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_QuoteFlowDialogAction.backToSales),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                    ),
                    child: const Text('Volver a ventas'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuotePdfSummaryRow(
    String label,
    String value, {
    bool emphasize = false,
  }) {
    final valueStyle = TextStyle(
      color: const Color(0xFF0F172A),
      fontSize: emphasize ? 14.5 : 13.2,
      fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
      height: 1.2,
    );
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: valueStyle,
          ),
        ),
      ],
    );
  }

  Future<void> _showQuotationLoadingDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            child: Container(
              width: 360,
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.14),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBE5FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.8,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFF1A56DB),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Creando cotización y preparando PDF',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Estamos procesando la venta con el formato profesional de cotización.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12.8,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showQuoteStatusCard({
    required String title,
    required String message,
    required IconData icon,
    required Color accentColor,
    required String primaryLabel,
  }) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            width: 420,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: accentColor, size: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13.2,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(primaryLabel),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<_QuoteFlowDialogAction?> _showQuotationPdfFlowWarningDialog(
    QuoteDetailDto quoteDetail,
  ) async {
    if (!mounted) return null;
    final quoteLabel = quoteDetail.quote.id == null
        ? 'Pendiente'
        : 'COT-${quoteDetail.quote.id!.toString().padLeft(5, '0')}';

    return showDialog<_QuoteFlowDialogAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            width: 430,
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.14),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFF59E0B),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Cotización creada con advertencia',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'La cotización $quoteLabel fue guardada, pero el PDF no pudo generarse en este momento.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 13.2,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_QuoteFlowDialogAction.goToQuotation),
                    icon: const Icon(Icons.open_in_new_rounded, size: 20),
                    label: const Text('Ir a cotización'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A56DB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: TextButton(
                    onPressed: () => Navigator.of(
                      dialogContext,
                    ).pop(_QuoteFlowDialogAction.backToSales),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                    ),
                    child: const Text('Volver a ventas'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPanelDocumentTypeDropdown() {
    if (_fiscalReceiptSettings.enabled) {
      return _buildPanelFiscalReceiptDropdown();
    }

    final currentType = _currentSalesDocumentType;
    final availableTypes = <_SalesDocumentType>[
      _SalesDocumentType.consumidorFinal,
      if (_isElectronicInvoicingFeatureEnabled)
        _SalesDocumentType.creditoFiscal,
    ];

    return Builder(
      builder: (fieldContext) => _buildProfessionalDropdownField(
        supportingText: 'Numeracion',
        value: _salesDocumentTypeLabel(currentType),
        onTap: () => unawaited(
          _showAnchoredPopover<void>(
            anchorContext: fieldContext,
            width: 300,
            maxHeight: 260,
            childBuilder: (dialogContext, close) {
              return _buildProfessionalDropdownSurface(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shrinkWrap: true,
                  children: [
                    _buildDropdownGroupHeader('No electrónicas'),
                    for (final type in availableTypes)
                      _buildDropdownOptionTile(
                        title: _salesDocumentTypeLabel(type),
                        selected: type == currentType,
                        onTap: () {
                          close();
                          unawaited(_setSalesDocumentType(type));
                        },
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPanelFiscalReceiptDropdown() {
    final activeTypes = _fiscalReceiptTypes
        .where((type) => type.isAvailable)
        .toList(growable: false);
    final selectedId = _currentCart.fiscalReceiptTypeId;
    final selected = activeTypes
        .where((type) => type.id == selectedId)
        .firstOrNull;
    final label = selected == null
        ? 'Sin comprobante'
        : '${selected.name} · ${selected.nextReceiptNumber}';

    return Builder(
      builder: (fieldContext) => _buildProfessionalDropdownField(
        supportingText: 'Comprobante fiscal',
        value: activeTypes.isEmpty ? 'Configura comprobantes' : label,
        onTap: () => unawaited(
          _showAnchoredPopover<void>(
            anchorContext: fieldContext,
            width: 340,
            maxHeight: 320,
            childBuilder: (dialogContext, close) {
              return _buildProfessionalDropdownSurface(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shrinkWrap: true,
                  children: [
                    _buildDropdownGroupHeader('NCF locales'),
                    if (activeTypes.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 10, 16, 14),
                        child: Text(
                          'Configura comprobantes fiscales en Configuración > Comprobantes.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12.5,
                            height: 1.25,
                          ),
                        ),
                      )
                    else ...[
                      _buildDropdownOptionTile(
                        title: 'Sin comprobante',
                        selected: selectedId == null,
                        onTap: () {
                          close();
                          _updateCurrentCart(() {
                            _currentCart.fiscalReceiptTypeId = null;
                          });
                        },
                      ),
                      for (final type in activeTypes)
                        _buildDropdownOptionTile(
                          title: '${type.name} (${type.code})',
                          trailingText: type.nextReceiptNumber,
                          selected: type.id == selectedId,
                          onTap: () {
                            close();
                            _updateCurrentCart(() {
                              _currentCart.fiscalReceiptTypeId = type.id;
                            });
                          },
                        ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPanelClientControl() {
    final client = _currentCart.selectedClient;
    _scheduleClientFieldSync();

    return CompositedTransformTarget(
      link: _clientSearchLayerLink,
      child: SizedBox.expand(
        key: _clientSearchFieldKey,
        child: TextField(
          controller: _clientSearchController,
          focusNode: _clientSearchFocusNode,
          textAlignVertical: TextAlignVertical.center,
          onTap: _openClientSearchOverlay,
          onTapOutside: (_) {
            // El desplegable vive en un Overlay fuera del TapRegion del campo.
            // Mantener el foco permite que el InkWell complete su onTap.
            if (_clientSearchOverlay != null) return;
            _clientSearchFocusNode.unfocus();
          },
          onChanged: (value) {
            _clientSearchQuery = value;
            if (_clientSearchOverlay == null) {
              _openClientSearchOverlay();
            }
            _clientSearchOverlay?.markNeedsBuild();
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            hintText: 'Buscar o seleccionar cliente',
            hintStyle: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13.4,
              fontWeight: FontWeight.w500,
              height: 1.0,
            ),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 0,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(_customerRowControlRadius),
              borderSide: const BorderSide(color: Color(0xFFD6E0EA), width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(_customerRowControlRadius),
              borderSide: const BorderSide(color: Color(0xFFD6E0EA), width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(_customerRowControlRadius),
              borderSide: const BorderSide(
                color: Color(0xFF1A56DB),
                width: 1.2,
              ),
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 108,
              maxWidth: 108,
              minHeight: _customerRowControlHeight,
              maxHeight: _customerRowControlHeight,
            ),
            suffixIcon: SizedBox(
              width: 108,
              height: _customerRowControlHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (client != null)
                    _buildClientFieldIcon(
                      icon: Icons.edit_outlined,
                      onTap: () => unawaited(_showEditClientFromSales(client)),
                    ),
                  if (client != null)
                    _buildClientFieldIcon(
                      icon: Icons.close_rounded,
                      onTap: () {
                        _removeClient();
                        _clientSearchController.clear();
                        _clientSearchQuery = '';
                        _clientSearchOverlay?.markNeedsBuild();
                      },
                    ),
                  const Spacer(),
                  _buildClientFieldIcon(
                    icon: Icons.keyboard_arrow_down_rounded,
                    onTap: _openClientSearchOverlay,
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),
          style: TextStyle(
            color: salesDetailTextColor,
            fontSize: 14.1,
            fontWeight: FontWeight.w500,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildClientSearchDropdown() {
    final client = _currentCart.selectedClient;
    final defaultClient = _findDefaultClientIn(_clients);
    final normalizedQuery = _clientSearchQuery.trim().toLowerCase();
    final filteredClients = _clients.where((option) {
      if (_isDefaultClientName(option.nombre)) {
        return false;
      }
      if (normalizedQuery.isEmpty) return true;

      final name = option.nombre.toLowerCase();
      final phone = option.telefono?.toLowerCase() ?? '';
      final rnc = option.rnc?.toLowerCase() ?? '';
      final cedula = option.cedula?.toLowerCase() ?? '';

      return name.contains(normalizedQuery) ||
          phone.contains(normalizedQuery) ||
          rnc.contains(normalizedQuery) ||
          cedula.contains(normalizedQuery);
    }).toList();

    Widget compactTile({
      required String title,
      String? subtitle,
      required bool selected,
      required VoidCallback onTap,
      Widget? trailing,
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: selected ? const Color(0xFFF5F8FE) : Colors.transparent,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.2,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: const Color(0xFF17324D),
                    ),
                  ),
                ),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 11.8,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF6B7C8E),
                      ),
                    ),
                  ),
                ],
                if (trailing != null) ...[const SizedBox(width: 6), trailing],
              ],
            ),
          ),
        ),
      );
    }

    return _buildProfessionalDropdownSurface(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: Material(
          color: Colors.transparent,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            itemCount: filteredClients.length + 1,
            separatorBuilder: (context, index) {
              return const Divider(height: 1, indent: 12, endIndent: 12);
            },
            itemBuilder: (context, index) {
              if (index == 0) {
                final selected =
                    defaultClient?.id != null &&
                    client?.id == defaultClient!.id;

                return compactTile(
                  title: defaultClient?.nombre ?? 'Consumidor Final',
                  subtitle: 'Cliente general',
                  selected: selected,
                  onTap: () async {
                    final resolved =
                        defaultClient ?? await _resolveOrCreateDefaultClient();
                    if (!mounted || resolved == null) return;
                    await _applySelectedClient(resolved);
                  },
                );
              }

              final option = filteredClients[index - 1];

              final optionMeta = (option.telefono?.trim().isNotEmpty ?? false)
                  ? option.telefono!.trim()
                  : ((option.rnc?.trim().isNotEmpty ?? false)
                        ? option.rnc!.trim()
                        : ((option.cedula?.trim().isNotEmpty ?? false)
                              ? option.cedula!.trim()
                              : ''));

              final selected = option.id == client?.id;

              return compactTile(
                title: option.nombre,
                subtitle: optionMeta.isEmpty ? null : optionMeta,
                selected: selected,
                onTap: () async {
                  await _applySelectedClient(option);
                },
                trailing: InkWell(
                  onTap: () async {
                    _closeClientSearchOverlay();
                    await _showEditClientFromSales(option);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: const SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(
                      child: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPanelNewClientButton() {
    return SizedBox.expand(
      child: ElevatedButton.icon(
        onPressed: _showCreateClientFromSales,
        style: ElevatedButton.styleFrom(
          fixedSize: const Size(
            _customerNewButtonWidth,
            _customerRowControlHeight,
          ),
          minimumSize: const Size(
            _customerNewButtonWidth,
            _customerRowControlHeight,
          ),
          maximumSize: const Size(
            _customerNewButtonWidth,
            _customerRowControlHeight,
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          backgroundColor: const Color(0xFFF1F5FF),
          foregroundColor: const Color(0xFF1A56DB),
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          alignment: Alignment.center,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_customerRowControlRadius),
            side: const BorderSide(color: Color(0xFFC7D2FE), width: 1),
          ),
          textStyle: const TextStyle(
            fontSize: 12.8,
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
        icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
        label: const Text(
          'Nuevo',
          style: TextStyle(
            fontSize: 12.8,
            fontWeight: FontWeight.w600,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildClientFieldIcon({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 28,
        height: _customerRowControlHeight,
        child: Center(
          child: Icon(icon, size: 18, color: salesDetailMutedTextColor),
        ),
      ),
    );
  }

  Widget _buildProfessionalDropdownField({
    String? supportingText,
    required String value,
    required VoidCallback onTap,
    Widget? suffix,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: supportingText == null ? 42 : 48,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD6E0EA), width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withOpacity(0.025),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: supportingText == null
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (supportingText != null)
                      Text(
                        supportingText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF6B7A92),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          height: 1.05,
                        ),
                      ),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: salesDetailTextColor,
                        fontSize: 14.0,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ),
              ),
              if (suffix != null) ...[const SizedBox(width: 6), suffix],
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: salesDetailMutedTextColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfessionalDropdownSurface({required Widget child}) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD9E3EF)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.07),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _buildDropdownGroupHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildDropdownOptionTile({
    required String title,
    String? subtitle,
    String? trailingText,
    required bool selected,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: selected ? const Color(0xFFF5F8FE) : Colors.transparent,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                    height: 1.05,
                    color: const Color(0xFF17324D),
                  ),
                ),
              ),
              if (trailingText != null && trailingText.isNotEmpty) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      trailingText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12.4,
                        fontWeight: FontWeight.w400,
                        height: 1.05,
                        color: Color(0xFF6B7C8E),
                      ),
                    ),
                  ),
                ),
              ] else if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(width: 12),
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12.2,
                        fontWeight: FontWeight.w400,
                        height: 1.05,
                        color: Color(0xFF6B7C8E),
                      ),
                    ),
                  ),
                ),
              ],
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: Color(0xFF1A56DB),
                  ),
                ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
        ),
      ),
    );
  }

  /// CARD A: Ticket / Cliente
  // ignore: unused_element
  Widget _buildTicketHeaderCard({bool embedded = false}) {
    final totalTickets = _carts.length;

    Color actionBackground(bool isHovered) {
      final base = salesDetailSurfaceColor;
      final hover = salesDetailSurfaceStrongColor;
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
                  ? salesDetailSelectedBorderColor
                  : salesDetailBorderColor,
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
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: salesDetailTextColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: salesDetailTextColor,
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
                  ? salesDetailSelectedBorderColor
                  : salesDetailBorderColor,
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
                  width: 40,
                  height: 40,
                  child: Center(
                    child: Icon(icon, size: 20, color: salesDetailTextColor),
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
              tooltip: 'Venta común',
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
  Widget _buildItemsListCard({
    bool embedded = false,
    _SalesResponsiveMetrics? metrics,
  }) {
    const emptyKey = ValueKey<String>('ticket_items_empty');
    const listKey = ValueKey<String>('ticket_items_list');

    const panelBackground = Color(0xFFF8FAFC);
    const listBackground = Color(0xFFFAFCFE);
    const panelBorderColor = Color(0xFFD9E3F0);

    final m =
        metrics ??
        _SalesResponsiveMetrics(
          isCompactDesktop: false,
          isTightDesktop: false,
          isShortDesktop: false,
          isVeryShortDesktop: false,
          ticketPanelWidth: 550,
          productCardWidth: 220,
          productCardHeight: 254,
          productHorizontalMargin: 12,
          productVerticalMargin: 10,
          catalogLeftPadding: 14,
          controlBarTopPadding: 20,
          controlBarRightPadding: 18,
          controlBarHeight: 42,
          productImageSize: 112,
          productImageBoxSize: 118,
          productNameFontSize: 13.4,
          productPriceFontSize: 16.5,
          ticketHorizontalPadding: 18,
          ticketHeaderVerticalPadding: 13,
          totalAreaHeight: 86,
          categorySidebarWidth: 64,
          categoryItemHeight: 48,
          categoryAvatarOuterSize: 44,
          categoryAvatarInnerSize: 36,
          footerTicketHeight: 58,
          footerTicketTabHeight: 46,
          spaceBelowControlBar: 14,
        );

    final hasItems = _currentCart.items.isNotEmpty;
    final showScrollbar = embedded ? _currentCart.items.length > 5 : hasItems;

    Widget buildItemsList() {
      return Scrollbar(
        controller: _ticketItemsScrollController,
        thumbVisibility: showScrollbar,
        thickness: 5,
        radius: const Radius.circular(20),
        interactive: true,
        child: ListView.separated(
          controller: _ticketItemsScrollController,
          primary: false,
          shrinkWrap: embedded,
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 3, 0, 3),
          itemCount: _currentCart.items.length,
          separatorBuilder: (context, index) {
            return const SizedBox.shrink();
          },
          itemBuilder: (context, index) {
            final item = _currentCart.items[index];

            return _buildCartItemRow(item, index, metrics: m);
          },
        ),
      );
    }

    final Widget listContent = !hasItems
        ? KeyedSubtree(key: emptyKey, child: _buildEmptyCartView())
        : KeyedSubtree(key: listKey, child: buildItemsList());

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );

        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.015),
              end: Offset.zero,
            ).animate(fade),
            child: child,
          ),
        );
      },
      child: Container(
        color: panelBackground,
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
        child: Container(
          key: ValueKey<bool>(hasItems),
          decoration: BoxDecoration(
            color: hasItems ? listBackground : panelBackground,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(5),
              bottomLeft: Radius.circular(5),
              bottomRight: Radius.circular(12),
            ),
            border: hasItems
                ? Border.all(color: panelBorderColor, width: 0.75)
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: listContent,
        ),
      ),
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

  Widget _buildCartItemRow(
    SaleItemModel item,
    int index, {
    _SalesResponsiveMetrics? metrics,
  }) {
    final m =
        metrics ??
        _SalesResponsiveMetrics(
          isCompactDesktop: false,
          isTightDesktop: false,
          isShortDesktop: false,
          isVeryShortDesktop: false,
          ticketPanelWidth: 550,
          productCardWidth: 220,
          productCardHeight: 254,
          productHorizontalMargin: 12,
          productVerticalMargin: 10,
          catalogLeftPadding: 14,
          controlBarTopPadding: 20,
          controlBarRightPadding: 18,
          controlBarHeight: 42,
          productImageSize: 112,
          productImageBoxSize: 118,
          productNameFontSize: 13.4,
          productPriceFontSize: 16.5,
          ticketHorizontalPadding: 18,
          ticketHeaderVerticalPadding: 13,
          totalAreaHeight: 86,
          categorySidebarWidth: 64,
          categoryItemHeight: 48,
          categoryAvatarOuterSize: 44,
          categoryAvatarInnerSize: 36,
          footerTicketHeight: 58,
          footerTicketTabHeight: 46,
          spaceBelowControlBar: 14,
        );
    final isCompact = m.isCompactDesktop || m.ticketPanelWidth <= 440;
    final isHovered = _hoveredCartItemIndexes.contains(index);
    final animationToken = _cartItemAnimationTokens[index] ?? 0;
    final subtotal = (item.qty * item.unitPrice) - item.discountLine;
    const rowDividerColor = Color(0xFFE8EEF6);
    final showActions = isHovered;
    final rowBackground = isHovered ? const Color(0xFFFAFCFF) : Colors.white;
    final isNewItem = animationToken > 0;

    return TweenAnimationBuilder<double>(
      key: ValueKey<String>('cart-row-$index-$animationToken'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        // Animación de entrada: slide desde la izquierda + fade + scale
        final slideOffset = (1 - value) * -120;
        final opacity = value.clamp(0.0, 1.0);
        final scale = 0.85 + (value * 0.15);

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(slideOffset, 0),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.centerLeft,
              child: child,
            ),
          ),
        );
      },
      child: isNewItem
          ? _AnimatedNewItemHighlight(
              child: _buildCartItemContent(
                item,
                index,
                rowBackground,
                rowDividerColor,
                showActions,
                subtotal,
                isCompact: isCompact,
              ),
            )
          : _buildCartItemContent(
              item,
              index,
              rowBackground,
              rowDividerColor,
              showActions,
              subtotal,
              isCompact: isCompact,
            ),
    );
  }

  Widget _buildCartItemContent(
    SaleItemModel item,
    int index,
    Color rowBackground,
    Color rowDividerColor,
    bool showActions,
    double subtotal, {
    bool isCompact = false,
  }) {
    return Builder(
      builder: (rowContext) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) =>
            _setHoverStateDeferred(_hoveredCartItemIndexes, index, true),
        onExit: (_) =>
            _setHoverStateDeferred(_hoveredCartItemIndexes, index, false),
        child: InkWell(
          onTap: () => setState(() => _selectedCartItemIndex = index),
          onDoubleTap: () => unawaited(
            _showItemEditPopover(
              rowContext,
              index,
              focus: _InlineItemFocus.qty,
            ),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: EdgeInsets.symmetric(
              horizontal: isCompact ? 8 : 10,
              vertical: isCompact ? 8.5 : 10.5,
            ),
            decoration: BoxDecoration(
              color: rowBackground,
              border: Border(
                bottom: BorderSide(color: rowDividerColor, width: 1),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // LEFT: Product name and unit price.
                Expanded(
                  flex: isCompact ? 5 : 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.productNameSnapshot,
                        style: TextStyle(
                          fontSize: isCompact ? 12.6 : 13.8,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF111827),
                          height: 1.12,
                          letterSpacing: -0.12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                      SizedBox(height: isCompact ? 4 : 6),
                      Text(
                        'RD\$${CurrencyDisplay.formatPlain(item.unitPrice, decimalDigits: 2)}',
                        style: TextStyle(
                          fontSize: isCompact ? 10.6 : 11.5,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                          height: 1.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: isCompact ? 8 : 14),

                // MIDDLE: Compact quantity controls.
                Container(
                  width: isCompact ? 84 : 112,
                  height: isCompact ? 30 : 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                      width: 0.85,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      InkWell(
                        onTap: () {
                          if (item.qty > 1) {
                            _updateCurrentCart(
                              () => _currentCart.updateQuantity(
                                index,
                                item.qty - 1,
                              ),
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: isCompact ? 24 : 26,
                          height: isCompact ? 24 : 26,
                          child: Icon(
                            Icons.remove,
                            size: isCompact ? 15 : 16,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isCompact ? 24 : 28,
                        child: Text(
                          item.qty == item.qty.roundToDouble()
                              ? item.qty.toStringAsFixed(0)
                              : item.qty.toStringAsFixed(2),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isCompact ? 13.2 : 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF111827),
                            height: 1.0,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => _incrementCartItemQty(item, index),
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: isCompact ? 24 : 26,
                          height: isCompact ? 24 : 26,
                          child: Icon(
                            Icons.add,
                            size: isCompact ? 15 : 16,
                            color: const Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: isCompact ? 8 : 12),

                // RIGHT: Total line price + hover actions.
                SizedBox(
                  width: isCompact ? 92 : 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: showActions ? 0 : 1,
                        child: IgnorePointer(
                          ignoring: showActions,
                          child: Text(
                            'RD\$${CurrencyDisplay.formatPlain(subtotal, decimalDigits: 2)}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: isCompact ? 13.4 : 14.2,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF111827),
                              height: 1.0,
                              letterSpacing: -0.18,
                            ),
                          ),
                        ),
                      ),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: showActions ? 1 : 0,
                        child: IgnorePointer(
                          ignoring: !showActions,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                _buildCartRowActionButton(
                                  id: 'edit-$index',
                                  icon: Image.asset(
                                    'assets/imagen/iconos/editar-texto.png',
                                    width: isCompact ? 20 : 22,
                                    height: isCompact ? 20 : 22,
                                    fit: BoxFit.contain,
                                  ),
                                  tooltip: 'Editar',
                                  onTap: () => unawaited(
                                    _showItemEditPopover(
                                      rowContext,
                                      index,
                                      focus: _InlineItemFocus.qty,
                                    ),
                                  ),
                                ),
                                SizedBox(width: isCompact ? 6 : 10),
                                _buildCartRowActionButton(
                                  id: 'delete-$index',
                                  icon: Image.asset(
                                    'assets/imagen/iconos/eliminar.png',
                                    width: isCompact ? 20 : 22,
                                    height: isCompact ? 20 : 22,
                                    fit: BoxFit.contain,
                                  ),
                                  tooltip: 'Eliminar',
                                  onTap: () => _updateCurrentCart(() {
                                    if (_inlineEditCartItemIndex == index) {
                                      _inlineEditCartItemIndex = null;
                                    }
                                    if (_selectedCartItemIndex == index) {
                                      _selectedCartItemIndex = null;
                                    }
                                    _currentCart.removeItem(index);
                                  }),
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCartRowActionButton({
    required String id,
    required Widget icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final isHovered = _hoveredCartRowActions.contains(id);
    const buttonSize = 32.0;
    const labelGap = 8.0;

    return MouseRegion(
      onEnter: (_) => _setHoverStateDeferred(_hoveredCartRowActions, id, true),
      onExit: (_) => _setHoverStateDeferred(_hoveredCartRowActions, id, false),
      child: SizedBox(
        width: buttonSize,
        height: buttonSize,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Positioned(
              right: buttonSize + labelGap,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 120),
                opacity: isHovered ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !isHovered,
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF172033),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.16),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        tooltip,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  width: buttonSize,
                  height: buttonSize,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: icon),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildCompactStepperButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: salesDetailSurfaceStrongColor,
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

  Widget _buildTotalAndActionsCard({
    bool embedded = false,
    _SalesResponsiveMetrics? metrics,
  }) {
    final m =
        metrics ??
        _SalesResponsiveMetrics(
          isCompactDesktop: false,
          isTightDesktop: false,
          isShortDesktop: false,
          isVeryShortDesktop: false,
          ticketPanelWidth: 550,
          productCardWidth: 220,
          productCardHeight: 254,
          productHorizontalMargin: 12,
          productVerticalMargin: 10,
          catalogLeftPadding: 14,
          controlBarTopPadding: 20,
          controlBarRightPadding: 18,
          controlBarHeight: 42,
          productImageSize: 112,
          productImageBoxSize: 118,
          productNameFontSize: 13.4,
          productPriceFontSize: 16.5,
          ticketHorizontalPadding: 18,
          ticketHeaderVerticalPadding: 13,
          totalAreaHeight: 86,
          categorySidebarWidth: 64,
          categoryItemHeight: 48,
          categoryAvatarOuterSize: 44,
          categoryAvatarInnerSize: 36,
          footerTicketHeight: 58,
          footerTicketTabHeight: 46,
          spaceBelowControlBar: 14,
        );

    final totalAmount = _currentCart.calculateTotal();
    final itemsCount = _currentCart.items.length;

    final productCountLabel = itemsCount == 1
        ? '1 producto'
        : '$itemsCount productos';

    final totalLabel = CurrencyDisplay.format(totalAmount, decimalDigits: 2);
    final canSell = _currentCart.items.isNotEmpty;

    const fullposBlue = Color(0xFF1A56DB);
    const fullposBlueDark = Color(0xFF1443B0);
    const borderColor = Color(0xFFB8C4D1);
    const softBlue = Color(0xFFEAF1FF);
    const disabledBackground = Color(0xFFD9E1E8);

    const primaryRadius = BorderRadius.only(
      topLeft: Radius.circular(18),
      topRight: Radius.circular(7),
      bottomLeft: Radius.circular(7),
      bottomRight: Radius.circular(18),
    );

    const secondaryRadius = BorderRadius.only(
      topLeft: Radius.circular(14),
      topRight: Radius.circular(6),
      bottomLeft: Radius.circular(6),
      bottomRight: Radius.circular(14),
    );

    final isCompact = m.isCompactDesktop;
    final rowHeight = isCompact ? 64.0 : 70.0;
    final sideCardWidth = isCompact ? 58.0 : 66.0;
    final footerHeight = isCompact ? 36.0 : 40.0;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Builder(
          builder: (context) {
            final grossSubtotal = _currentCart.calculateGrossSubtotal();

            final discountsCombined = _currentCart
                .calculateTotalDiscountsCombined();

            final shouldShowFiscalTax =
                _currentSalesDocumentType == _SalesDocumentType.creditoFiscal &&
                _currentCart.itbisEnabled;

            final itbisAmount = shouldShowFiscalTax
                ? _currentCart.calculateItbis()
                : 0.0;

            final itbisLabel =
                'ITBIS (${(_currentCart.itbisRate * 100).toStringAsFixed(2)}%)';

            final showSummary = discountsCombined > 0 || shouldShowFiscalTax;

            if (!showSummary) {
              return const SizedBox.shrink();
            }

            return Container(
              width: double.infinity,
              margin: EdgeInsets.fromLTRB(
                6,
                isCompact ? 6 : 8,
                6,
                isCompact ? 5 : 6,
              ),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: secondaryRadius,
                border: Border.all(color: const Color(0xFFE2E8F0), width: 0.85),
              ),
              child: Column(
                children: [
                  _buildSummaryRow('Subtotal', grossSubtotal, false),
                  if (discountsCombined > 0) ...[
                    const SizedBox(height: 8),
                    _buildSummaryRow(
                      'Descuento',
                      -discountsCombined,
                      false,
                      color: scheme.error,
                    ),
                  ],
                  if (shouldShowFiscalTax) ...[
                    const SizedBox(height: 8),
                    _buildSummaryRow(itbisLabel, itbisAmount, false),
                  ],
                ],
              ),
            );
          },
        ),

        // ─────────────────────────────────────────────
        // FILA PRINCIPAL: COBRAR + VENTAS
        // ─────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(
            6,
            isCompact ? 6 : 8,
            6,
            isCompact ? 5 : 6,
          ),
          child: SizedBox(
            height: rowHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ─────────────────────────────────────────────
                // COBRAR + TOTAL
                // ─────────────────────────────────────────────
                Expanded(
                  child: ElevatedButton(
                    onPressed: canSell
                        ? () => _processPayment(
                            SaleKind.invoice,
                            initialPrintTicket: false,
                          )
                        : null,
                    style: ButtonStyle(
                      padding: WidgetStateProperty.all(
                        EdgeInsets.fromLTRB(
                          isCompact ? 16 : 20,
                          8,
                          isCompact ? 20 : 24,
                          8,
                        ),
                      ),
                      elevation: WidgetStateProperty.all(0),
                      shadowColor: WidgetStateProperty.all(Colors.transparent),
                      shape: WidgetStateProperty.all(
                        const RoundedRectangleBorder(
                          borderRadius: primaryRadius,
                        ),
                      ),
                      backgroundColor: WidgetStateProperty.resolveWith<Color>((
                        states,
                      ) {
                        if (states.contains(WidgetState.disabled)) {
                          return disabledBackground;
                        }
                        if (states.contains(WidgetState.hovered)) {
                          return fullposBlueDark;
                        }
                        if (states.contains(WidgetState.pressed)) {
                          return const Color(0xFF10388F);
                        }
                        return fullposBlue;
                      }),
                      foregroundColor: WidgetStateProperty.all(Colors.white),
                    ),
                    child: Row(
                      children: [
                        Text(
                          'Cobrar',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isCompact ? 17 : 18.5,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            letterSpacing: -0.25,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: isCompact ? 2 : 4),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                totalLabel,
                                maxLines: 1,
                                softWrap: false,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: isCompact ? 24 : 26,
                                  fontWeight: FontWeight.w900,
                                  height: 1,
                                  letterSpacing: -0.45,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // ─────────────────────────────────────────────
                // VENTAS RECIENTES
                // ─────────────────────────────────────────────
                Tooltip(
                  message: 'Ver ventas recientes',
                  waitDuration: const Duration(milliseconds: 350),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _toggleRecentSalesPanel,
                      borderRadius: secondaryRadius,
                      splashColor: fullposBlue.withOpacity(0.08),
                      hoverColor: fullposBlue.withOpacity(0.035),
                      child: Ink(
                        width: sideCardWidth,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: secondaryRadius,
                          border: Border.all(color: borderColor, width: 0.9),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.receipt_long_rounded,
                                    size: isCompact ? 24 : 27,
                                    color: fullposBlue,
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Ventas',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: fullposBlue,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_recentSales.isNotEmpty)
                              Positioned(
                                top: -7,
                                right: -5,
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 18,
                                    minHeight: 18,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF16A39A),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.4,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF16A39A,
                                        ).withOpacity(0.18),
                                        blurRadius: 7,
                                        spreadRadius: -2,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    _recentSales.length > 9
                                        ? '9+'
                                        : '${_recentSales.length}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),
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
        ),

        // ─────────────────────────────────────────────
        // BARRA INFERIOR: PRODUCTOS + CANCELAR VENTA
        // ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canSell ? () => unawaited(_cancelCurrentCart()) : null,
              borderRadius: secondaryRadius,
              splashColor: scheme.error.withOpacity(0.06),
              hoverColor: scheme.error.withOpacity(0.025),
              child: Ink(
                height: footerHeight,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: secondaryRadius,
                  border: Border.all(color: borderColor, width: 0.9),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: softBlue,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        productCountLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: fullposBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),

                    const Spacer(),

                    Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: canSell ? scheme.error : const Color(0xFF94A3B8),
                    ),

                    const SizedBox(width: 5),

                    Text(
                      'Cancelar venta',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: canSell ? scheme.error : const Color(0xFF94A3B8),
                        fontSize: isCompact ? 12 : 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (embedded) {
      return content;
    }

    return Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: salesDetailPanelColor,
        borderRadius: secondaryRadius,
        border: Border.all(color: salesDetailBorderColor, width: 0.9),
      ),
      child: content,
    );
  }

  Widget _buildSummaryRow(
    String label,
    double amount,
    bool isTotal, {
    Color? color,
  }) {
    final labelColor = color ?? const Color(0xFF64748B);
    final valueColor = color ?? const Color(0xFF111827);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isTotal ? 14.5 : 13.2,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
              color: labelColor,
              height: 1.18,
              letterSpacing: 0.1,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Text(
          CurrencyDisplay.format(amount, decimalDigits: 2),
          style: TextStyle(
            fontSize: isTotal ? 17 : 15.2,
            fontWeight: isTotal ? FontWeight.w800 : FontWeight.w700,
            color: valueColor,
            height: 1.12,
            letterSpacing: 0.05,
          ),
        ),
      ],
    );
  }

  Future<void> _addFooterTicket() async {
    if (!mounted) return;
    setState(() {
      final cart = _Cart(name: _nextUniqueSaleLabel());
      _applySalesDefaultsToCart(cart);
      _carts.add(cart);
      _currentCartIndex = _carts.length - 1;
      _rebuildQtyIndexForCurrentCart();
    });
    _handleCurrentCartChanged();
    await _ensureDefaultCustomerSelected();
    await _saveAllCartsToDatabase();
  }

  Future<void> _selectFooterTicket(int index) async {
    if (!mounted || index < 0 || index >= _carts.length) return;
    setState(() {
      _currentCartIndex = index;
      _rebuildQtyIndexForCurrentCart();
    });
    _handleCurrentCartChanged();
    await _ensureDefaultCustomerSelected();
  }

  Future<void> _renameFooterTicket(int index) async {
    if (!mounted || index < 0 || index >= _carts.length) return;
    final controller = TextEditingController(text: _carts[index].name);

    try {
      final newName = await showDialog<String>(
        context: context,
        builder: (context) {
          final borderColor = const Color(0xFFDCE4EC);
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 42,
              vertical: 24,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Material(
                color: Colors.white,
                child: SizedBox(
                  width: 680,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 22, 18, 18),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Renombrar factura pendiente',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF1F3B5B),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.close,
                                color: Color(0xFF9AA8B6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: borderColor),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 28, 28, 34),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: RichText(
                                text: const TextSpan(
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Color(0xFF6F7F8F),
                                  ),
                                  children: [
                                    TextSpan(
                                      text:
                                          'Para cambiar el prefijo general tienes que dirigirte a ',
                                    ),
                                    TextSpan(
                                      text: 'aquí',
                                      style: TextStyle(
                                        color: Color(0xFF11B8B2),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 34),
                            const Text(
                              'Nombre *',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF687785),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: 266,
                              child: TextField(
                                controller: controller,
                                autofocus: true,
                                decoration: InputDecoration(
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide: BorderSide(color: borderColor),
                                  ),
                                  focusedBorder: const OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(6),
                                    ),
                                    borderSide: BorderSide(
                                      color: Color(0xFFBFD1E2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: borderColor),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
                        child: Row(
                          children: [
                            const Text(
                              '* Campos obligatorios',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7C8A97),
                              ),
                            ),
                            const Spacer(),
                            OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(102, 40),
                                side: BorderSide(color: borderColor),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cancelar'),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: () => Navigator.of(
                                context,
                              ).pop(controller.text.trim()),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(92, 40),
                                backgroundColor: const Color(0xFF1A56DB),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Guardar'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

      final trimmed = (newName ?? '').trim();
      if (trimmed.isEmpty || !mounted) return;

      final uniqueName = _ensureUniqueLabel(trimmed, excludeIndex: index);
      setState(() => _carts[index].name = uniqueName);
      if (_carts[index].ticketId != null) {
        await TicketsRepository().updateTicketName(
          _carts[index].ticketId!,
          uniqueName,
        );
      }
      unawaited(_saveAllCartsToDatabase());
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteFooterTicket(int index) async {
    if (!mounted || index < 0 || index >= _carts.length || _carts.length <= 1) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final borderColor = const Color(0xFFDCE4EC);
        final label = _footerTicketLabel(_carts[index], index);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 42,
            vertical: 24,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Material(
              color: Colors.white,
              child: SizedBox(
                width: 680,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 22, 18, 18),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Eliminar venta pendiente',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1F3B5B),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            icon: const Icon(
                              Icons.close,
                              color: Color(0xFF9AA8B6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: borderColor),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 28, 28, 34),
                      child: Center(
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 15,
                              color: Color(0xFF3D4D5C),
                            ),
                            children: [
                              const TextSpan(
                                text:
                                    '¿Seguro que quieres eliminar la venta pendiente? ',
                              ),
                              TextSpan(
                                text: label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF203854),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Divider(height: 1, color: borderColor),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
                      child: Row(
                        children: [
                          const Text(
                            '* Campos obligatorios',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7C8A97),
                            ),
                          ),
                          const Spacer(),
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(64, 40),
                              side: BorderSide(color: borderColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('No'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(64, 40),
                              backgroundColor: const Color(0xFF1A56DB),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Si'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final cart = _carts[index];
    final tempCartId = cart.tempCartId;
    final ticketId = cart.ticketId;

    setState(() {
      _carts.removeAt(index);
      if (_currentCartIndex >= _carts.length) {
        _currentCartIndex = _carts.length - 1;
      } else if (_currentCartIndex > index) {
        _currentCartIndex -= 1;
      } else if (_currentCartIndex == index) {
        _currentCartIndex = index.clamp(0, _carts.length - 1);
      }
      _rebuildQtyIndexForCurrentCart();
    });
    _handleCurrentCartChanged();

    if (tempCartId != null) {
      unawaited(_deleteTempCartFromDatabase(tempCartId));
    }
    if (ticketId != null) {
      unawaited(_deletePendingTicketFromDatabase(ticketId));
    }
    unawaited(_saveAllCartsToDatabase());
  }

  /// Gestor unificado: agregar, seleccionar, renombrar y eliminar en un solo diálogo centrado
  Future<void> _showTicketSelector() async {
    final nameController = TextEditingController(text: _nextUniqueSaleLabel());
    final editController = TextEditingController();
    final ticketListController = ScrollController();
    int? editingIndex;

    Future<void> addTicketAndClose(BuildContext dialogContext) async {
      final raw = nameController.text.trim();
      final ticketName = raw.isEmpty
          ? _nextUniqueSaleLabel()
          : _ensureUniqueLabel(raw);

      if (!mounted) return;
      setState(() {
        final cart = _Cart(name: ticketName);
        _applySalesDefaultsToCart(cart);
        _carts.add(cart);
        _currentCartIndex = _carts.length - 1;
        _rebuildQtyIndexForCurrentCart();
      });
      _handleCurrentCartChanged();

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
      final uniqueName = _ensureUniqueLabel(newName, excludeIndex: index);
      setState(() => _carts[index].name = uniqueName);
      if (_carts[index].ticketId != null) {
        await TicketsRepository().updateTicketName(
          _carts[index].ticketId!,
          uniqueName,
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
      _handleCurrentCartChanged();
      await _ensureDefaultCustomerSelected();
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

enum _QuoteFlowDialogAction { viewPdf, goToQuotation, backToSales }

enum _SalesDocumentType { consumidorFinal, creditoFiscal }

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
  int? fiscalReceiptTypeId;
  _SalesDocumentType documentType = _SalesDocumentType.consumidorFinal;
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
    documentType = _SalesDocumentType.consumidorFinal;
    electronicInvoiceEnabled = false;
    fiscalReceiptTypeId = null;
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

/// Widget para cada item del sidebar de categorías con hover elegante.
class _CategorySidebarItem extends StatefulWidget {
  final bool isSelected;
  final double categoryItemHeight;
  final bool isExpanded;
  final bool useCompactChrome;
  final double avatarLaneWidth;
  final VoidCallback onTap;
  final Widget avatar;
  final String name;

  const _CategorySidebarItem({
    required this.isSelected,
    required this.categoryItemHeight,
    required this.isExpanded,
    required this.useCompactChrome,
    required this.avatarLaneWidth,
    required this.onTap,
    required this.avatar,
    required this.name,
  });

  @override
  State<_CategorySidebarItem> createState() => _CategorySidebarItemState();
}

class _CategorySidebarItemState extends State<_CategorySidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final isHovered = _isHovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        width: double.infinity,
        height: widget.categoryItemHeight,
        decoration: BoxDecoration(
          color: isHovered
              ? const Color(0xFFEFF6FF)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected
                  ? const Color(0xFF1A56DB)
                  : (isHovered
                      ? const Color(0xFF1A56DB).withOpacity(0.3)
                      : Colors.transparent),
              width: isSelected ? 3 : 1.5,
            ),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.zero,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            child: SizedBox(
              width: double.infinity,
              height: widget.categoryItemHeight,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showExpandedLayout =
                      widget.isExpanded && constraints.maxWidth >= 140;
                  if (!showExpandedLayout) {
                    return Center(
                      child: widget.avatar,
                    );
                  }

                  return Padding(
                    padding: EdgeInsets.only(
                      right: widget.useCompactChrome ? 10 : 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: widget.avatarLaneWidth,
                          child: Center(
                            child: widget.avatar,
                          ),
                        ),
                        SizedBox(width: widget.useCompactChrome ? 8 : 12),
                        Expanded(
                          child: Text(
                            widget.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(
                              color: const Color(0xFF172033),
                              fontSize: widget.useCompactChrome ? 13 : 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget que envuelve un nuevo item del carrito y le aplica un efecto
/// de "barrido de brillo" (shine sweep) que recorre de izquierda a derecha,
/// combinado con un sutil fondo de color que aparece y desaparece.
class _AnimatedNewItemHighlight extends StatefulWidget {
  const _AnimatedNewItemHighlight({required this.child});

  final Widget child;

  @override
  State<_AnimatedNewItemHighlight> createState() =>
      _AnimatedNewItemHighlightState();
}

class _AnimatedNewItemHighlightState extends State<_AnimatedNewItemHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _shineAnimation;
  late final Animation<double> _bgFadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // Animación del brillo: arranca rápido, termina suave
    _shineAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Cubic(0.0, 0.0, 0.2, 1.0),
    );

    // Animación del fondo: aparece rápido y se desvanece lentamente
    _bgFadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            // Fondo azul muy suave que se desvanece
            color: Color.alphaBlend(
              const Color(
                0xFF1A56DB,
              ).withOpacity(_bgFadeAnimation.value * 0.08),
              Colors.white,
            ),
            // Borde izquierdo con color que se desvanece
            border: Border(
              left: BorderSide(
                color: const Color(
                  0xFF1A56DB,
                ).withOpacity(_bgFadeAnimation.value * 0.5),
                width: 3,
              ),
            ),
          ),
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              // Efecto de brillo (shine sweep)
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRect(
                    child: CustomPaint(
                      painter: _ShineSweepPainter(
                        progress: _shineAnimation.value,
                        color: Colors.white.withOpacity(0.35),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Painter que dibuja un barrido de brillo diagonal que cruza de izquierda
/// a derecha, simulando un "shine" o "reflejo" que recorre el elemento.
class _ShineSweepPainter extends CustomPainter {
  _ShineSweepPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;

    final bandWidth = size.width * 0.35;
    final centerX = (size.width + bandWidth) * progress - (bandWidth * 0.5);
    final rect = Rect.fromLTWH(
      centerX - bandWidth * 0.5,
      0,
      bandWidth,
      size.height,
    );

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.transparent, color, Colors.transparent],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(rect, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShineSweepPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// Widget animado que envuelve el diálogo de efectivo con escala y fade.
class _AnimatedCashDialog extends StatefulWidget {
  final double size;
  final Widget child;

  const _AnimatedCashDialog({required this.size, required this.child});

  @override
  State<_AnimatedCashDialog> createState() => _AnimatedCashDialogState();
}

class _AnimatedCashDialogState extends State<_AnimatedCashDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 12,
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Formulario compacto para registrar ingreso/salida de efectivo dentro del diálogo cuadrado centrado.
class _CompactCashMovementForm extends ConsumerStatefulWidget {
  final String type;
  final int sessionId;
  final bool isIncome;
  final VoidCallback onDone;

  const _CompactCashMovementForm({
    required this.type,
    required this.sessionId,
    required this.isIncome,
    required this.onDone,
  });

  @override
  ConsumerState<_CompactCashMovementForm> createState() =>
      _CompactCashMovementFormState();
}

class _CompactCashMovementFormState
    extends ConsumerState<_CompactCashMovementForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _isLoading = false;

  bool get isIncome => widget.isIncome;

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _saveMovement() async {
    if (!_formKey.currentState!.validate()) return;

    final authorized = await requireAuthorizationIfNeeded(
      context: context,
      action: AppActions.cashMovement,
      resourceType: 'cash_session',
      resourceId: widget.sessionId.toString(),
      reason: isIncome ? 'Entrada de efectivo' : 'Salida de efectivo',
    );
    if (!mounted) return;
    if (!authorized) return;

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final amount = AccountingAmountFormatter.parse(_amountController.text);
      final reason = _reasonController.text.trim();
      final userId = await SessionManager.userId() ?? 1;

      if (!isIncome) {
        final summary = await CashRepository.buildSummary(
          sessionId: widget.sessionId,
        );
        final available = summary.expectedCash;

        if (amount > available + 0.009) {
          if (!mounted) return;
          setState(() => _isLoading = false);

          final decision = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Caja sin efectivo suficiente'),
              content: Text(
                'Disponible en caja: RD\$${available.toStringAsFixed(2)}\n'
                'Intentas retirar: RD\$${amount.toStringAsFixed(2)}\n\n'
                'Ingresa efectivo antes de registrar este retiro.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'add'),
                  child: const Text('Agregar efectivo'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'cancel'),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          );

          if (!mounted) return;
          if (decision == 'add') {
            await CashMovementDialog.show(
              context,
              type: CashMovementType.income,
              sessionId: widget.sessionId,
            );
          }

          return;
        }
      }

      await ref
          .read(activeSessionControllerProvider.notifier)
          .addMovement(
            sessionId: widget.sessionId,
            type: widget.type,
            amount: amount,
            movementType: isIncome
                ? CashMovementAccountingType.transfer
                : CashMovementAccountingType.expense,
            affectsProfit: !isIncome,
            reason: reason.isEmpty
                ? (isIncome ? 'Entrada de efectivo' : 'Salida de efectivo')
                : reason,
            userId: userId,
          );

      if (mounted) {
        widget.onDone();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isIncome
                  ? 'Entrada de RD\$${amount.toStringAsFixed(2)} registrada'
                  : 'Salida de RD\$${amount.toStringAsFixed(2)} registrada',
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _saveMovement,
          module: 'cash/movement',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primaryColor = isIncome ? scheme.primary : scheme.error;
    final onPrimaryColor = isIncome ? scheme.onPrimary : scheme.onError;
    final title = isIncome ? 'Registrar Ingreso' : 'Registrar Salida';
    final icon = isIncome
        ? Icons.add_circle_outline_rounded
        : Icons.remove_circle_outline_rounded;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: primaryColor, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close_rounded,
                    color: scheme.onSurface.withOpacity(0.6),
                  ),
                  splashRadius: 20,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Monto
            Text(
              'Monto',
              style: TextStyle(
                color: scheme.onSurface.withOpacity(0.7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [AccountingAmountFormatter(allowEmpty: false)],
              autofocus: true,
              style: TextStyle(
                color: primaryColor,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                prefixText: r'$ ',
                prefixStyle: TextStyle(
                  color: primaryColor,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
                hintText: '0.00',
                hintStyle: TextStyle(
                  color: scheme.onSurface.withOpacity(0.25),
                  fontSize: 26,
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: primaryColor, width: 1.25),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Ingrese el monto';
                }
                final amount = AccountingAmountFormatter.parse(value);
                if (amount <= 0) {
                  return 'Monto debe ser mayor a 0';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Motivo
            Text(
              'Motivo',
              style: TextStyle(
                color: scheme.onSurface.withOpacity(0.7),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: TextFormField(
                controller: _reasonController,
                maxLines: 3,
                style: TextStyle(color: scheme.onSurface, fontSize: 14),
                decoration: InputDecoration(
                  hintText: isIncome
                      ? 'Ej: Cambio adicional, ajuste...'
                      : 'Ej: Pago de proveedor, gastos...',
                  hintStyle: TextStyle(
                    color: scheme.onSurface.withOpacity(0.4),
                    fontSize: 13,
                  ),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Ingrese el motivo';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 16),

            // Botones
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.onSurface.withOpacity(0.8),
                      side: BorderSide(
                        color: scheme.outlineVariant.withOpacity(0.65),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveMovement,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: onPrimaryColor,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    icon: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                onPrimaryColor,
                              ),
                            ),
                          )
                        : Icon(icon, size: 20),
                    label: Text(
                      isIncome ? 'Registrar Ingreso' : 'Registrar Salida',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
