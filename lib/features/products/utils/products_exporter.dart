import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/product_model.dart';

class ProductsExporter {
  ProductsExporter._();

  static Future<File> exportProductsToExcel({
    required List<ProductModel> products,
    bool includePurchasePrice = true,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Productos'];

    sheet.appendRow([
      TextCellValue('ID'),
      TextCellValue('Codigo'),
      TextCellValue('Nombre'),
      if (includePurchasePrice) TextCellValue('Precio Compra'),
      TextCellValue('Precio Venta'),
      TextCellValue('Stock'),
      TextCellValue('Stock Min'),
      TextCellValue('Activo'),
      TextCellValue('Imagen'),
      TextCellValue('Placeholder Tipo'),
      TextCellValue('Placeholder Color'),
    ]);

    for (final p in products) {
      sheet.appendRow([
        IntCellValue(p.id ?? 0),
        TextCellValue(p.code),
        TextCellValue(p.name),
        if (includePurchasePrice) DoubleCellValue(p.purchasePrice),
        DoubleCellValue(p.salePrice),
        DoubleCellValue(p.stock),
        DoubleCellValue(p.stockMin),
        TextCellValue(p.isActive ? 'Si' : 'No'),
        TextCellValue(p.imagePath ?? ''),
        TextCellValue(p.placeholderType),
        TextCellValue(p.placeholderColorHex ?? ''),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('No se pudo generar el archivo Excel');
    }

    final downloadsDir = await getDownloadsDirectory();
    if (downloadsDir == null) {
      throw StateError('No se pudo acceder al directorio de descargas');
    }

    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${downloadsDir.path}/Productos_$ts.xlsx');
    await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
    return file;
  }
}
