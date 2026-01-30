import 'package:flutter/material.dart';

enum DateRangePeriod { today, week, biweekly, month, year, custom }

class DateRangeSelector extends StatelessWidget {
  final DateRangePeriod selectedPeriod;
  final DateTime? customStart;
  final DateTime? customEnd;
  final Function(DateRangePeriod) onPeriodChanged;
  final Function(DateTime, DateTime)? onCustomRangeChanged;

  const DateRangeSelector({
    super.key,
    required this.selectedPeriod,
    required this.onPeriodChanged,
    this.customStart,
    this.customEnd,
    this.onCustomRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildChip(context, 'Hoy', DateRangePeriod.today),
        _buildChip(context, 'Semana', DateRangePeriod.week),
        _buildChip(context, '15 días', DateRangePeriod.biweekly),
        _buildChip(context, 'Mes', DateRangePeriod.month),
        _buildChip(context, 'Año', DateRangePeriod.year),
        _buildChip(context, 'Personalizado', DateRangePeriod.custom),
      ],
    );
  }

  Widget _buildChip(
    BuildContext context,
    String label,
    DateRangePeriod period,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = selectedPeriod == period;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          if (period == DateRangePeriod.custom) {
            _showCustomDatePicker(context);
          } else {
            onPeriodChanged(period);
          }
        }
      },
      selectedColor: scheme.primary,
      labelStyle: TextStyle(
        color: isSelected ? scheme.onPrimary : scheme.onSurface,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Future<void> _showCustomDatePicker(BuildContext context) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: customStart != null && customEnd != null
          ? DateTimeRange(start: customStart!, end: customEnd!)
          : DateTimeRange(start: DateTime(now.year, now.month, 1), end: now),
      builder: (context, child) {
        final scheme = Theme.of(context).colorScheme;
        return Theme(
          data: Theme.of(context).copyWith(colorScheme: scheme),
          child: child!,
        );
      },
    );

    if (range != null && onCustomRangeChanged != null) {
      onCustomRangeChanged!(range.start, range.end);
      onPeriodChanged(DateRangePeriod.custom);
    }
  }
}

/// Helper para calcular el rango de fechas según el período
class DateRangeHelper {
  static DateTimeRange getRangeForPeriod(
    DateRangePeriod period, {
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Fin del día actual (23:59:59.999)
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    switch (period) {
      case DateRangePeriod.today:
        return DateTimeRange(start: today, end: endOfToday);

      case DateRangePeriod.week:
        final weekAgo = today.subtract(const Duration(days: 7));
        return DateTimeRange(start: weekAgo, end: endOfToday);

      case DateRangePeriod.biweekly:
        final biweekAgo = today.subtract(const Duration(days: 15));
        return DateTimeRange(start: biweekAgo, end: endOfToday);

      case DateRangePeriod.month:
        final monthStart = DateTime(now.year, now.month, 1);
        return DateTimeRange(start: monthStart, end: endOfToday);

      case DateRangePeriod.year:
        final yearStart = DateTime(now.year, 1, 1);
        return DateTimeRange(start: yearStart, end: endOfToday);

      case DateRangePeriod.custom:
        if (customStart != null && customEnd != null) {
          // Asegurar que el fin incluya todo el día
          final endOfCustom = DateTime(
            customEnd.year,
            customEnd.month,
            customEnd.day,
            23,
            59,
            59,
            999,
          );
          return DateTimeRange(start: customStart, end: endOfCustom);
        }
        return DateTimeRange(start: today, end: endOfToday);
    }
  }
}
