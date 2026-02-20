import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
    // Evitamos el modo "Todos los productos" porque un catálogo muy grande
    // puede tardar demasiado o no llegar a renderizar en preview.
    return openFromSidebar(context);
  }

  /// Flujo para el acceso directo del Sidebar:
  /// Permite elegir por categoría o por selección manual.
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
        int mode = 1; // 1=category, 2=selected
        CategoryModel? category;
        final selectedIds = <int>{};

        return StatefulBuilder(
          builder: (context, setState) {
            final canGenerate = switch (mode) {
              1 => category != null,
              2 => selectedIds.isNotEmpty,
              _ => false,
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

              return const SizedBox.shrink();
            }

            return AlertDialog(
              title: const Text('Generar Catálogo (PDF)'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
      await Future<void>.delayed(Duration.zero);

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
        products: products,
        catalogTitle: title,
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
    required List<ProductModel> products,
    required String? catalogTitle,
    required String suggestedFileName,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _CatalogPdfPreviewDialog(
          products: products,
          catalogTitle: catalogTitle,
          suggestedFileName: suggestedFileName,
        );
      },
    );
  }
}

class _CatalogPdfPreviewDialog extends StatefulWidget {
  const _CatalogPdfPreviewDialog({
    required this.products,
    required this.catalogTitle,
    required this.suggestedFileName,
  });

  final List<ProductModel> products;
  final String? catalogTitle;
  final String suggestedFileName;

  @override
  State<_CatalogPdfPreviewDialog> createState() =>
      _CatalogPdfPreviewDialogState();
}

class _CatalogPdfPreviewDialogState extends State<_CatalogPdfPreviewDialog> {
  late Future<Uint8List> pdfFuture;
  bool busy = false;
  bool generating = true;
  Object? generationError;

  @override
  void initState() {
    super.initState();
    generating = true;
    generationError = null;
    pdfFuture = ProductCatalogPrinter.generateCatalogPdf(
      products: widget.products,
      title: widget.catalogTitle,
    );

    pdfFuture
        .then((_) {
          _safeSetState(() {
            generating = false;
            generationError = null;
          });
        })
        .catchError((e) {
          _safeSetState(() {
            generating = false;
            generationError = e;
          });
        });
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final locked = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;

    if (locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(fn);
      });
      return;
    }

    setState(fn);
  }

  void _startGeneration() {
    _safeSetState(() {
      generating = true;
      generationError = null;
      pdfFuture = ProductCatalogPrinter.generateCatalogPdf(
        products: widget.products,
        title: widget.catalogTitle,
      );
    });

    pdfFuture
        .then((_) {
          _safeSetState(() {
            generating = false;
            generationError = null;
          });
        })
        .catchError((e) {
          _safeSetState(() {
            generating = false;
            generationError = e;
          });
        });
  }

  Future<void> runBusy(Future<void> Function() fn) async {
    if (busy) return;
    if (!mounted) return;
    _safeSetState(() => busy = true);
    try {
      await fn();
    } finally {
      if (mounted) _safeSetState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final businessName = appConfigService.getBusinessName().trim();
    final dialogTitle = businessName.isEmpty
        ? 'Catálogo (PDF)'
        : 'Catálogo de $businessName (PDF)';
    final shareText = businessName.isEmpty
        ? 'Catálogo de Productos'
        : 'Catálogo de Productos - $businessName';

    final showSpinner = busy || generating;
    final hasError = generationError != null;
    final canAct = !showSpinner && !hasError;

    // Nota: no forzamos lista de páginas fija para evitar índices fuera de
    // rango cuando el PDF generado tenga menos páginas de las esperadas.
    // (printing rasteriza internamente y puede lanzar ArgumentError).
    final bool showLargePreviewHint = widget.products.length >= 120;

    return WillPopScope(
      onWillPop: () async => !(busy || generating),
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
                        dialogTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (showSpinner)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    OutlinedButton(
                      onPressed: canAct
                          ? () async {
                              await runBusy(() async {
                                final bytes = await pdfFuture;
                                final file =
                                    await CatalogPdfLauncher._savePdfToDownloads(
                                      bytes: bytes,
                                      fileName: widget.suggestedFileName,
                                    );
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'PDF guardado en Descargas: ${file.path}',
                                      ),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                }
                              });
                            }
                          : null,
                      child: const Text('Descargar'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: canAct
                          ? () async {
                              File? file;
                              await runBusy(() async {
                                final bytes = await pdfFuture;
                                file = await CatalogPdfLauncher._writePdfToTemp(
                                  bytes: bytes,
                                  fileName: widget.suggestedFileName,
                                );
                              });

                              if (!mounted || file == null) return;

                              unawaited(
                                Share.shareXFiles([
                                  XFile(file!.path),
                                ], text: shareText),
                              );
                            }
                          : null,
                      child: const Text('Compartir'),
                    ),
                    const SizedBox(width: 8),
                    if (!showSpinner && hasError)
                      TextButton(
                        onPressed: _startGeneration,
                        child: const Text('Reintentar'),
                      ),
                    TextButton(
                      onPressed: (busy || generating)
                          ? null
                          : () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
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
                  data: Theme.of(context).copyWith(
                    colorScheme: Theme.of(context).colorScheme.copyWith(
                      primary: AppColors.teal700,
                      secondary: AppColors.gold,
                    ),
                  ),
                  child: Column(
                    children: [
                      if (showLargePreviewHint)
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            'El catálogo es grande y la vista previa puede tardar en renderizar.\n'
                            'Si demora, usa Descargar o Compartir para abrirlo externamente.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      Expanded(
                        child: PdfPreview(
                          build: (format) => pdfFuture,
                          maxPageWidth: 620,
                          canChangeOrientation: false,
                          canChangePageFormat: false,
                          allowPrinting: false,
                          allowSharing: false,
                          onError: (context, error) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'No se pudo mostrar la vista previa del PDF.\n'
                                  'Puedes usar Descargar o Compartir para abrirlo externamente.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
