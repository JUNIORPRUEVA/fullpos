import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/loading/app_loading_provider.dart';
import '../../../core/printing/product_catalog_printer.dart';
import '../../../core/services/app_configuration_service.dart';
import '../data/categories_repository.dart';
import '../data/products_repository.dart';
import '../models/category_model.dart';
import '../models/product_model.dart';

class CatalogPdfLauncher {
  CatalogPdfLauncher._();

  static Future<void> open(BuildContext context) async {
    try {
      final products = await ProductsRepository().getAll();
      await _generateAndPreview(
        context: context,
        products: products,
        title: null,
        fileNameSuffix: null,
      );
    } catch (e, st) {
      if (!context.mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => open(context),
        module: 'products/catalog_pdf/open',
      );
    }
  }

  /// Flujo para el acceso directo del Sidebar:
  /// Permite elegir si se genera con todos los productos,
  /// por categoría, o por selección manual.
  static Future<void> openFromSidebar(BuildContext context) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final loading = container.read(appLoadingProvider.notifier);
    loading.show();

    List<ProductModel> products;
    List<CategoryModel> categories;
    try {
      final results = await Future.wait([
        ProductsRepository().getAll(),
        CategoriesRepository().getAll(),
      ]);
      products = results[0] as List<ProductModel>;
      categories = results[1] as List<CategoryModel>;
    } catch (e, st) {
      loading.hide();
      if (!context.mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => openFromSidebar(context),
        module: 'products/catalog_pdf/load',
      );
      return;
    }

    if (!context.mounted) return;
    loading.hide();

    final selection = await _showGenerationOptionsDialog(
      context: context,
      products: products,
      categories: categories,
    );
    if (selection == null) return;

    await _generateAndPreview(
      context: context,
      products: selection.products,
      title: selection.title,
      fileNameSuffix: selection.fileNameSuffix,
    );
  }

  static Future<_CatalogSelection?> _showGenerationOptionsDialog({
    required BuildContext context,
    required List<ProductModel> products,
    required List<CategoryModel> categories,
  }) async {
    return showDialog<_CatalogSelection>(
      context: context,
      builder: (dialogContext) {
        int mode = 0; // 0=all, 1=category, 2=selected
        CategoryModel? category;
        final selectedIds = <int>{};

        return StatefulBuilder(
          builder: (context, setState) {
            final canGenerate = switch (mode) {
              0 => true,
              1 => category != null,
              2 => selectedIds.isNotEmpty,
              _ => true,
            };

            Widget bodyForMode() {
              if (mode == 1) {
                return DropdownButtonFormField<CategoryModel>(
                  initialValue: category,
                  decoration: const InputDecoration(
                    labelText: 'Categoría',
                    border: OutlineInputBorder(),
                  ),
                  items: categories
                      .map(
                        (c) => DropdownMenuItem(value: c, child: Text(c.name)),
                      )
                      .toList(growable: false),
                  onChanged: (v) => setState(() => category = v),
                );
              }

              if (mode == 2) {
                return Container(
                  constraints: const BoxConstraints(maxHeight: 340),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final p = products[index];
                      final id = p.id;
                      final checked = id != null && selectedIds.contains(id);
                      return CheckboxListTile(
                        dense: true,
                        value: checked,
                        onChanged: id == null
                            ? null
                            : (v) {
                                setState(() {
                                  if (v == true) {
                                    selectedIds.add(id);
                                  } else {
                                    selectedIds.remove(id);
                                  }
                                });
                              },
                        title: Text(
                          p.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'Precio: ${appConfigService.formatCurrency(p.salePrice)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                );
              }

              return const Text(
                'Se generará un catálogo con todos los productos disponibles.',
              );
            }

            return AlertDialog(
              title: const Text('Generar Catálogo (PDF)'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<int>(
                      value: 0,
                      groupValue: mode,
                      onChanged: (v) => setState(() => mode = v ?? 0),
                      title: const Text('Todos los productos'),
                    ),
                    RadioListTile<int>(
                      value: 2,
                      groupValue: mode,
                      onChanged: (v) => setState(() => mode = v ?? 2),
                      title: const Text('Seleccionar productos'),
                    ),
                    RadioListTile<int>(
                      value: 1,
                      groupValue: mode,
                      onChanged: (v) => setState(() => mode = v ?? 1),
                      title: const Text('Una categoría específica'),
                    ),
                    const SizedBox(height: 12),
                    bodyForMode(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton.icon(
                  onPressed: canGenerate
                      ? () {
                          final businessName = appConfigService
                              .getBusinessName()
                              .trim();
                          final baseTitle = businessName.isNotEmpty
                              ? 'Catálogo de $businessName'
                              : 'Catálogo de Productos';

                          if (mode == 0) {
                            Navigator.of(dialogContext).pop(
                              _CatalogSelection(
                                products: products,
                                title: baseTitle,
                                fileNameSuffix: null,
                              ),
                            );
                            return;
                          }

                          if (mode == 1 && category != null) {
                            final filtered = products
                                .where((p) => p.categoryId == category!.id)
                                .toList(growable: false);
                            Navigator.of(dialogContext).pop(
                              _CatalogSelection(
                                products: filtered,
                                title: '$baseTitle - ${category!.name}',
                                fileNameSuffix: _sanitizeFilePart(
                                  category!.name,
                                ),
                              ),
                            );
                            return;
                          }

                          if (mode == 2) {
                            final filtered = products
                                .where(
                                  (p) =>
                                      p.id != null &&
                                      selectedIds.contains(p.id),
                                )
                                .toList(growable: false);
                            Navigator.of(dialogContext).pop(
                              _CatalogSelection(
                                products: filtered,
                                title: baseTitle,
                                fileNameSuffix: 'Seleccion',
                              ),
                            );
                            return;
                          }
                        }
                      : null,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Generar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<void> _generateAndPreview({
    required BuildContext context,
    required List<ProductModel> products,
    required String? title,
    required String? fileNameSuffix,
  }) async {
    try {
      final bytes = await ProductCatalogPrinter.generateCatalogPdf(
        products: products,
        title: title,
      );

      if (!context.mounted) return;

      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final safeBusiness = _sanitizeFilePart(
        appConfigService.getBusinessName(),
      );
      final suffix = (fileNameSuffix ?? '').trim();
      final safeSuffix = suffix.isEmpty ? '' : '_${_sanitizeFilePart(suffix)}';

      final fileName = safeBusiness.isEmpty
          ? 'Catalogo_Productos${safeSuffix}_$ts.pdf'
          : 'Catalogo_$safeBusiness${safeSuffix}_$ts.pdf';

      await _showPreviewDialog(
        context: context,
        bytes: bytes,
        suggestedFileName: fileName,
      );
    } catch (e, st) {
      if (!context.mounted) return;
      await ErrorHandler.instance.handle(
        e,
        stackTrace: st,
        context: context,
        onRetry: () => _generateAndPreview(
          context: context,
          products: products,
          title: title,
          fileNameSuffix: fileNameSuffix,
        ),
        module: 'products/catalog_pdf/generate',
      );
    }
  }

  static String _sanitizeFilePart(String input) {
    final s = input.trim();
    if (s.isEmpty) return '';
    final replaced = s.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return replaced
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static Future<File> _savePdfToDownloads({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final downloadsDir = await getDownloadsDirectory();
    if (downloadsDir == null) {
      throw StateError('No se pudo acceder al directorio de descargas');
    }
    final file = File('${downloadsDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<File> _writePdfToTemp({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> _showPreviewDialog({
    required BuildContext context,
    required Uint8List bytes,
    required String suggestedFileName,
  }) async {
    final businessName = appConfigService.getBusinessName().trim();
    final title = businessName.isEmpty
        ? 'Catálogo (PDF)'
        : 'Catálogo de $businessName (PDF)';
    final shareText = businessName.isEmpty
        ? 'Catálogo de Productos'
        : 'Catálogo de Productos - $businessName';

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        bool busy = false;

        return StatefulBuilder(
          builder: (stateContext, setState) {
            Future<void> runBusy(Future<void> Function() fn) async {
              if (busy) return;
              if (!stateContext.mounted) return;
              setState(() => busy = true);
              try {
                await fn();
              } finally {
                if (stateContext.mounted) {
                  setState(() => busy = false);
                }
              }
            }

            return WillPopScope(
              onWillPop: () async => !busy,
              child: Dialog(
                child: SizedBox(
                  width: 980,
                  height: 720,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (busy)
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 16),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      await runBusy(() async {
                                        final file = await _savePdfToDownloads(
                                          bytes: bytes,
                                          fileName: suggestedFileName,
                                        );
                                        if (dialogContext.mounted) {
                                          ScaffoldMessenger.of(
                                            dialogContext,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'PDF guardado en Descargas: ${file.path}',
                                              ),
                                              backgroundColor:
                                                  AppColors.success,
                                            ),
                                          );
                                        }
                                      });
                                    },
                              child: const Text('Descargar'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      File? file;
                                      await runBusy(() async {
                                        file = await _writePdfToTemp(
                                          bytes: bytes,
                                          fileName: suggestedFileName,
                                        );
                                      });

                                      if (!dialogContext.mounted ||
                                          file == null) {
                                        return;
                                      }

                                      // En Windows, la UI de compartir puede no
                                      // completar el Future al cancelar; no
                                      // bloqueamos el estado "busy".
                                      unawaited(
                                        Share.shareXFiles([
                                          XFile(file!.path),
                                        ], text: shareText),
                                      );
                                    },
                              child: const Text('Compartir'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      if (Navigator.of(
                                        dialogContext,
                                      ).canPop()) {
                                        Navigator.of(dialogContext).pop();
                                      }
                                    },
                              child: const Text('Cerrar'),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: Theme(
                          data: Theme.of(dialogContext).copyWith(
                            colorScheme: Theme.of(dialogContext).colorScheme
                                .copyWith(
                                  primary: AppColors.teal700,
                                  secondary: AppColors.gold,
                                ),
                          ),
                          child: PdfPreview(
                            build: (format) async => bytes,
                            canChangeOrientation: false,
                            canChangePageFormat: false,
                            allowPrinting: false,
                            allowSharing: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CatalogSelection {
  final List<ProductModel> products;
  final String? title;
  final String? fileNameSuffix;

  const _CatalogSelection({
    required this.products,
    required this.title,
    required this.fileNameSuffix,
  });
}
