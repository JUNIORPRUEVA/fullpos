import '../../../features/settings/data/printer_settings_model.dart';

/// Configuración de diseño del ticket
/// Solo controla la apariencia, NO los datos del negocio
class TicketLayoutConfig {
  /// Ancho del papel en puntos (576 para 80mm típico)
  final int paperWidthDots;

  /// Máximo de caracteres por línea (42-48 para 80mm)
  final int maxCharsPerLine;

  /// Mostrar logo de la empresa
  final bool showLogo;

  /// Escala del logo (0.5 a 1.5)
  final double logoScale;

  /// Tamaño del logo en pixels
  final int logoSizePx;

  /// Usar negrita en encabezado
  final bool boldHeader;

  /// Mostrar información de la empresa (nombre, RNC, dirección, teléfono)
  final bool showCompanyInfo;

  /// Mostrar información del cliente
  final bool showClientInfo;

  /// Mostrar información del pago (método, recibido, cambio)
  final bool showPaymentInfo;

  /// Mostrar mensaje de pie de página
  final bool showFooterMessage;

  /// Mensaje personalizado de pie de página
  final String footerMessage;

  /// Texto multi-línea para política de garantía/cambios.
  /// Si está vacío, la sección no se imprime.
  final String warrantyPolicy;

  /// Tamaño de fuente
  final TicketFontSize fontSize;

  /// Familia de fuente
  final TicketFontFamily fontFamily;

  /// Mostrar fecha y hora
  final bool showDateTime;

  /// Mostrar código/número de ticket
  final bool showTicketCode;

  /// Mostrar NCF
  final bool showNcf;

  /// Mostrar ITBIS
  final bool showItbis;

  /// Mostrar cajero
  final bool showCashier;

  /// Mostrar desglose (subtotal, ITBIS, descuentos)
  final bool showTotalsBreakdown;

  /// Corte automático
  final bool autoCut;

  /// Margen izquierdo (mm)
  final int leftMarginMm;

  /// Margen derecho (mm)
  final int rightMarginMm;

  /// Margen superior (pixels)
  final int topMarginPx;

  /// Margen inferior (pixels)
  final int bottomMarginPx;

  /// Nivel de tamaño de fuente (1-10, donde 5 es normal)
  /// Afecta tanto la vista previa como la impresión térmica
  final int fontSizeLevel;

  /// Nivel de espaciado entre líneas (1-10)
  /// 1 = muy compacto, 10 = muy espaciado
  final int lineSpacingLevel;

  /// Nivel de espaciado entre secciones (1-10)
  /// Controla el espacio entre bloques del ticket (header, items, totales, etc.)
  final int sectionSpacingLevel;

  /// Estilo de separadores decorativos por sección: 'single' | 'double'
  final String sectionSeparatorStyle;

  /// Alineación del encabezado: 'left' | 'center' | 'right'
  final String headerAlignment;

  /// Alineación de detalles y cliente: 'left' | 'center' | 'right'
  final String detailsAlignment;

  /// Alineación de totales: 'left' | 'center' | 'right'
  final String totalsAlignment;

  const TicketLayoutConfig({
    this.paperWidthDots = 576,
    this.maxCharsPerLine = 42,
    this.showLogo = true,
    this.logoScale = 0.7,
    this.logoSizePx = 50,
    this.boldHeader = true,
    this.showCompanyInfo = true,
    this.showClientInfo = true,
    this.showPaymentInfo = true,
    this.showFooterMessage = true,
    this.footerMessage = '¡GRACIAS POR LA COMPRA!',
    this.warrantyPolicy = '',
    this.fontSize = TicketFontSize.normal,
    this.fontFamily = TicketFontFamily.arialBlack,
    this.showDateTime = true,
    this.showTicketCode = true,
    this.showNcf = true,
    this.showItbis = true,
    this.showCashier = true,
    this.showTotalsBreakdown = true,
    this.autoCut = true,
    this.leftMarginMm = 0,
    this.rightMarginMm = 0,
    this.topMarginPx = 8,
    this.bottomMarginPx = 8,
    this.fontSizeLevel = 6,
    this.lineSpacingLevel = 6,
    this.sectionSpacingLevel = 6,
    this.sectionSeparatorStyle = 'single',
    this.headerAlignment = 'center',
    this.detailsAlignment = 'left',
    this.totalsAlignment = 'right',
  });

  // ============================================================
  // HELPERS PARA MAPEAR NIVELES (1-10) A VALORES REALES
  // ============================================================

  /// Mapea el nivel de fuente (1-10) a un factor de escala
  /// 1 = 0.8x, 5 = 1.0x, 10 = 1.4x
  double get fontScaleFactor {
    return 0.8 + (fontSizeLevel - 1) * (0.6 / 9);
  }

  /// Mapea el nivel de espaciado entre líneas a un factor
  /// 1 = 0.4, 5 = 1.0, 10 = 1.6
  double get lineSpacingFactor {
    return 0.4 + (lineSpacingLevel - 1) * (1.2 / 9);
  }

  /// Mapea el nivel de espaciado entre secciones
  /// 1 = 0.5, 5 = 1.0, 10 = 2.0
  double get sectionSpacingFactor {
    return 0.5 + (sectionSpacingLevel - 1) * (1.5 / 9);
  }

  /// Obtiene el número de líneas vacías entre secciones según el nivel
  int get sectionEmptyLines {
    if (sectionSpacingLevel <= 3) return 0;
    if (sectionSpacingLevel <= 5) return 1;
    if (sectionSpacingLevel <= 7) return 2;
    return 3;
  }

  /// Tamaño de fuente base ajustado por nivel
  double get adjustedFontSize {
    final base = fontSizeValue;
    return base * fontScaleFactor;
  }

  /// Configuración profesional por defecto para impresora 80mm
  factory TicketLayoutConfig.professional80mm() {
    return const TicketLayoutConfig(
      paperWidthDots: 576,
      maxCharsPerLine: 42,
      showLogo: true,
      logoScale: 0.7,
      logoSizePx: 50,
      boldHeader: true,
      showCompanyInfo: true,
      showClientInfo: true,
      showPaymentInfo: true,
      showFooterMessage: true,
      footerMessage: '¡GRACIAS POR LA COMPRA!',
      warrantyPolicy: '',
      fontSize: TicketFontSize.normal,
      fontFamily: TicketFontFamily.arialBlack,
      showDateTime: true,
      showTicketCode: true,
      showNcf: true,
      showItbis: true,
      showCashier: true,
      showTotalsBreakdown: true,
      autoCut: true,
      leftMarginMm: 0,
      rightMarginMm: 0,
      topMarginPx: 8,
      bottomMarginPx: 8,
      fontSizeLevel: 6,
      lineSpacingLevel: 6,
      sectionSpacingLevel: 6,
      headerAlignment: 'center',
      detailsAlignment: 'left',
      totalsAlignment: 'right',
    );
  }

  /// Configuración compacta para tickets rápidos
  factory TicketLayoutConfig.compact() {
    return const TicketLayoutConfig(
      paperWidthDots: 576,
      maxCharsPerLine: 42,
      showLogo: false,
      logoScale: 0.5,
      logoSizePx: 40,
      boldHeader: true,
      showCompanyInfo: true,
      showClientInfo: false,
      showPaymentInfo: true,
      showFooterMessage: false,
      footerMessage: '',
      warrantyPolicy: '',
      fontSize: TicketFontSize.small,
      fontFamily: TicketFontFamily.courier,
      showDateTime: true,
      showTicketCode: true,
      showNcf: false,
      showItbis: true,
      showCashier: false,
      showTotalsBreakdown: false,
      autoCut: true,
      leftMarginMm: 0,
      rightMarginMm: 0,
      topMarginPx: 4,
      bottomMarginPx: 4,
      fontSizeLevel: 4,
      lineSpacingLevel: 3,
      sectionSpacingLevel: 3,
      headerAlignment: 'center',
      detailsAlignment: 'left',
      totalsAlignment: 'right',
    );
  }

  /// Crear desde PrinterSettingsModel existente
  factory TicketLayoutConfig.fromPrinterSettings(
    PrinterSettingsModel settings,
  ) {
    return TicketLayoutConfig(
      paperWidthDots: settings.paperWidthMm == 80 ? 576 : 384,
      maxCharsPerLine: settings.charsPerLine,
      showLogo: settings.showLogo == 1,
      logoScale: settings.logoSize / 80.0,
      logoSizePx: settings.logoSize,
      boldHeader: true,
      showCompanyInfo: settings.showBusinessData == 1,
      showClientInfo: settings.showClient == 1,
      showPaymentInfo: settings.showPaymentMethod == 1,
      showFooterMessage: settings.footerMessage.isNotEmpty,
      footerMessage: settings.footerMessage.isEmpty
          ? '¡GRACIAS POR LA COMPRA!'
          : settings.footerMessage,
      warrantyPolicy: settings.warrantyPolicy,
      fontSize: _parseFontSize(settings.fontSize),
      fontFamily: _parseFontFamily(settings.fontFamily),
      showDateTime: settings.showDatetime == 1,
      showTicketCode: settings.showCode == 1,
      showNcf: settings.showNcf == 1,
      showItbis: settings.showItbis == 1,
      showCashier: settings.showCashier == 1,
      showTotalsBreakdown: settings.showSubtotalItbisTotal == 1,
      autoCut: settings.autoCut == 1,
      leftMarginMm: settings.leftMargin,
      rightMarginMm: settings.rightMargin,
      topMarginPx: settings.topMargin,
      bottomMarginPx: settings.bottomMargin,
      fontSizeLevel: settings.fontSizeLevel,
      lineSpacingLevel: settings.lineSpacingLevel,
      sectionSpacingLevel: settings.sectionSpacingLevel,
      sectionSeparatorStyle: settings.sectionSeparatorStyle,
      headerAlignment: settings.headerAlignment,
      detailsAlignment: settings.detailsAlignment,
      totalsAlignment: settings.totalsAlignment,
    );
  }

  /// Obtener ancho del papel en mm
  int get paperWidthMm => paperWidthDots == 576 ? 80 : 58;

  /// Ancho IMPRIMIBLE real aproximado en mm.
  /// Muchas impresoras “80mm” imprimen ~72mm (576 dots a 203dpi).
  /// Esto ayuda a que el PDF NO se escale en el driver y mantenga columnas perfectas.
  int get printableWidthMm => paperWidthDots == 576 ? 72 : 48;

  /// Obtener tamaño de fuente numérico
  double get fontSizeValue {
    switch (fontSize) {
      case TicketFontSize.small:
        return paperWidthMm == 58 ? 9.0 : 10.0;
      case TicketFontSize.large:
        return paperWidthMm == 58 ? 12.0 : 13.0;
      default:
        return paperWidthMm == 58 ? 10.0 : 11.0;
    }
  }

  /// Obtener nombre de fuente
  String get fontFamilyName {
    switch (fontFamily) {
      case TicketFontFamily.arial:
        return 'Arial';
      case TicketFontFamily.arialBlack:
        return 'Arial Black';
      case TicketFontFamily.roboto:
        return 'Roboto';
      case TicketFontFamily.sansSerif:
        return 'sans-serif';
      default:
        return 'Courier';
    }
  }

  static TicketFontSize _parseFontSize(String value) {
    switch (value) {
      case 'small':
        return TicketFontSize.small;
      case 'large':
        return TicketFontSize.large;
      default:
        return TicketFontSize.normal;
    }
  }

  static TicketFontFamily _parseFontFamily(String value) {
    switch (value) {
      case 'arial':
        return TicketFontFamily.arial;
      case 'arialBlack':
        return TicketFontFamily.arialBlack;
      case 'roboto':
        return TicketFontFamily.roboto;
      case 'sansSerif':
        return TicketFontFamily.sansSerif;
      default:
        return TicketFontFamily.courier;
    }
  }

  TicketLayoutConfig copyWith({
    int? paperWidthDots,
    int? maxCharsPerLine,
    bool? showLogo,
    double? logoScale,
    int? logoSizePx,
    bool? boldHeader,
    bool? showCompanyInfo,
    bool? showClientInfo,
    bool? showPaymentInfo,
    bool? showFooterMessage,
    String? footerMessage,
    TicketFontSize? fontSize,
    TicketFontFamily? fontFamily,
    bool? showDateTime,
    bool? showTicketCode,
    bool? showNcf,
    bool? showItbis,
    bool? showCashier,
    bool? showTotalsBreakdown,
    bool? autoCut,
    int? leftMarginMm,
    int? rightMarginMm,
    int? topMarginPx,
    int? bottomMarginPx,
    int? fontSizeLevel,
    int? lineSpacingLevel,
    int? sectionSpacingLevel,
    String? headerAlignment,
    String? detailsAlignment,
    String? totalsAlignment,
  }) {
    return TicketLayoutConfig(
      paperWidthDots: paperWidthDots ?? this.paperWidthDots,
      maxCharsPerLine: maxCharsPerLine ?? this.maxCharsPerLine,
      showLogo: showLogo ?? this.showLogo,
      logoScale: logoScale ?? this.logoScale,
      logoSizePx: logoSizePx ?? this.logoSizePx,
      boldHeader: boldHeader ?? this.boldHeader,
      showCompanyInfo: showCompanyInfo ?? this.showCompanyInfo,
      showClientInfo: showClientInfo ?? this.showClientInfo,
      showPaymentInfo: showPaymentInfo ?? this.showPaymentInfo,
      showFooterMessage: showFooterMessage ?? this.showFooterMessage,
      footerMessage: footerMessage ?? this.footerMessage,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      showDateTime: showDateTime ?? this.showDateTime,
      showTicketCode: showTicketCode ?? this.showTicketCode,
      showNcf: showNcf ?? this.showNcf,
      showItbis: showItbis ?? this.showItbis,
      showCashier: showCashier ?? this.showCashier,
      showTotalsBreakdown: showTotalsBreakdown ?? this.showTotalsBreakdown,
      autoCut: autoCut ?? this.autoCut,
      leftMarginMm: leftMarginMm ?? this.leftMarginMm,
      rightMarginMm: rightMarginMm ?? this.rightMarginMm,
      topMarginPx: topMarginPx ?? this.topMarginPx,
      bottomMarginPx: bottomMarginPx ?? this.bottomMarginPx,
      fontSizeLevel: fontSizeLevel ?? this.fontSizeLevel,
      lineSpacingLevel: lineSpacingLevel ?? this.lineSpacingLevel,
      sectionSpacingLevel: sectionSpacingLevel ?? this.sectionSpacingLevel,
      headerAlignment: headerAlignment ?? this.headerAlignment,
      detailsAlignment: detailsAlignment ?? this.detailsAlignment,
      totalsAlignment: totalsAlignment ?? this.totalsAlignment,
    );
  }
}
