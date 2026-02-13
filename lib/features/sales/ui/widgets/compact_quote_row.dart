import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/quote_model.dart';
import '../../../../core/theme/app_status_theme.dart';

/// Tarjeta compacta y elevada para listar cotizaciones
class CompactQuoteRow extends StatelessWidget {
  final QuoteDetailDto quoteDetail;
  final bool isSelected;
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
    this.isSelected = false,
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
    final statusTheme =
        theme.extension<AppStatusTheme>() ??
        AppStatusTheme(
          success: scheme.primary,
          warning: scheme.tertiary,
          error: scheme.error,
          info: scheme.secondary,
        );

    final dateLabel = DateFormat(
      'dd/MM/yy HH:mm',
    ).format(DateTime.fromMillisecondsSinceEpoch(quote.createdAtMs));
    final idLabel = quote.id == null
        ? 'COT-—'
        : 'COT-${quote.id!.toString().padLeft(5, '0')}';
    final statusColor = _statusColor(quote.status, scheme, statusTheme);

    final bgColor = isSelected
        ? scheme.primaryContainer.withOpacity(0.35)
        : scheme.surface;
    final textColor = scheme.onSurface;
    final mutedText = scheme.onSurface.withOpacity(0.70);

    final canConvert =
        quote.status != 'CONVERTED' && quote.status != 'CANCELLED';

    String statusLabel(String value) {
      switch (value) {
        case 'PASSED_TO_TICKET':
          return 'TICKET';
        default:
          return value;
      }
    }

    final statusText = statusLabel(quote.status);

    final actions = <_QuoteAction>[
      _QuoteAction.view,
      if (canConvert) _QuoteAction.sell,
      if (canConvert && onConvertToTicket != null) _QuoteAction.ticket,
      _QuoteAction.whatsapp,
      _QuoteAction.pdf,
      if (onDownload != null) _QuoteAction.download,
      _QuoteAction.duplicate,
      _QuoteAction.delete,
    ];

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  idLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 5,
                child: Text(
                  quoteDetail.clientName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(
                  dateLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: Text(
                  NumberFormat.currency(
                    locale: 'es_DO',
                    symbol: 'RD\$',
                    decimalDigits: 2,
                  ).format(quote.total),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withOpacity(0.35)),
                ),
                child: Text(
                  statusText,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<_QuoteAction>(
                tooltip: 'Acciones',
                icon: Icon(
                  Icons.more_vert,
                  size: 18,
                  color: scheme.onSurface.withOpacity(0.7),
                ),
                onSelected: (action) {
                  switch (action) {
                    case _QuoteAction.view:
                      onTap();
                      break;
                    case _QuoteAction.sell:
                      onSell();
                      break;
                    case _QuoteAction.ticket:
                      onConvertToTicket?.call();
                      break;
                    case _QuoteAction.whatsapp:
                      onWhatsApp();
                      break;
                    case _QuoteAction.pdf:
                      onPdf();
                      break;
                    case _QuoteAction.download:
                      onDownload?.call();
                      break;
                    case _QuoteAction.duplicate:
                      onDuplicate();
                      break;
                    case _QuoteAction.delete:
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  for (final a in actions)
                    PopupMenuItem<_QuoteAction>(
                      value: a,
                      child: Row(
                        children: [
                          Icon(_actionIcon(a), size: 18),
                          const SizedBox(width: 10),
                          Text(_actionLabel(a)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _actionLabel(_QuoteAction action) {
    switch (action) {
      case _QuoteAction.view:
        return 'Ver detalles';
      case _QuoteAction.sell:
        return 'Convertir a venta';
      case _QuoteAction.ticket:
        return 'Pasar a ticket';
      case _QuoteAction.whatsapp:
        return 'Enviar por WhatsApp';
      case _QuoteAction.pdf:
        return 'Ver PDF';
      case _QuoteAction.download:
        return 'Descargar PDF';
      case _QuoteAction.duplicate:
        return 'Duplicar';
      case _QuoteAction.delete:
        return 'Eliminar';
    }
  }

  static IconData _actionIcon(_QuoteAction action) {
    switch (action) {
      case _QuoteAction.view:
        return Icons.visibility_outlined;
      case _QuoteAction.sell:
        return Icons.point_of_sale;
      case _QuoteAction.ticket:
        return Icons.receipt_long;
      case _QuoteAction.whatsapp:
        return Icons.chat;
      case _QuoteAction.pdf:
        return Icons.picture_as_pdf;
      case _QuoteAction.download:
        return Icons.download;
      case _QuoteAction.duplicate:
        return Icons.copy;
      case _QuoteAction.delete:
        return Icons.delete_outline;
    }
  }

  Color _statusColor(
    String status,
    ColorScheme scheme,
    AppStatusTheme statusTheme,
  ) {
    switch (status) {
      case 'CONVERTED':
        return statusTheme.success;
      case 'CANCELLED':
        return statusTheme.error;
      case 'TICKET':
      case 'PASSED_TO_TICKET':
        return statusTheme.warning;
      case 'SENT':
        return statusTheme.info;
      default:
        return scheme.primary;
    }
  }
}

enum _QuoteAction {
  view,
  sell,
  ticket,
  whatsapp,
  pdf,
  download,
  duplicate,
  delete,
}
