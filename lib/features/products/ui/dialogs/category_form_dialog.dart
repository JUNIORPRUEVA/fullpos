import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/window/window_service.dart';
import '../../data/categories_repository.dart';
import '../../models/category_model.dart';
import '../widgets/products_surface.dart';

/// Diálogo para crear/editar categorías
class CategoryFormDialog extends StatefulWidget {
  final CategoryModel? category;

  const CategoryFormDialog({super.key, this.category});

  @override
  State<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final CategoriesRepository _categoriesRepo = CategoriesRepository();

  bool _isLoading = false;
  bool _isEdit = false;
  String? _imagePath;
  String? _pendingImageSourcePath;
  bool _removeImage = false;

  @override
  void initState() {
    super.initState();
    _isEdit = widget.category != null;
    if (_isEdit) {
      _nameController.text = widget.category!.name;
      _imagePath = widget.category!.imagePath;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? get _previewImagePath => _pendingImageSourcePath ?? _imagePath;

  Future<Directory> _ensureCategoryImagesDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'category_images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> _copyImageToAppDir(String sourcePath) async {
    final imagesDir = await _ensureCategoryImagesDir();
    final ext = p.extension(sourcePath);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final fileName = _isEdit && widget.category?.id != null
        ? 'category_${widget.category!.id}_$ts${ext.isEmpty ? '.png' : ext}'
        : 'category_$ts${ext.isEmpty ? '.png' : ext}';
    final destPath = p.join(imagesDir.path, fileName);
    final copied = await File(sourcePath).copy(destPath);
    return copied.path;
  }

  Future<void> _pickImage() async {
    final result = await WindowService.runWithSystemDialog(
      () => FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      ),
    );
    final path = result?.files.single.path;
    if (path == null || path.isEmpty || !mounted) return;
    setState(() {
      _pendingImageSourcePath = path;
      _removeImage = false;
    });
  }

  void _removeSelectedImage() {
    setState(() {
      _pendingImageSourcePath = null;
      _imagePath = null;
      _removeImage = true;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final name = _nameController.text.trim();

      // Verificar si ya existe (excluyendo la actual si es edición)
      final exists = await _categoriesRepo.existsByName(
        name,
        excludeId: _isEdit ? widget.category!.id : null,
      );

      if (exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ya existe una categoría con ese nombre'),
            ),
          );
        }
        return;
      }

      String? finalImagePath = widget.category?.imagePath;
      if (_removeImage) {
        finalImagePath = null;
      } else if (_pendingImageSourcePath != null) {
        finalImagePath = await _copyImageToAppDir(_pendingImageSourcePath!);
      }

      if (_isEdit) {
        // Actualizar
        final updated = widget.category!.copyWith(
          name: name,
          imagePath: finalImagePath,
        );
        await _categoriesRepo.update(updated);
      } else {
        // Crear
        final category = CategoryModel(
          name: name,
          imagePath: finalImagePath,
          createdAtMs: DateTime.now().millisecondsSinceEpoch,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        await _categoriesRepo.create(category);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEdit
                  ? 'Categoría actualizada correctamente'
                  : 'Categoría creada correctamente',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
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
    final dialogWidth = (viewport.width * 0.28).clamp(360.0, 460.0);
    final previewPath = _previewImagePath;
    final hasPreview = previewPath != null && previewPath.trim().isNotEmpty;
    final initial = _nameController.text.trim().isEmpty
        ? 'C'
        : _nameController.text.trim().substring(0, 1).toUpperCase();

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
                                      ? 'EDITAR CATEGORÍA'
                                      : 'CREAR CATEGORÍA',
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
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                                const SizedBox(height: 14),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 74,
                                      height: 74,
                                      decoration: BoxDecoration(
                                        color: scheme.primary.withOpacity(0.10),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: scheme.outlineVariant,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child:
                                          hasPreview &&
                                              File(previewPath).existsSync()
                                          ? Image.file(
                                              File(previewPath),
                                              fit: BoxFit.cover,
                                            )
                                          : Center(
                                              child: Text(
                                                initial,
                                                style: TextStyle(
                                                  color: scheme.primary,
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Imagen de categoría',
                                            style: theme.textTheme.labelLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Opcional. Si existe, se mostrará en ventas y en los selectores.',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                  height: 1.3,
                                                ),
                                          ),
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              FilledButton.tonalIcon(
                                                onPressed: _isLoading
                                                    ? null
                                                    : _pickImage,
                                                icon: const Icon(
                                                  Icons.upload_file_rounded,
                                                  size: 18,
                                                ),
                                                label: Text(
                                                  hasPreview
                                                      ? 'Cambiar imagen'
                                                      : 'Seleccionar imagen',
                                                ),
                                              ),
                                              if (hasPreview)
                                                OutlinedButton.icon(
                                                  onPressed: _isLoading
                                                      ? null
                                                      : _removeSelectedImage,
                                                  icon: const Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    size: 18,
                                                  ),
                                                  label: const Text('Quitar'),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
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
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size(132, 44),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
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
