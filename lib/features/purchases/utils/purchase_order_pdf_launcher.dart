import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/printing/purchase_order_printer.dart';
import '../../../core/window/window_service.dart';
import '../../sales/data/settings_repository.dart';
import '../data/purchase_order_models.dart';

class PurchaseOrderPdfLauncher {
  PurchaseOrderPdfLauncher._();

  static Future<void> openPreviewDialog({
    required BuildContext context,
    required PurchaseOrderDetailDto detail,
  }) async {
    final business = await SettingsRepository.getBusinessInfo();
    final bytes = await PurchaseOrderPrinter.generatePdf(
      detail: detail,
      business: business,
    );

    final suggestedFileName = 'orden_compra_${detail.order.id ?? ''}.pdf';
    final shareText = 'Orden de compra #${detail.order.id ?? ''}';

    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setState) {
            var busy = false;

            Future<T> runBusy<T>(Future<T> Function() fn) async {
              if (busy) return await fn();
              busy = true;
              if (builderContext.mounted) {
                setState(() {});
              }
              try {
                return await fn();
              } finally {
                busy = false;
                if (builderContext.mounted) {
                  setState(() {});
                }
              }
            }

            return Dialog(
              child: SizedBox(
                width: 980,
                height: 720,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSizes.paddingM),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Orden de Compra (PDF)',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () {
                                    runBusy(() async {
                                      final file = await _savePdfToDownloads(
                                        bytes: bytes,
                                        fileName: suggestedFileName,
                                      );
                                      if (!dialogContext.mounted) return;
                                      ScaffoldMessenger.of(
                                        dialogContext,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'PDF guardado en Descargas: ${file.path}',
                                          ),
                                          backgroundColor: AppColors.success,
                                        ),
                                      );
                                    });
                                  },
                            child: const Text('Descargar'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: busy
                                ? null
                                : () {
                                    runBusy(() async {
                                      final file = await _writePdfToTemp(
                                        bytes: bytes,
                                        fileName: suggestedFileName,
                                      );
                                      await Share.shareXFiles([
                                        XFile(file.path),
                                      ], text: shareText);
                                    });
                                  },
                            child: const Text(
                              'Enviar por WhatsApp / Compartir',
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => Navigator.of(dialogContext).pop(),
                            child: const Text('Cerrar'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Theme(
                        data: Theme.of(dialogContext).copyWith(
                          colorScheme: Theme.of(dialogContext).colorScheme.copyWith(
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
            );
          },
        );
      },
    );
  }

  static Future<File> _writePdfToTemp({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final dir = await Directory.systemTemp.createTemp('fullpos_pdf_');
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<File> _savePdfToDownloads({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final outputFile = await WindowService.runWithSystemDialog(
      () => FilePicker.platform.saveFile(
        dialogTitle: 'Guardar PDF',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      ),
    );

    if (outputFile == null) {
      throw Exception('Guardado cancelado');
    }

    final file = File(outputFile);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
