import 'dart:io';

import 'package:excel/excel.dart';

import '../data/products_repository.dart';
import '../models/product_model.dart';

class ProductsImportResult {
  final int inserted;
  final int updated;
  final int skipped;
  final List<String> errors;

  const ProductsImportResult({
    required this.inserted,
    required this.updated,
    required this.skipped,
    required this.errors,
  });
}

class ProductsImporter {
  ProductsImporter._();

  static Future<ProductsImportResult> importProductsFromExcel({
    required File file,
    required ProductsRepository repository,
    bool requirePurchasePrice = true,
  }) async {
    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    final sheet =
        excel.sheets['Productos'] ??
        (excel.sheets.isNotEmpty ? excel.sheets.values.first : null);
    if (sheet == null) {
      throw StateError('No se encontro la hoja "Productos"');
    }

    if (sheet.rows.isEmpty) {
      throw StateError('El archivo no contiene filas');
    }

    final header = sheet.rows.first
        .map((cell) => _asString(cell).toLowerCase())
        .toList();
    int idxOf(String name) => header.indexOf(name.toLowerCase());

    final codeIdx = idxOf('codigo');
    final nameIdx = idxOf('nombre');
    final purchaseIdx = idxOf('precio compra');
    final saleIdx = idxOf('precio venta');
    final stockIdx = idxOf('stock');
    final stockMinIdx = idxOf('stock min');
    final activeIdx = idxOf('activo');
    final imageIdx = idxOf('imagen');
    final placeholderTypeIdx = idxOf('placeholder tipo');
    final placeholderColorIdx = idxOf('placeholder color');

    final required = <String, int>{
      'Codigo': codeIdx,
      'Nombre': nameIdx,
      'Precio Venta': saleIdx,
      'Stock': stockIdx,
      'Stock Min': stockMinIdx,
    };

    final missing = required.entries.where((e) => e.value < 0).toList();
    if (missing.isNotEmpty) {
      throw StateError(
        'Faltan columnas requeridas: ${missing.map((e) => e.key).join(', ')}',
      );
    }

    if (requirePurchasePrice && purchaseIdx < 0) {
      throw StateError('La columna "Precio Compra" es requerida para importar');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final productsByCode = <String, ProductModel>{};
    final errors = <String>[];
    var skipped = 0;

    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      final rowNum = i + 1;

      final code = _read(row, codeIdx);
      final name = _read(row, nameIdx);
      if (code.isEmpty || name.isEmpty) {
        errors.add('Fila $rowNum: codigo/nombre requerido');
        skipped++;
        continue;
      }

      final purchasePrice = purchaseIdx >= 0
          ? _readDouble(row, purchaseIdx)
          : 0.0;
      final salePrice = _readDouble(row, saleIdx);
      final stock = _readDouble(row, stockIdx);
      final stockMin = _readDouble(row, stockMinIdx);

      if (purchasePrice <= 0 && requirePurchasePrice) {
        errors.add('Fila $rowNum: precio compra invalido');
        skipped++;
        continue;
      }
      if (salePrice <= 0) {
        errors.add('Fila $rowNum: precio venta invalido');
        skipped++;
        continue;
      }
      if (stock < 0 || stockMin < 0) {
        errors.add('Fila $rowNum: stock invalido');
        skipped++;
        continue;
      }

      final imagePath = imageIdx >= 0 ? _read(row, imageIdx) : '';
      final rawType = placeholderTypeIdx >= 0
          ? _read(row, placeholderTypeIdx)
          : '';
      final rawColor = placeholderColorIdx >= 0
          ? _read(row, placeholderColorIdx)
          : '';
      final hasImage = imagePath.isNotEmpty;
      final normalizedType = rawType.toLowerCase() == 'color'
          ? 'color'
          : (hasImage ? 'image' : 'color');

      final isActive = activeIdx >= 0 ? _readBool(row, activeIdx) : true;

      final product = ProductModel(
        code: code,
        name: name,
        imagePath: imagePath.isNotEmpty ? imagePath : null,
        placeholderType: normalizedType,
        placeholderColorHex: rawColor.isNotEmpty ? rawColor : null,
        purchasePrice: purchasePrice,
        salePrice: salePrice,
        stock: stock,
        stockMin: stockMin,
        isActive: isActive,
        createdAtMs: now,
        updatedAtMs: now,
      );

      if (productsByCode.containsKey(code)) {
        errors.add('Fila $rowNum: codigo duplicado ($code), se sobrescribe');
      }
      productsByCode[code] = product;
    }

    if (productsByCode.isEmpty) {
      return ProductsImportResult(
        inserted: 0,
        updated: 0,
        skipped: skipped,
        errors: errors,
      );
    }

    final summary = await repository.importProducts(
      productsByCode.values.toList(),
    );

    return ProductsImportResult(
      inserted: summary.inserted,
      updated: summary.updated,
      skipped: skipped,
      errors: errors,
    );
  }

  static String _asString(Data? cell) {
    final value = cell?.value;
    if (value == null) return '';
    return value.toString().trim();
  }

  static String _read(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return _asString(row[index]);
  }

  static double _readDouble(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return 0.0;
    final value = row[index]?.value;
    if (value == null) return 0.0;
    final text = value.toString().replaceAll(',', '').trim();
    return double.tryParse(text) ?? 0.0;
  }

  static bool _readBool(List<Data?> row, int index) {
    final text = _read(row, index).toLowerCase();
    if (text.isEmpty) return true;
    return text == 'si' ||
        text == 's' ||
        text == '1' ||
        text == 'true' ||
        text == 'activo';
  }
}
