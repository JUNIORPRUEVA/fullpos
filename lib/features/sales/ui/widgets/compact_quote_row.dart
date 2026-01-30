import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/quote_model.dart';
import '../../../../core/theme/app_status_theme.dart';
import '../../../../core/theme/color_utils.dart';

/// Tarjeta compacta y elevada para listar cotizaciones
class CompactQuoteRow extends StatelessWidget {
  final QuoteDetailDto quoteDetail;
  final VoidCallback onTap;
  final VoidCallback onSell;
  final VoidCallback onWhatsApp;
  final VoidCallback onPdf;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback? onConvertToTicket;
  final VoidCallback? onDownload;

  const CompactQuoteRow({
    super.key,
    required this.quoteDetail,
    required this.onTap,
    required this.onSell,
    required this.onWhatsApp,
    required this.onPdf,
    required this.onDuplicate,
    required this.onDelete,
    this.onConvertToTicket,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final quote = quoteDetail.quote;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusTheme = theme.extension<AppStatusTheme>() ??
        AppStatusTheme(
          success: scheme.primary,
          warning: scheme.tertiary,
          error: scheme.error,
          info: scheme.secondary,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (constraints.maxWidth / 980).clamp(0.88, 1.05);
        final createdDate = DateFormat('dd/MM/yy HH:mm').format(
          DateTime.fromMillisecondsSinceEpoch(quote.createdAtMs),
        );
        final cardBackground = scheme.surfaceContainerHighest;
        final cardForeground =
            ColorUtils.ensureReadableColor(scheme.onSurface, cardBackground);
        final idBackground = scheme.primaryContainer.withOpacity(
          ColorUtils.isLight(scheme.primaryContainer) ? 0.7 : 0.4,
        );
        final idForeground = ColorUtils.ensureReadableColor(
          scheme.onPrimaryContainer,
          idBackground,
        );
        final totalColor = ColorUtils.ensureReadableColor(
          scheme.primary,
          cardBackground,
        );

        return Material(
          color: cardBackground,
          elevation: 1.5,
          shadowColor: scheme.shadow.withOpacity(0.24),
          borderRadius: BorderRadius.circular(10 * scale),
          child: InkWell(
            borderRadius: BorderRadius.circular(10 * scale),
            onTap: onTap,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: 12 * scale,
                vertical: 8 * scale,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10 * scale),
                border: Border.all(color: scheme.outlineVariant, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8 * scale,
                          vertical: 4 * scale,
                        ),
                        decoration: BoxDecoration(
                          color: idBackground,
                          borderRadius: BorderRadius.circular(8 * scale),
                        ),
                        child: Text(
                          'COT-${quote.id!.toString().padLeft(5, '0')}',
                          style: TextStyle(
                            fontSize: 11 * scale,
                            fontWeight: FontWeight.w700,
                            color: idForeground,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      SizedBox(width: 8 * scale),
                      _buildStatusChip(context, quote.status),
                      const Spacer(),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 13 * scale,
                            color: cardForeground.withOpacity(0.6),
                          ),
                          SizedBox(width: 4 * scale),
                          Text(
                            createdDate,
                            style: TextStyle(
                              fontSize: 10 * scale,
                              color: cardForeground.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 6 * scale),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              quoteDetail.clientName,
                              style: TextStyle(
                                fontSize: 13 * scale,
                                fontWeight: FontWeight.w700,
                                color: cardForeground,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if ((quoteDetail.clientPhone ?? '')
                                .trim()
                                .isNotEmpty)
                              Text(
                                quoteDetail.clientPhone!,
                                style: TextStyle(
                                  fontSize: 11 * scale,
                                  color: cardForeground.withOpacity(0.7),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      SizedBox(width: 10 * scale),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 10 * scale,
                              color: cardForeground.withOpacity(0.6),
                            ),
                          ),
                          Text(
                            '\$${quote.total.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 15 * scale,
                              fontWeight: FontWeight.bold,
                              color: totalColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 6 * scale),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (quote.status != 'CONVERTED' &&
                            quote.status != 'CANCELLED' &&
                            quote.status != 'PASSED_TO_TICKET')
                          _buildIconButton(
                            icon: Icons.point_of_sale,
                            tooltip: 'Vender',
                            color: statusTheme.success,
                            scale: scale,
                            onPressed: onSell,
                          ),
                        if (quote.status != 'CONVERTED' &&
                            quote.status != 'CANCELLED' &&
                            quote.status != 'PASSED_TO_TICKET' &&
                            onConvertToTicket != null)
                          _buildIconButton(
                            icon: Icons.receipt_long,
                            tooltip: 'Pasar a ticket',
                            color: statusTheme.warning,
                            scale: scale,
                            onPressed: onConvertToTicket!,
                          ),
                        _buildIconButton(
                          icon: Icons.chat,
                          tooltip: 'WhatsApp',
                          color: statusTheme.success,
                          scale: scale,
                          onPressed: onWhatsApp,
                        ),
                        _buildIconButton(
                          icon: Icons.picture_as_pdf,
                          tooltip: 'PDF',
                          color: statusTheme.error,
                          scale: scale,
                          onPressed: onPdf,
                        ),
                        if (onDownload != null)
                          _buildIconButton(
                            icon: Icons.download,
                            tooltip: 'Descargar',
                            color: scheme.tertiary,
                            scale: scale,
                            onPressed: onDownload!,
                          ),
                        if (quote.status != 'CONVERTED' &&
                            quote.status != 'CANCELLED')
                          _buildIconButton(
                            icon: Icons.copy,
                            tooltip: 'Duplicar',
                            color: scheme.secondary,
                            scale: scale,
                            onPressed: onDuplicate,
                          ),
                        _buildIconButton(
                          icon: Icons.delete_outline,
                          tooltip: 'Eliminar',
                          color: statusTheme.error,
                          scale: scale,
                          onPressed: onDelete,
                        ),
                      ],
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

  Widget _buildStatusChip(BuildContext context, String status) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusTheme = theme.extension<AppStatusTheme>() ??
        AppStatusTheme(
          success: scheme.primary,
          warning: scheme.tertiary,
          error: scheme.error,
          info: scheme.secondary,
        );
    Color color;
    String label;

    switch (status) {
      case 'OPEN':
        color = scheme.primary;
        label = 'Abierta';
        break;
      case 'SENT':
        color = statusTheme.warning;
        label = 'Enviada';
        break;
      case 'CONVERTED':
        color = statusTheme.success;
        label = 'Vendida';
        break;
      case 'CANCELLED':
        color = statusTheme.error;
        label = 'Cancelada';
        break;
      default:
        color = scheme.outline;
        label = status;
    }

    final background = color.withOpacity(0.12);
    final foreground = ColorUtils.ensureReadableColor(color, background);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onPressed,
    double scale = 1.0,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        margin: EdgeInsets.only(right: 4 * scale),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8 * scale),
        ),
        child: IconButton(
          icon: Icon(icon, size: 16 * scale, color: color),
          onPressed: onPressed,
          padding: EdgeInsets.all(6 * scale),
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
          tooltip: '',
        ),
      ),
    );
  }
}
