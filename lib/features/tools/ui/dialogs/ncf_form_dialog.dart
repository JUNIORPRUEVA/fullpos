import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/ui/dialog_sizes.dart';
import '../../data/models/ncf_book_model.dart';

/// Diálogo para crear o editar un talonario de NCF
class NcfFormDialog extends StatefulWidget {
  final NcfBookModel? ncfBook; // null = crear, no-null = editar

  const NcfFormDialog({super.key, this.ncfBook});

  @override
  State<NcfFormDialog> createState() => _NcfFormDialogState();
}

class _NcfFormDialogState extends State<NcfFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _seriesCtrl;
  late TextEditingController _fromCtrl;
  late TextEditingController _toCtrl;
  late TextEditingController _noteCtrl;

  String _selectedType = NcfTypes.b02;
  bool _isActive = true;
  DateTime? _expiresAt;

  bool get _isEditing => widget.ncfBook != null;

  @override
  void initState() {
    super.initState();

    if (_isEditing) {
      final book = widget.ncfBook!;
      _selectedType = book.type;
      _seriesCtrl = TextEditingController(text: book.series ?? '');
      _fromCtrl = TextEditingController(text: book.fromN.toString());
      _toCtrl = TextEditingController(text: book.toN.toString());
      _noteCtrl = TextEditingController(text: book.note ?? '');
      _isActive = book.isActive;
      _expiresAt = book.expiresAt;
    } else {
      _seriesCtrl = TextEditingController();
      _fromCtrl = TextEditingController(text: '1');
      _toCtrl = TextEditingController();
      _noteCtrl = TextEditingController();
    }
  }

  @override
  void dispose() {
    _seriesCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final fromN = int.parse(_fromCtrl.text);
    final toN = int.parse(_toCtrl.text);
    final series = _seriesCtrl.text.trim().isEmpty
        ? null
        : _seriesCtrl.text.trim();
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

    final now = DateTime.now();

    final result = NcfBookModel(
      id: widget.ncfBook?.id,
      type: _selectedType,
      series: series,
      fromN: fromN,
      toN: toN,
      nextN: _isEditing ? widget.ncfBook!.nextN : fromN,
      isActive: _isActive,
      expiresAt: _expiresAt,
      note: note,
      createdAt: widget.ncfBook?.createdAt ?? now,
      updatedAt: now,
    );

    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    InputDecoration fieldDecoration({String? hintText}) {
      return InputDecoration(
        hintText: hintText,
        filled: true,
        fillColor: scheme.surfaceVariant.withOpacity(isDark ? 0.45 : 0.65),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withOpacity(0.35),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withOpacity(0.35),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: scheme.primary.withOpacity(0.75),
            width: 1.4,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      );
    }

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DialogSizes.dialogRadius),
      ),
      child: ConstrainedBox(
        constraints: DialogSizes.small(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: DialogSizes.dialogPadding,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(DialogSizes.dialogRadius),
                  topRight: Radius.circular(DialogSizes.dialogRadius),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.receipt_long, color: Colors.white, size: 24),
                  const SizedBox(width: AppSizes.paddingM),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Editar NCF' : 'Nuevo NCF',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: DialogSizes.scrollPadding,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Tipo de NCF
                      Text(
                        'Tipo de Comprobante',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedType,
                        decoration: fieldDecoration(),
                        items: NcfTypes.all.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(
                              '$type - ${NcfTypes.getDescription(type)}',
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedType = value);
                          }
                        },
                      ),

                      const SizedBox(height: DialogSizes.formSpacing),

                      // Serie (opcional)
                      Text(
                        'Serie (opcional)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _seriesCtrl,
                        decoration: fieldDecoration(hintText: 'Ej: A, B, C'),
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(3),
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z]'),
                          ),
                        ],
                        textCapitalization: TextCapitalization.characters,
                      ),

                      const SizedBox(height: DialogSizes.formSpacing),

                      // Rango: Desde - Hasta
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Desde',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _fromCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: fieldDecoration(hintText: '1'),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Requerido';
                                    }
                                    final n = int.tryParse(value);
                                    if (n == null || n < 1) {
                                      return 'Inválido';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSizes.paddingM),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hasta',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: _toCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: fieldDecoration(hintText: '1000'),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Requerido';
                                    }
                                    final toN = int.tryParse(value);
                                    if (toN == null || toN < 1) {
                                      return 'Inválido';
                                    }
                                    final fromN = int.tryParse(_fromCtrl.text);
                                    if (fromN != null && toN < fromN) {
                                      return 'Debe ser ≥ Desde';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: DialogSizes.formSpacing),

                      // Fecha de expiración (opcional)
                      Text(
                        'Fecha de Expiración (opcional)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _expiresAt ??
                                DateTime.now().add(const Duration(days: 365)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 3650),
                            ),
                          );
                          if (picked == null) return;
                          if (!mounted) return;
                          setState(() => _expiresAt = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceVariant.withOpacity(
                              isDark ? 0.45 : 0.65,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: scheme.outlineVariant.withOpacity(0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _expiresAt != null
                                      ? '${_expiresAt!.day}/${_expiresAt!.month}/${_expiresAt!.year}'
                                      : 'Sin fecha de expiración',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _expiresAt != null
                                        ? scheme.onSurface
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              if (_expiresAt != null)
                                IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    size: 18,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  onPressed: () =>
                                      setState(() => _expiresAt = null),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: DialogSizes.formSpacing),

                      // Nota (opcional)
                      Text(
                        'Nota (opcional)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _noteCtrl,
                        maxLines: 2,
                        decoration: fieldDecoration(
                          hintText: 'Descripción o comentario',
                        ),
                      ),

                      const SizedBox(height: DialogSizes.formSpacing),

                      // Estado activo
                      SwitchListTile(
                        value: _isActive,
                        onChanged: (value) => setState(() => _isActive = value),
                        title: Text(
                          'Activo',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                        subtitle: Text(
                          'Disponible para usarse en ventas',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        activeColor: scheme.primary,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Footer con botones
            Container(
              padding: DialogSizes.dialogPadding,
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  top: BorderSide(
                    color: scheme.outlineVariant.withOpacity(0.35),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, DialogSizes.buttonHeight),
                        side: BorderSide(
                          color: scheme.outlineVariant.withOpacity(0.55),
                        ),
                      ),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: AppSizes.paddingM),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, DialogSizes.buttonHeight),
                      ),
                      child: Text(_isEditing ? 'Guardar' : 'Crear'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
