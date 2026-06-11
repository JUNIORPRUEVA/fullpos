import 'package:flutter/material.dart';

/// DropdownButtonFormField limpio, profesional y sin sombras.
///
/// Reemplaza los DropdownButtonFormField tradicionales que tienen sombras
/// (elevation) al desplegarse. Este widget usa un menú limpio con bordes
/// redondeados y sin sombras.
class AppDropdownButtonFormField<T> extends StatelessWidget {
  const AppDropdownButtonFormField({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.decoration,
    this.isExpanded = true,
    this.isDense = true,
    this.hint,
    this.label,
    this.validator,
    this.enabled = true,
    this.autofocus = false,
    this.iconSize = 20,
  });

  final List<DropdownMenuItem<T>> items;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final InputDecoration? decoration;
  final bool isExpanded;
  final bool isDense;
  final String? hint;
  final String? label;
  final FormFieldValidator<T>? validator;
  final bool enabled;
  final bool autofocus;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: isExpanded,
      isDense: isDense,
      autofocus: autofocus,
      validator: validator,
      decoration: decoration ??
          InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: isDense,
            filled: true,
            fillColor: scheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(0.6)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.error),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
      items: items,
      onChanged: enabled ? onChanged : null,
      icon: Icon(
        Icons.keyboard_arrow_down_rounded,
        size: iconSize,
        color: scheme.onSurfaceVariant,
      ),
      borderRadius: BorderRadius.circular(14),
      // Eliminar sombra del menú desplegable
      menuMaxHeight: 320,
      selectedItemBuilder: (context) {
        return items.map((item) {
          return Container(
            alignment: Alignment.centerLeft,
            child: item.child,
          );
        }).toList();
      },
    );
  }
}

/// Versión simplificada para dropdowns de tipo String con opciones fijas.
class AppSimpleDropdown extends StatelessWidget {
  const AppSimpleDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.hint,
    this.isDense = true,
    this.enabled = true,
  });

  final String? value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?>? onChanged;
  final String? label;
  final String? hint;
  final bool isDense;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return AppDropdownButtonFormField<String>(
      value: value,
      items: items,
      onChanged: onChanged,
      label: label,
      hint: hint,
      isDense: isDense,
      enabled: enabled,
    );
  }
}
