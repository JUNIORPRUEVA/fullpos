import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/errors/error_handler.dart';
import '../../data/suppliers_repository.dart';
import '../../models/supplier_model.dart';
import '../widgets/products_surface.dart';

/// Diálogo para crear/editar suplidores
class SupplierFormDialog extends StatefulWidget {
  final SupplierModel? supplier;

  const SupplierFormDialog({super.key, this.supplier});

  @override
  State<SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();
  final SuppliersRepository _suppliersRepo = SuppliersRepository();

  bool _isLoading = false;
  bool _isEdit = false;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.supplier != null;
    if (_isEdit) {
      _nameController.text = widget.supplier!.name;
      _phoneController.text = widget.supplier!.phone ?? '';
      _noteController.text = widget.supplier!.note ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final name = _nameController.text.trim();
      final phone = _phoneController.text.trim();
      final note = _noteController.text.trim();

      // Verificar si ya existe (excluyendo el actual si es edición)
      final exists = await _suppliersRepo.existsByName(
        name,
        excludeId: _isEdit ? widget.supplier!.id : null,
      );

      if (exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ya existe un suplidor con ese nombre'),
            ),
          );
        }
        return;
      }

      if (_isEdit) {
        // Actualizar
        final updated = widget.supplier!.copyWith(
          name: name,
          phone: phone.isEmpty ? null : phone,
          note: note.isEmpty ? null : note,
        );
        await _suppliersRepo.update(updated);
      } else {
        // Crear
        final supplier = SupplierModel(
          name: name,
          phone: phone.isEmpty ? null : phone,
          note: note.isEmpty ? null : note,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        await _suppliersRepo.create(supplier);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEdit
                  ? 'Suplidor actualizado correctamente'
                  : 'Suplidor creado correctamente',
            ),
          ),
        );
      }
    } catch (e, st) {
      if (mounted) {
        await ErrorHandler.instance.handle(
          e,
          stackTrace: st,
          context: context,
          onRetry: _save,
          module: 'products/suppliers/save',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final viewport = MediaQuery.sizeOf(context);
    final dialogWidth = (viewport.width * 0.30).clamp(380.0, 500.0);

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): DismissIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => Navigator.pop(context),
          ),
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (_isLoading) return null;
              _save();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(72, 12, 12, 12),
              child: Dialog(
                backgroundColor: Colors.transparent,
                insetPadding: EdgeInsets.zero,
                child: SizedBox(
                  width: dialogWidth,
                  child: ProductsSurface(
                    padding: EdgeInsets.zero,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            border: Border(
                              bottom: BorderSide(color: scheme.outlineVariant),
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(22),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _isEdit
                                      ? 'EDITAR SUPLIDOR'
                                      : 'CREAR SUPLIDOR',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextFormField(
                                  controller: _nameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Nombre *',
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                  textCapitalization: TextCapitalization.words,
                                  autofocus: true,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'El nombre es requerido';
                                    }
                                    if (value.trim().length < 2) {
                                      return 'Mínimo 2 caracteres';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _phoneController,
                                  decoration: const InputDecoration(
                                    labelText: 'Teléfono',
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                  keyboardType: TextInputType.phone,
                                ),
                                const SizedBox(height: 10),
                                TextFormField(
                                  controller: _noteController,
                                  decoration: const InputDecoration(
                                    labelText: 'Nota',
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                  maxLines: 2,
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: _isLoading
                                          ? null
                                          : () => Navigator.pop(context),
                                      child: const Text('Cancelar'),
                                    ),
                                    const SizedBox(width: 8),
                                    FilledButton(
                                      onPressed: _isLoading ? null : _save,
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Text(_isEdit ? 'Guardar' : 'Crear'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
