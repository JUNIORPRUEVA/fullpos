import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/color_utils.dart';
import '../../../../core/ui/ui_scale.dart';

/// Configuración para los filtros y búsqueda
class QuotesFilterConfig {
  final String searchText;
  final String? selectedStatus;
  final DateTime? selectedDate;
  final DateTimeRange? dateRange;
  final String sortBy; // 'newest', 'oldest', 'highest', 'lowest'

  const QuotesFilterConfig({
    this.searchText = '',
    this.selectedStatus,
    this.selectedDate,
    this.dateRange,
    this.sortBy = 'newest',
  });

  QuotesFilterConfig copyWith({
    String? searchText,
    String? selectedStatus,
    DateTime? selectedDate,
    DateTimeRange? dateRange,
    String? sortBy,
  }) {
    return QuotesFilterConfig(
      searchText: searchText ?? this.searchText,
      selectedStatus: selectedStatus ?? this.selectedStatus,
      selectedDate: selectedDate ?? this.selectedDate,
      dateRange: dateRange ?? this.dateRange,
      sortBy: sortBy ?? this.sortBy,
    );
  }
}

/// Barra de filtros y búsqueda para las cotizaciones
class QuotesFilterBar extends StatefulWidget {
  final QuotesFilterConfig initialConfig;
  final Function(QuotesFilterConfig) onFilterChanged;

  const QuotesFilterBar({
    super.key,
    required this.initialConfig,
    required this.onFilterChanged,
  });

  @override
  State<QuotesFilterBar> createState() => _QuotesFilterBarState();
}

class _QuotesFilterBarState extends State<QuotesFilterBar> {
  late QuotesFilterConfig _config;
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _searchController = TextEditingController(text: _config.searchText);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _updateConfig(QuotesFilterConfig newConfig) {
    setState(() {
      _config = newConfig;
    });
    widget.onFilterChanged(_config);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _config.selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      _updateConfig(_config.copyWith(selectedDate: picked));
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _config.dateRange,
      saveText: 'Aceptar',
      cancelText: 'Cancelar',
    );
    if (picked != null) {
      _updateConfig(_config.copyWith(dateRange: picked));
    }
  }

  void _clearFilters() {
    _searchController.clear();
    _updateConfig(const QuotesFilterConfig());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = uiScale(context);
        final horizontalPadding =
            (constraints.maxWidth * 0.018).clamp(12.0, 20.0) * scale;
        final verticalPadding = 12.0 * scale;
        final gap = 8.0 * scale;
        final isNarrow = constraints.maxWidth < 980;
        final searchField = TextField(
          controller: _searchController,
          onChanged: (text) {
            _updateConfig(_config.copyWith(searchText: text));
          },
          decoration: InputDecoration(
            hintText: 'Buscar por cliente, telefono, codigo o total...',
            prefixIcon: Icon(Icons.search, color: scheme.primary),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _updateConfig(_config.copyWith(searchText: ''));
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16 * scale,
              vertical: 12 * scale,
            ),
          ),
        );

        final filters = Wrap(
          spacing: gap,
          runSpacing: gap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildFilterButton(
              icon: Icons.calendar_today,
              label: _config.selectedDate != null
                  ? DateFormat('dd/MM/yy').format(_config.selectedDate!)
                  : 'Fecha',
              onPressed: _pickDate,
              isActive: _config.selectedDate != null,
            ),
            _buildFilterButton(
              icon: Icons.date_range,
              label: _config.dateRange != null
                  ? '${DateFormat('dd/MM').format(_config.dateRange!.start)} - ${DateFormat('dd/MM').format(_config.dateRange!.end)}'
                  : 'Rango',
              onPressed: _pickDateRange,
              isActive: _config.dateRange != null,
            ),
            _buildStatusDropdown(),
            _buildSortDropdown(),
            if (_config.selectedDate != null ||
                _config.dateRange != null ||
                _config.selectedStatus != null ||
                _config.searchText.isNotEmpty)
              ElevatedButton(
                onPressed: _clearFilters,
                style: ElevatedButton.styleFrom(
                  backgroundColor: scheme.errorContainer,
                  foregroundColor: scheme.onErrorContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: 12 * scale,
                    vertical: 10 * scale,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.clear, size: 16),
                    SizedBox(width: 4),
                    Text('Limpiar', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
          ],
        );

        return Container(
          color: scheme.surfaceContainerHighest,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: isNarrow
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    SizedBox(height: gap),
                    filters,
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 3, child: searchField),
                    SizedBox(width: gap),
                    Expanded(
                      flex: 4,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: filters,
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildFilterButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required bool isActive,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final background = isActive ? scheme.primaryContainer : scheme.surface;
    final foreground = isActive
        ? ColorUtils.ensureReadableColor(scheme.onPrimaryContainer, background)
        : ColorUtils.ensureReadableColor(scheme.onSurface, background);
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        side: BorderSide(
          color: isActive ? scheme.primary : scheme.outlineVariant,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildStatusDropdown() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
        color: scheme.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButton<String?>(
        value: _config.selectedStatus,
        underline: const SizedBox(),
        icon: Icon(Icons.expand_more, size: 20, color: scheme.onSurface),
        dropdownColor: scheme.surface,
        style: TextStyle(color: scheme.onSurface),
        items: [
          const DropdownMenuItem(value: null, child: Text('Estado')),
          const DropdownMenuItem(value: 'OPEN', child: Text('Abierta')),
          const DropdownMenuItem(value: 'SENT', child: Text('Enviada')),
          const DropdownMenuItem(value: 'CONVERTED', child: Text('Vendida')),
          const DropdownMenuItem(value: 'CANCELLED', child: Text('Cancelada')),
        ],
        onChanged: (value) {
          _updateConfig(_config.copyWith(selectedStatus: value));
        },
      ),
    );
  }

  Widget _buildSortDropdown() {
    final scheme = Theme.of(context).colorScheme;
    final sortLabels = {
      'newest': 'Más reciente',
      'oldest': 'Más antigua',
      'highest': 'Mayor total',
      'lowest': 'Menor total',
    };

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
        color: scheme.surface,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButton<String>(
        value: _config.sortBy,
        underline: const SizedBox(),
        icon: Icon(Icons.expand_more, size: 20, color: scheme.onSurface),
        dropdownColor: scheme.surface,
        style: TextStyle(color: scheme.onSurface),
        items: [
          DropdownMenuItem(value: 'newest', child: Text(sortLabels['newest']!)),
          DropdownMenuItem(value: 'oldest', child: Text(sortLabels['oldest']!)),
          DropdownMenuItem(
            value: 'highest',
            child: Text(sortLabels['highest']!),
          ),
          DropdownMenuItem(value: 'lowest', child: Text(sortLabels['lowest']!)),
        ],
        onChanged: (value) {
          if (value != null) {
            _updateConfig(_config.copyWith(sortBy: value));
          }
        },
      ),
    );
  }
}
