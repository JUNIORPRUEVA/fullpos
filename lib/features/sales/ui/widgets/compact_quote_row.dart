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
        ? scheme.primary.withOpacity(0.06)
        : Colors.white;

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
            border: Border.all(color: Colors.white, width: 1.4),
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
                    color: Colors.black,
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
                    color: Colors.black,
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
                    color: Colors.black.withOpacity(0.75),
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
                    color: Colors.black,
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
                  quote.status,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: Colors.black.withOpacity(0.45)),
            ],
          ),
        ),
      ),
    );
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
