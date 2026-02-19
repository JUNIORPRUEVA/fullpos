import 'dart:io';

import 'package:excel/excel.dart';

import '../data/categories_repository.dart';
import '../data/products_repository.dart';
import '../data/suppliers_repository.dart';
import '../models/product_model.dart';

class ProductsImportResult {
  final int inserted;
  final int updated;
  final int skipped;
  final int categoriesUpserted;
  final int suppliersUpserted;
  final List<String> errors;

  const ProductsImportResult({
    required this.inserted,
    required this.updated,
    required this.skipped,
    required this.categoriesUpserted,
    required this.suppliersUpserted,
    required this.errors,
  });
}

class ProductsImporter {
  ProductsImporter._();

  static Future<ProductsImportResult> importProductsFromExcel({
    required File file,
    required ProductsRepository repository,
    bool requirePurchasePrice = true,
    CategoriesRepository? categoriesRepository,
    SuppliersRepository? suppliersRepository,
  }) async {
    final catsRepo = categoriesRepository ?? CategoriesRepository();
    final supsRepo = suppliersRepository ?? SuppliersRepository();

    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);

    final productsSheet = _findSheet(excel, const [
      'Productos',
      'Producto',
      'Products',
    ], fallbackToFirst: true);
    if (productsSheet == null) {
      throw StateError('No se encontro la hoja "Productos"');
    }

    // Importar categorías y suplidores si existen (hojas opcionales).
    var categoriesUpserted = 0;
    var suppliersUpserted = 0;

    final categoryNameToId = <String, int>{};
    final supplierNameToId = <String, int>{};
    final categoryOldIdToNewId = <int, int>{};
    final supplierOldIdToNewId = <int, int>{};

    final categoriesSheet = _findSheet(excel, const [
      'Categorías',
      'Categorias',
      'Categories',
    ]);
    if (categoriesSheet != null && categoriesSheet.rows.isNotEmpty) {
      final header = categoriesSheet.rows.first
          .map((cell) => _normalizeHeader(_asString(cell)))
          .toList();
      int idxOf(String name) => header.indexOf(_normalizeHeader(name));

      final idIdx = idxOf('id');
      final nameIdx = idxOf('nombre') >= 0 ? idxOf('nombre') : idxOf('name');
      final activeIdx = idxOf('activo') >= 0
          ? idxOf('activo')
          : (idxOf('is_active') >= 0 ? idxOf('is_active') : idxOf('active'));

      for (var i = 1; i < categoriesSheet.rows.length; i++) {
        final row = categoriesSheet.rows[i];
        final name = _read(row, nameIdx);
        if (_isNullLike(name)) continue;
        final isActive = activeIdx >= 0 ? _readBool(row, activeIdx) : true;
        final newId = await catsRepo.upsertFromImport(
          name: name,
          isActive: isActive,
        );
        categoriesUpserted++;
        categoryNameToId[_normalizeKey(name)] = newId;

        final oldId = _readInt(row, idIdx);
        if (oldId > 0) {
          categoryOldIdToNewId[oldId] = newId;
        }
      }
    }

    final suppliersSheet = _findSheet(excel, const [
      'Suplidores',
      'Suplidor',
      'Proveedores',
      'Suppliers',
    ]);
    if (suppliersSheet != null && suppliersSheet.rows.isNotEmpty) {
      final header = suppliersSheet.rows.first
          .map((cell) => _normalizeHeader(_asString(cell)))
          .toList();
      int idxOf(String name) => header.indexOf(_normalizeHeader(name));

      final idIdx = idxOf('id');
      final nameIdx = idxOf('nombre') >= 0 ? idxOf('nombre') : idxOf('name');
      final phoneIdx = idxOf('telefono') >= 0
          ? idxOf('telefono')
          : (idxOf('phone') >= 0 ? idxOf('phone') : idxOf('tel'));
      final noteIdx = idxOf('nota') >= 0 ? idxOf('nota') : idxOf('note');
      final activeIdx = idxOf('activo') >= 0
          ? idxOf('activo')
          : (idxOf('is_active') >= 0 ? idxOf('is_active') : idxOf('active'));

      for (var i = 1; i < suppliersSheet.rows.length; i++) {
        final row = suppliersSheet.rows[i];
        final name = _read(row, nameIdx);
        if (_isNullLike(name)) continue;
        final phone = phoneIdx >= 0 ? _read(row, phoneIdx) : '';
        final note = noteIdx >= 0 ? _read(row, noteIdx) : '';
        final isActive = activeIdx >= 0 ? _readBool(row, activeIdx) : true;

        final newId = await supsRepo.upsertFromImport(
          name: name,
          phone: phone,
          note: note,
          isActive: isActive,
        );
        suppliersUpserted++;
        supplierNameToId[_normalizeKey(name)] = newId;

        final oldId = _readInt(row, idIdx);
        if (oldId > 0) {
          supplierOldIdToNewId[oldId] = newId;
        }
      }
    }

    if (productsSheet.rows.isEmpty) {
      throw StateError('El archivo no contiene filas');
    }

    final header = productsSheet.rows.first
        .map((cell) => _normalizeHeader(_asString(cell)))
        .toList();
    int idxOf(String name) => header.indexOf(_normalizeHeader(name));

    final codeIdx = idxOf('codigo');
    final nameIdx = idxOf('nombre');
    final categoryIdIdx = idxOf('categoria id') >= 0
        ? idxOf('categoria id')
        : idxOf('category id');
    final categoryNameIdx = idxOf('categoria') >= 0
        ? idxOf('categoria')
        : (idxOf('categoría') >= 0 ? idxOf('categoría') : idxOf('category'));
    final supplierIdIdx = idxOf('suplidor id') >= 0
        ? idxOf('suplidor id')
        : (idxOf('proveedor id') >= 0
              ? idxOf('proveedor id')
              : idxOf('supplier id'));
    final supplierNameIdx = idxOf('suplidor') >= 0
        ? idxOf('suplidor')
        : (idxOf('proveedor') >= 0 ? idxOf('proveedor') : idxOf('supplier'));
    final purchaseIdx = idxOf('precio compra');
    final saleIdx = idxOf('precio venta');
    final stockIdx = idxOf('stock');
    final reservedIdx = idxOf('reservado') >= 0
        ? idxOf('reservado')
        : idxOf('reserved');
    final stockMinIdx = idxOf('stock min');
    final activeIdx = idxOf('activo');
    final imageIdx = idxOf('imagen');
    final imageUrlIdx = idxOf('imagen url') >= 0
        ? idxOf('imagen url')
        : (idxOf('image url') >= 0 ? idxOf('image url') : idxOf('imagenurl'));
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

    for (var i = 1; i < productsSheet.rows.length; i++) {
      final row = productsSheet.rows[i];
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
      final reservedStock = reservedIdx >= 0
          ? _readDouble(row, reservedIdx)
          : 0.0;
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

      if (reservedStock < 0) {
        errors.add('Fila $rowNum: reservado invalido');
        skipped++;
        continue;
      }

      final imagePath = imageIdx >= 0 ? _read(row, imageIdx) : '';
      final imageUrl = imageUrlIdx >= 0 ? _read(row, imageUrlIdx) : '';
      final rawType = placeholderTypeIdx >= 0
          ? _read(row, placeholderTypeIdx)
          : '';
      final rawColor = placeholderColorIdx >= 0
          ? _read(row, placeholderColorIdx)
          : '';
      final hasImage = imagePath.isNotEmpty || imageUrl.isNotEmpty;
      final normalizedType = rawType.toLowerCase() == 'color'
          ? 'color'
          : (hasImage ? 'image' : 'color');

      final isActive = activeIdx >= 0 ? _readBool(row, activeIdx) : true;

      int? categoryId;
      final categoryName = categoryNameIdx >= 0
          ? _read(row, categoryNameIdx)
          : '';
      if (!_isNullLike(categoryName)) {
        final key = _normalizeKey(categoryName);
        final cached = categoryNameToId[key];
        if (cached != null) {
          categoryId = cached;
        } else {
          final id = await catsRepo.upsertFromImport(
            name: categoryName,
            isActive: true,
          );
          categoriesUpserted++;
          categoryNameToId[key] = id;
          categoryId = id;
        }
      } else {
        final oldId = _readInt(row, categoryIdIdx);
        if (oldId > 0) {
          categoryId = categoryOldIdToNewId[oldId];
        }
      }

      int? supplierId;
      final supplierName = supplierNameIdx >= 0
          ? _read(row, supplierNameIdx)
          : '';
      if (!_isNullLike(supplierName)) {
        final key = _normalizeKey(supplierName);
        final cached = supplierNameToId[key];
        if (cached != null) {
          supplierId = cached;
        } else {
          final id = await supsRepo.upsertFromImport(
            name: supplierName,
            isActive: true,
          );
          suppliersUpserted++;
          supplierNameToId[key] = id;
          supplierId = id;
        }
      } else {
        final oldId = _readInt(row, supplierIdIdx);
        if (oldId > 0) {
          supplierId = supplierOldIdToNewId[oldId];
        }
      }

      final product = ProductModel(
        code: code,
        name: name,
        imagePath: imagePath.isNotEmpty ? imagePath : null,
        imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
        placeholderType: normalizedType,
        placeholderColorHex: rawColor.isNotEmpty ? rawColor : null,
        categoryId: categoryId,
        supplierId: supplierId,
        purchasePrice: purchasePrice,
        salePrice: salePrice,
        stock: stock,
        reservedStock: reservedStock,
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
        categoriesUpserted: categoriesUpserted,
        suppliersUpserted: suppliersUpserted,
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
      categoriesUpserted: categoriesUpserted,
      suppliersUpserted: suppliersUpserted,
      errors: errors,
    );
  }

  static Sheet? _findSheet(
    Excel excel,
    List<String> preferredNames, {
    bool fallbackToFirst = false,
  }) {
    for (final name in preferredNames) {
      final exact = excel.sheets[name];
      if (exact != null) return exact;

      // Fallback: match por normalización (acentos/espacios/case)
      final want = _normalizeHeader(name);
      for (final entry in excel.sheets.entries) {
        if (_normalizeHeader(entry.key) == want) return entry.value;
      }
    }
    return fallbackToFirst && excel.sheets.isNotEmpty
        ? excel.sheets.values.first
        : null;
  }

  static String _normalizeKey(String value) {
    return _normalizeHeader(value).trim();
  }

  static String _normalizeHeader(String value) {
    var s = value.toLowerCase().trim();
    s = s
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ñ', 'n');
    // Convertir puntuación/guiones/underscores en separadores
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    // Normalizar separadores
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static bool _isNullLike(String value) {
    final key = _normalizeKey(value);
    if (key.isEmpty) return true;

    const nullLikes = <String>{
      'na',
      'n a',
      'null',
      'none',
      'ninguno',
      'sin categoria',
      'sin suplidor',
      'sin proveedor',
      '0',
    };
    return nullLikes.contains(key);
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

  static int _readInt(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return 0;
    final value = row[index]?.value;
    if (value == null) return 0;
    final text = value.toString().replaceAll(',', '').trim();
    return int.tryParse(text) ?? 0;
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
