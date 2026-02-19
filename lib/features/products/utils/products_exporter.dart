import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../models/category_model.dart';
import '../models/product_model.dart';
import '../models/supplier_model.dart';

class ProductsExporter {
  ProductsExporter._();

  static Future<File> exportProductsToExcel({
    required List<ProductModel> products,
    List<CategoryModel> categories = const <CategoryModel>[],
    List<SupplierModel> suppliers = const <SupplierModel>[],
    bool includePurchasePrice = true,
  }) async {
    final excel = Excel.createExcel();
    try {
      excel.delete('Sheet1');
    } catch (_) {}

    final categoriesById = <int, CategoryModel>{
      for (final c in categories)
        if (c.id != null) c.id!: c,
    };
    final suppliersById = <int, SupplierModel>{
      for (final s in suppliers)
        if (s.id != null) s.id!: s,
    };

    final sheet = excel['Productos'];

    sheet.appendRow([
      TextCellValue('Codigo'),
      TextCellValue('Nombre'),
      TextCellValue('Categoria'),
      TextCellValue('Suplidor'),
      if (includePurchasePrice) TextCellValue('Precio Compra'),
      TextCellValue('Precio Venta'),
      TextCellValue('Stock'),
      TextCellValue('Reservado'),
      TextCellValue('Stock Min'),
      TextCellValue('Activo'),
      TextCellValue('Imagen'),
      TextCellValue('Imagen URL'),
      TextCellValue('Placeholder Tipo'),
      TextCellValue('Placeholder Color'),
    ]);

    for (final p in products) {
      final categoryId = p.categoryId;
      final supplierId = p.supplierId;
      final categoryName = categoryId != null
          ? (categoriesById[categoryId]?.name ?? '')
          : '';
      final supplierName = supplierId != null
          ? (suppliersById[supplierId]?.name ?? '')
          : '';

      sheet.appendRow([
        TextCellValue(p.code),
        TextCellValue(p.name),
        TextCellValue(categoryName),
        TextCellValue(supplierName),
        if (includePurchasePrice) DoubleCellValue(p.purchasePrice),
        DoubleCellValue(p.salePrice),
        DoubleCellValue(p.stock),
        DoubleCellValue(p.reservedStock),
        DoubleCellValue(p.stockMin),
        TextCellValue(p.isActive ? 'Si' : 'No'),
        TextCellValue(p.imagePath ?? ''),
        TextCellValue(p.imageUrl ?? ''),
        TextCellValue(p.placeholderType),
        TextCellValue(p.placeholderColorHex ?? ''),
      ]);
    }

    final catsSheet = excel['Categorías'];
    catsSheet.appendRow([TextCellValue('Nombre'), TextCellValue('Activo')]);
    for (final c in categories) {
      catsSheet.appendRow([
        TextCellValue(c.name),
        TextCellValue(c.isActive ? 'Si' : 'No'),
      ]);
    }

    final suppliersSheet = excel['Suplidores'];
    suppliersSheet.appendRow([
      TextCellValue('Nombre'),
      TextCellValue('Telefono'),
      TextCellValue('Nota'),
      TextCellValue('Activo'),
    ]);
    for (final s in suppliers) {
      suppliersSheet.appendRow([
        TextCellValue(s.name),
        TextCellValue(s.phone ?? ''),
        TextCellValue(s.note ?? ''),
        TextCellValue(s.isActive ? 'Si' : 'No'),
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
