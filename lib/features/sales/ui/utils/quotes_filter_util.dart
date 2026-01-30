import 'dart:async';
import '../../data/quote_model.dart';
import '../widgets/quotes_filter_bar.dart';

/// Utilidad para filtrar y buscar cotizaciones
class QuotesFilterUtil {
  /// Filtra y busca en la lista de cotizaciones
  static List<QuoteDetailDto> applyFilters(
    List<QuoteDetailDto> quotes,
    QuotesFilterConfig config,
  ) {
    var filtered = quotes;

    // Filtro 1: Búsqueda por texto
    if (config.searchText.isNotEmpty) {
      final searchLower = _removeAccents(config.searchText).toLowerCase();
      filtered = filtered.where((quote) {
        final clientNameMatch =
            _removeAccents(quote.clientName).toLowerCase().contains(searchLower);
        final clientPhoneMatch =
            (quote.clientPhone ?? '').toLowerCase().contains(searchLower);
        final codeMatch = 'COT-${quote.quote.id.toString().padLeft(5, '0')}'
            .toLowerCase()
            .contains(searchLower);
        final totalMatch = quote.quote.total.toString().contains(searchLower);

        return clientNameMatch ||
            clientPhoneMatch ||
            codeMatch ||
            totalMatch;
      }).toList();
    }

    // Filtro 2: Por estado
    if (config.selectedStatus != null) {
      filtered = filtered
          .where((q) => q.quote.status == config.selectedStatus)
          .toList();
    }

    // Filtro 3: Por fecha exacta
    if (config.selectedDate != null) {
      final selectedDate = config.selectedDate!;
      filtered = filtered.where((quote) {
        final quoteDate = DateTime.fromMillisecondsSinceEpoch(quote.quote.createdAtMs);
        return quoteDate.year == selectedDate.year &&
            quoteDate.month == selectedDate.month &&
            quoteDate.day == selectedDate.day;
      }).toList();
    }

    // Filtro 4: Por rango de fechas
    if (config.dateRange != null) {
      filtered = filtered.where((quote) {
        final quoteDate = DateTime.fromMillisecondsSinceEpoch(quote.quote.createdAtMs);
        return quoteDate.isAfter(config.dateRange!.start) &&
            quoteDate.isBefore(config.dateRange!.end.add(const Duration(days: 1)));
      }).toList();
    }

    // Filtro 5: Ordenamiento
    switch (config.sortBy) {
      case 'newest':
        filtered.sort((a, b) => b.quote.createdAtMs.compareTo(a.quote.createdAtMs));
        break;
      case 'oldest':
        filtered.sort((a, b) => a.quote.createdAtMs.compareTo(b.quote.createdAtMs));
        break;
      case 'highest':
        filtered.sort((a, b) => b.quote.total.compareTo(a.quote.total));
        break;
      case 'lowest':
        filtered.sort((a, b) => a.quote.total.compareTo(b.quote.total));
        break;
      default:
        filtered.sort((a, b) => b.quote.createdAtMs.compareTo(a.quote.createdAtMs));
    }

    return filtered;
  }

  /// Remueve acentos de un string para búsqueda insensible
  static String _removeAccents(String text) {
    const accents = {
      'á': 'a',
      'é': 'e',
      'í': 'i',
      'ó': 'o',
      'ú': 'u',
      'à': 'a',
      'è': 'e',
      'ì': 'i',
      'ò': 'o',
      'ù': 'u',
      'ä': 'a',
      'ë': 'e',
      'ï': 'i',
      'ö': 'o',
      'ü': 'u',
      'ñ': 'n',
    };

    String result = text.toLowerCase();
    accents.forEach((accent, replacement) {
      result = result.replaceAll(accent, replacement);
      result = result.replaceAll(accent.toUpperCase(), replacement);
    });

    return result;
  }
}

/// Clase para manejar debouncing de búsqueda
class SearchDebouncer {
  final Duration duration;
  Timer? _timer;
  final Function(String) onDebounce;

  SearchDebouncer({
    this.duration = const Duration(milliseconds: 300),
    required this.onDebounce,
  });

  void call(String text) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      onDebounce(text);
    });
  }

  void dispose() {
    _timer?.cancel();
  }
}
