import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  final Widget? summary;

  const QuotesFilterBar({
    super.key,
    required this.initialConfig,
    required this.onFilterChanged,
    this.summary,
  });

  @override
  State<QuotesFilterBar> createState() => _QuotesFilterBarState();
}

class _QuotesFilterBarState extends State<QuotesFilterBar> {
  late QuotesFilterConfig _config;
  late TextEditingController _searchController;

  static const _brandDark = Colors.black;
  static const _brandLight = Colors.white;
  static const _controlRadius = 10.0;

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
        final verticalPadding = 10.0 * scale;
        final gap = 8.0 * scale;
        final isNarrow = constraints.maxWidth < 980;
        final baseFieldBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(_controlRadius),
          borderSide: BorderSide(color: scheme.outlineVariant),
        );

        final searchField = TextField(
          controller: _searchController,
          onChanged: (text) {
            _updateConfig(_config.copyWith(searchText: text));
          },
          style: const TextStyle(color: _brandLight),
          decoration: InputDecoration(
            hintText: 'Buscar por cliente, telefono, codigo o total...',
            hintStyle: TextStyle(color: _brandLight.withOpacity(0.70)),
            filled: true,
            fillColor: _brandDark,
            prefixIcon: Icon(
              Icons.search,
              color: _brandLight.withOpacity(0.85),
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    color: _brandLight.withOpacity(0.90),
                    onPressed: () {
                      _searchController.clear();
                      _updateConfig(_config.copyWith(searchText: ''));
                    },
                  )
                : null,
            border: baseFieldBorder,
            enabledBorder: baseFieldBorder,
            focusedBorder: baseFieldBorder.copyWith(
              borderSide: BorderSide(color: scheme.primary),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16 * scale,
              vertical: 12 * scale,
            ),
          ),
        );

        final filterWidgets = <Widget>[
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
                backgroundColor: _brandDark,
                foregroundColor: _brandLight,
                side: BorderSide(color: scheme.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_controlRadius),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: 14 * scale,
                  vertical: 12 * scale,
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
        ];

        Widget filtersRow() {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < filterWidgets.length; i++) ...[
                if (i > 0) SizedBox(width: gap),
                filterWidgets[i],
              ],
            ],
          );
        }

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
                    Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: filterWidgets,
                    ),
                    if (widget.summary != null) ...[
                      SizedBox(height: gap),
                      widget.summary!,
                    ],
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
                        child: filtersRow(),
                      ),
                    ),
                    if (widget.summary != null) ...[
                      SizedBox(width: gap),
                      widget.summary!,
                    ],
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

    // Estética de marca: chips/botones oscuros con texto claro.
    final background = _brandDark;
    final foreground = _brandLight;
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        side: BorderSide(
          color: isActive ? scheme.primary : scheme.outlineVariant,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_controlRadius),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        border: Border.all(
          color: _config.selectedStatus != null
              ? scheme.primary
              : scheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(_controlRadius),
        color: _brandDark,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButton<String?>(
        value: _config.selectedStatus,
        underline: const SizedBox(),
        icon: const Icon(Icons.expand_more, size: 20, color: _brandLight),
        dropdownColor: scheme.surface,
        style: const TextStyle(color: _brandLight),
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
        border: Border.all(
          color: _config.sortBy != 'newest'
              ? scheme.primary
              : scheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(_controlRadius),
        color: _brandDark,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: DropdownButton<String>(
        value: _config.sortBy,
        underline: const SizedBox(),
        icon: const Icon(Icons.expand_more, size: 20, color: _brandLight),
        dropdownColor: scheme.surface,
        style: const TextStyle(color: _brandLight),
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
