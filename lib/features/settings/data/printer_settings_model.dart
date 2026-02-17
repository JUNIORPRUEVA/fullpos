/// Tamaños de fuente disponibles para el ticket
enum TicketFontSize { small, normal, large }

/// Fuentes disponibles para el ticket
enum TicketFontFamily { courier, arial, arialBlack, roboto, sansSerif }

class PrinterSettingsModel {
  final int? id;
  final String? selectedPrinterName;
  final int paperWidthMm;
  final int charsPerLine;
  final int autoPrintOnPayment;
  final int autoOpenDrawerOnChargeWithoutTicket;
  final int copies; // 0, 1 o 2 copias
  final int showItbis;
  final int showNcf;
  final int showCashier;
  final int showClient;
  final int showPaymentMethod;
  final int showDiscounts;
  final int showCode;
  final int showDatetime;
  final String headerBusinessName;
  final String? headerRnc;
  final String? headerAddress;
  final String? headerPhone;
  final String? headerExtra; // Texto adicional encabezado
  final String footerMessage;

  /// Texto multi-línea para política de garantía/cambio.
  /// Si está vacío, no se imprime la sección.
  final String warrantyPolicy;
  final int leftMargin;
  final int rightMargin;
  final int autoCut;
  final double itbisRate; // Tasa ITBIS (default 0.18)
  final int createdAtMs;
  final int updatedAtMs;

  // === NUEVOS CAMPOS DE ESTILO ===
  final String
  fontFamily; // 'courier', 'arial', 'arialBlack', 'roboto', 'sansSerif'
  final String fontSize; // 'small', 'normal', 'large'
  final int showLogo; // 1=mostrar, 0=ocultar
  final int logoSize; // Tamaño del logo en px (40-120)
  final int showBusinessData; // 1=mostrar datos de empresa
  final int showSubtotalItbisTotal; // 1=mostrar bloque de totales
  final int autoHeight; // 1=altura automática, 0=fija
  final int topMargin; // Margen superior en px
  final int bottomMargin; // Margen inferior en px

  // === NIVELES DE ESPACIADO CONFIGURABLES (1-10) ===
  final int fontSizeLevel; // Nivel de tamaño de fuente (1=pequeño, 10=grande)
  final int
  lineSpacingLevel; // Nivel de espaciado entre líneas (1=compacto, 10=amplio)
  final int
  sectionSpacingLevel; // Nivel de espaciado entre secciones (1=junto, 10=separado)

  /// Estilo de separadores decorativos por sección: 'single' | 'double'
  /// - single: una línea (recomendado)
  /// - double: dos líneas (arriba y abajo del encabezado de sección)
  final String sectionSeparatorStyle;

  // === ALINEACIÓN DE ELEMENTOS ===
  final String
  headerAlignment; // Alineación del encabezado: 'left' | 'center' | 'right'
  final String
  detailsAlignment; // Alineación de detalles: 'left' | 'center' | 'right'
  final String
  totalsAlignment; // Alineación de totales: 'left' | 'center' | 'right'

  PrinterSettingsModel({
    this.id,
    this.selectedPrinterName,
    this.paperWidthMm = 80,
    this.charsPerLine = 48,
    this.autoPrintOnPayment = 0,
    this.autoOpenDrawerOnChargeWithoutTicket = 0,
    this.copies = 1,
    this.showItbis = 1,
    this.showNcf = 1,
    this.showCashier = 1,
    this.showClient = 1,
    this.showPaymentMethod = 1,
    this.showDiscounts = 1,
    this.showCode = 1,
    this.showDatetime = 1,
    this.headerBusinessName = 'FULLPOS',
    this.headerRnc,
    this.headerAddress,
    this.headerPhone,
    this.headerExtra,
    this.footerMessage = 'Gracias por su compra',
    this.warrantyPolicy = '',
    this.leftMargin = 0,
    this.rightMargin = 0,
    this.autoCut = 1,
    this.itbisRate = 0.18,
    required this.createdAtMs,
    required this.updatedAtMs,
    // Nuevos campos con valores por defecto profesionales
    this.fontFamily = 'arialBlack',
    this.fontSize = 'normal',
    this.showLogo = 1,
    this.logoSize = 50,
    this.showBusinessData = 1,
    this.showSubtotalItbisTotal = 1,
    this.autoHeight = 1,
    this.topMargin = 8,
    this.bottomMargin = 8,
    this.fontSizeLevel = 6,
    this.lineSpacingLevel = 6,
    this.sectionSpacingLevel = 6,
    this.sectionSeparatorStyle = 'single',
    this.headerAlignment = 'center',
    this.detailsAlignment = 'left',
    this.totalsAlignment = 'right',
  });

  /// Obtiene el tamaño de fuente en double según la configuración
  double get fontSizeValue {
    switch (fontSize) {
      case 'small':
        return paperWidthMm == 58 ? 9.0 : 10.0;
      case 'large':
        return paperWidthMm == 58 ? 12.0 : 13.0;
      default: // normal
        return paperWidthMm == 58 ? 10.0 : 11.0;
    }
  }

  /// Obtiene el nombre de la familia de fuente para Flutter
  String get fontFamilyName {
    switch (fontFamily) {
      case 'arial':
        return 'Arial';
      case 'arialBlack':
        return 'Arial Black';
      case 'roboto':
        return 'Roboto';
      case 'sansSerif':
        return 'sans-serif';
      default:
        return 'Courier';
    }
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'selected_printer_name': selectedPrinterName,
    'paper_width_mm': paperWidthMm,
    'chars_per_line': charsPerLine,
    'auto_print_on_payment': autoPrintOnPayment,
    'auto_open_drawer_on_charge_without_ticket':
      autoOpenDrawerOnChargeWithoutTicket,
    'copies': copies,
    'show_itbis': showItbis,
    'show_ncf': showNcf,
    'show_cashier': showCashier,
    'show_client': showClient,
    'show_payment_method': showPaymentMethod,
    'show_discounts': showDiscounts,
    'show_code': showCode,
    'show_datetime': showDatetime,
    'header_business_name': headerBusinessName,
    'header_rnc': headerRnc,
    'header_address': headerAddress,
    'header_phone': headerPhone,
    'header_extra': headerExtra,
    'footer_message': footerMessage,
    'warranty_policy': warrantyPolicy,
    'left_margin': leftMargin,
    'right_margin': rightMargin,
    'auto_cut': autoCut,
    'itbis_rate': itbisRate,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
    // Nuevos campos
    'font_family': fontFamily,
    'font_size': fontSize,
    'show_logo': showLogo,
    'logo_size': logoSize,
    'show_business_data': showBusinessData,
    'show_subtotal_itbis_total': showSubtotalItbisTotal,
    'auto_height': autoHeight,
    'top_margin': topMargin,
    'bottom_margin': bottomMargin,
    'font_size_level': fontSizeLevel,
    'line_spacing_level': lineSpacingLevel,
    'section_spacing_level': sectionSpacingLevel,
    'section_separator_style': sectionSeparatorStyle,
    'header_alignment': headerAlignment,
    'details_alignment': detailsAlignment,
    'totals_alignment': totalsAlignment,
  };

  factory PrinterSettingsModel.fromMap(
    Map<String, dynamic> map,
  ) => PrinterSettingsModel(
    id: map['id'] as int?,
    selectedPrinterName: map['selected_printer_name'] as String?,
    paperWidthMm: map['paper_width_mm'] as int? ?? 80,
    charsPerLine: map['chars_per_line'] as int? ?? 48,
    autoPrintOnPayment: map['auto_print_on_payment'] as int? ?? 0,
    autoOpenDrawerOnChargeWithoutTicket:
      map['auto_open_drawer_on_charge_without_ticket'] as int? ?? 0,
    copies: map['copies'] as int? ?? 1,
    showItbis: map['show_itbis'] as int? ?? 1,
    showNcf: map['show_ncf'] as int? ?? 1,
    showCashier: map['show_cashier'] as int? ?? 1,
    showClient: map['show_client'] as int? ?? 1,
    showPaymentMethod: map['show_payment_method'] as int? ?? 1,
    showDiscounts: map['show_discounts'] as int? ?? 1,
    showCode: map['show_code'] as int? ?? 1,
    showDatetime: map['show_datetime'] as int? ?? 1,
    headerBusinessName: map['header_business_name'] as String? ?? 'FULLPOS',
    headerRnc: map['header_rnc'] as String?,
    headerAddress: map['header_address'] as String?,
    headerPhone: map['header_phone'] as String?,
    headerExtra: map['header_extra'] as String?,
    footerMessage: map['footer_message'] as String? ?? 'Gracias por su compra',
    warrantyPolicy: map['warranty_policy'] as String? ?? '',
    leftMargin: map['left_margin'] as int? ?? 0,
    rightMargin: map['right_margin'] as int? ?? 0,
    autoCut: map['auto_cut'] as int? ?? 1,
    itbisRate: (map['itbis_rate'] as num?)?.toDouble() ?? 0.18,
    createdAtMs: map['created_at_ms'] as int,
    updatedAtMs: map['updated_at_ms'] as int,
    // Nuevos campos
    fontFamily: map['font_family'] as String? ?? 'arialBlack',
    fontSize: map['font_size'] as String? ?? 'normal',
    showLogo: map['show_logo'] as int? ?? 1,
    logoSize: map['logo_size'] as int? ?? 50,
    showBusinessData: map['show_business_data'] as int? ?? 1,
    showSubtotalItbisTotal: map['show_subtotal_itbis_total'] as int? ?? 1,
    autoHeight: map['auto_height'] as int? ?? 1,
    topMargin: map['top_margin'] as int? ?? 8,
    bottomMargin: map['bottom_margin'] as int? ?? 8,
    fontSizeLevel: map['font_size_level'] as int? ?? 6,
    lineSpacingLevel: map['line_spacing_level'] as int? ?? 6,
    sectionSpacingLevel: map['section_spacing_level'] as int? ?? 6,
    sectionSeparatorStyle:
        map['section_separator_style'] as String? ?? 'single',
    headerAlignment: map['header_alignment'] as String? ?? 'center',
    detailsAlignment: map['details_alignment'] as String? ?? 'left',
    totalsAlignment: map['totals_alignment'] as String? ?? 'right',
  );

  PrinterSettingsModel copyWith({
    int? id,
    String? selectedPrinterName,
    int? paperWidthMm,
    int? charsPerLine,
    int? autoPrintOnPayment,
    int? autoOpenDrawerOnChargeWithoutTicket,
    int? copies,
    int? showItbis,
    int? showNcf,
    int? showCashier,
    int? showClient,
    int? showPaymentMethod,
    int? showDiscounts,
    int? showCode,
    int? showDatetime,
    String? headerBusinessName,
    String? headerRnc,
    String? headerAddress,
    String? headerPhone,
    String? headerExtra,
    String? footerMessage,
    String? warrantyPolicy,
    int? leftMargin,
    int? rightMargin,
    int? autoCut,
    double? itbisRate,
    int? createdAtMs,
    int? updatedAtMs,
    // Nuevos campos
    String? fontFamily,
    String? fontSize,
    int? showLogo,
    int? logoSize,
    int? showBusinessData,
    int? showSubtotalItbisTotal,
    int? autoHeight,
    int? topMargin,
    int? bottomMargin,
    int? fontSizeLevel,
    int? lineSpacingLevel,
    int? sectionSpacingLevel,
    String? sectionSeparatorStyle,
    String? headerAlignment,
    String? detailsAlignment,
    String? totalsAlignment,
  }) => PrinterSettingsModel(
    id: id ?? this.id,
    selectedPrinterName: selectedPrinterName ?? this.selectedPrinterName,
    paperWidthMm: paperWidthMm ?? this.paperWidthMm,
    charsPerLine: charsPerLine ?? this.charsPerLine,
    autoPrintOnPayment: autoPrintOnPayment ?? this.autoPrintOnPayment,
    autoOpenDrawerOnChargeWithoutTicket:
      autoOpenDrawerOnChargeWithoutTicket ??
      this.autoOpenDrawerOnChargeWithoutTicket,
    copies: copies ?? this.copies,
    showItbis: showItbis ?? this.showItbis,
    showNcf: showNcf ?? this.showNcf,
    showCashier: showCashier ?? this.showCashier,
    showClient: showClient ?? this.showClient,
    showPaymentMethod: showPaymentMethod ?? this.showPaymentMethod,
    showDiscounts: showDiscounts ?? this.showDiscounts,
    showCode: showCode ?? this.showCode,
    showDatetime: showDatetime ?? this.showDatetime,
    headerBusinessName: headerBusinessName ?? this.headerBusinessName,
    headerRnc: headerRnc ?? this.headerRnc,
    headerAddress: headerAddress ?? this.headerAddress,
    headerPhone: headerPhone ?? this.headerPhone,
    headerExtra: headerExtra ?? this.headerExtra,
    footerMessage: footerMessage ?? this.footerMessage,
    warrantyPolicy: warrantyPolicy ?? this.warrantyPolicy,
    leftMargin: leftMargin ?? this.leftMargin,
    rightMargin: rightMargin ?? this.rightMargin,
    autoCut: autoCut ?? this.autoCut,
    itbisRate: itbisRate ?? this.itbisRate,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    // Nuevos campos
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    showLogo: showLogo ?? this.showLogo,
    logoSize: logoSize ?? this.logoSize,
    showBusinessData: showBusinessData ?? this.showBusinessData,
    showSubtotalItbisTotal:
        showSubtotalItbisTotal ?? this.showSubtotalItbisTotal,
    autoHeight: autoHeight ?? this.autoHeight,
    topMargin: topMargin ?? this.topMargin,
    bottomMargin: bottomMargin ?? this.bottomMargin,
    fontSizeLevel: fontSizeLevel ?? this.fontSizeLevel,
    lineSpacingLevel: lineSpacingLevel ?? this.lineSpacingLevel,
    sectionSpacingLevel: sectionSpacingLevel ?? this.sectionSpacingLevel,
    sectionSeparatorStyle: sectionSeparatorStyle ?? this.sectionSeparatorStyle,
    headerAlignment: headerAlignment ?? this.headerAlignment,
    detailsAlignment: detailsAlignment ?? this.detailsAlignment,
    totalsAlignment: totalsAlignment ?? this.totalsAlignment,
  );

  /// Obtiene configuración por defecto con plantilla profesional
  factory PrinterSettingsModel.defaults() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return PrinterSettingsModel(
      paperWidthMm: 80,
      charsPerLine: 48,
      autoPrintOnPayment: 0,
      autoOpenDrawerOnChargeWithoutTicket: 0,
      copies: 1,
      showItbis: 1,
      showNcf: 1,
      showCashier: 1,
      showClient: 1,
      showPaymentMethod: 1,
      showDiscounts: 1,
      showCode: 1,
      showDatetime: 1,
      headerBusinessName: 'FULLPOS',
      footerMessage: 'Gracias por su compra',
      warrantyPolicy: '',
      leftMargin: 0,
      rightMargin: 0,
      autoCut: 1,
      itbisRate: 0.18,
      createdAtMs: now,
      updatedAtMs: now,
      // Plantilla profesional por defecto
      fontFamily: 'arialBlack',
      fontSize: 'normal',
      showLogo: 1,
      logoSize: 50,
      showBusinessData: 1,
      showSubtotalItbisTotal: 1,
      autoHeight: 1,
      topMargin: 8,
      bottomMargin: 8,
      fontSizeLevel: 6,
      lineSpacingLevel: 6,
      sectionSpacingLevel: 6,
      headerAlignment: 'center',
      detailsAlignment: 'left',
      totalsAlignment: 'right',
    );
  }

  /// Plantilla profesional ejecutiva preconfigurada
  factory PrinterSettingsModel.professionalTemplate() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return PrinterSettingsModel(
      paperWidthMm: 80,
      charsPerLine: 48,
      autoPrintOnPayment: 1,
      autoOpenDrawerOnChargeWithoutTicket: 0,
      copies: 1,
      showItbis: 1,
      showNcf: 1,
      showCashier: 1,
      showClient: 1,
      showPaymentMethod: 1,
      showDiscounts: 1,
      showCode: 1,
      showDatetime: 1,
      headerBusinessName: 'FULLPOS',
      footerMessage: '¡Gracias por su preferencia!',
      warrantyPolicy: '',
      leftMargin: 0,
      rightMargin: 0,
      autoCut: 1,
      itbisRate: 0.18,
      createdAtMs: now,
      updatedAtMs: now,
      // Estilo profesional
      fontFamily: 'arialBlack',
      fontSize: 'normal',
      showLogo: 1,
      logoSize: 50,
      showBusinessData: 1,
      showSubtotalItbisTotal: 1,
      autoHeight: 1,
      topMargin: 10,
      bottomMargin: 10,
      fontSizeLevel: 6,
      lineSpacingLevel: 6,
      sectionSpacingLevel: 6,
      headerAlignment: 'center',
      detailsAlignment: 'left',
      totalsAlignment: 'right',
    );
  }
}
