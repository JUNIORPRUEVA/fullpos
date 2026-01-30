import 'package:sqflite/sqflite.dart';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/utils/color_utils.dart';
import '../models/product_model.dart';

/// Filtros para búsqueda de productos
class ProductFilters {
  final int? categoryId;
  final int? supplierId;
  final bool? hasLowStock;
  final bool? isOutOfStock;
  final bool? isActive;
  final DateTime? createdAfter;
  final DateTime? createdBefore;

  const ProductFilters({
    this.categoryId,
    this.supplierId,
    this.hasLowStock,
    this.isOutOfStock,
    this.isActive,
    this.createdAfter,
    this.createdBefore,
  });

  bool get hasFilters =>
      categoryId != null ||
      supplierId != null ||
      hasLowStock != null ||
      isOutOfStock != null ||
      isActive != null ||
      createdAfter != null ||
      createdBefore != null;
}

/// Repositorio para operaciones CRUD de Productos
class ProductsRepository {
  void _validateRequiredForSave(ProductModel product) {
    final code = product.code.trim();
    final name = product.name.trim();
    final imagePath = product.imagePath?.trim();
    final imageUrl = product.imageUrl?.trim();
    final placeholderType = product.placeholderType.toLowerCase();
    final placeholderColor = product.placeholderColorHex?.trim();
    final hasImage =
        (imagePath != null && imagePath.isNotEmpty) ||
        (imageUrl != null && imageUrl.isNotEmpty);
    final wantsColor = placeholderType == 'color';

    if (code.isEmpty) {
      throw ArgumentError('El codigo del producto es obligatorio');
    }
    if (name.isEmpty) {
      throw ArgumentError('El nombre del producto es obligatorio');
    }
    if (product.purchasePrice <= 0) {
      throw ArgumentError('El precio de compra debe ser mayor que 0');
    }
    if (product.salePrice <= 0) {
      throw ArgumentError('El precio de venta debe ser mayor que 0');
    }
    if (placeholderType != 'image' && placeholderType != 'color') {
      throw ArgumentError('placeholderType invalido (image|color)');
    }
    if (product.stock < 0 || product.stockMin < 0) {
      throw ArgumentError('Stock invalido');
    }
    if (!wantsColor && !hasImage) {
      throw ArgumentError('La imagen del producto es obligatoria');
    }
    if (wantsColor && (placeholderColor == null || placeholderColor.isEmpty)) {
      throw ArgumentError('Debe generar o elegir un color para el producto');
    }
  }

  ProductModel _withPlaceholderDefaults(ProductModel product) {
    final normalizedType = product.placeholderType.toLowerCase() == 'color'
        ? 'color'
        : 'image';
    final color = (product.placeholderColorHex?.trim().isNotEmpty ?? false)
        ? product.placeholderColorHex!.trim()
        : ColorUtils.generateDeterministicColorHex(
            product.name.trim(),
            categoryId: product.categoryId,
          );
    final prefersColor = normalizedType == 'color';
    final hasImage =
        (product.imagePath?.trim().isNotEmpty ?? false) ||
        (product.imageUrl?.trim().isNotEmpty ?? false);

    // Si el usuario eligio color pero dejo una imagen previa, respetamos la preferencia.
    // Si elige imagen pero no tiene una, forzamos color para evitar inconsistencias.
    final effectiveType = prefersColor
        ? 'color'
        : (hasImage ? 'image' : 'color');

    return product.copyWith(
      placeholderType: effectiveType,
      placeholderColorHex: color,
    );
  }

  Future<Directory> _ensureProductsImagesDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'product_images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<bool> _isManagedProductImagePath(String path) async {
    if (path.trim().isEmpty) return false;
    if (!p.isAbsolute(path)) return false;
    final dir = await _ensureProductsImagesDir();
    final normalizedPath = p.normalize(path);
    final normalizedDir = p.normalize(dir.path);
    return p.isWithin(normalizedDir, normalizedPath);
  }

  Future<bool> _isImagePathReferenced(
    Database db,
    String imagePath, {
    int? excludeProductId,
  }) async {
    final args = <dynamic>[imagePath];
    var where = 'image_path = ?';
    if (excludeProductId != null) {
      where += ' AND id != ?';
      args.add(excludeProductId);
    }
    final result = await db.query(
      DbTables.products,
      columns: ['COUNT(*) as count'],
      where: where,
      whereArgs: args,
    );
    return (Sqflite.firstIntValue(result) ?? 0) > 0;
  }

  Future<void> _deleteImageFileIfUnused(
    Database db,
    String? imagePath, {
    int? excludeProductId,
  }) async {
    final path = imagePath?.trim();
    if (path == null || path.isEmpty) return;
    if (!await _isManagedProductImagePath(path)) return;

    final isReferenced = await _isImagePathReferenced(
      db,
      path,
      excludeProductId: excludeProductId,
    );
    if (isReferenced) return;

    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // Ignorar fallos al borrar para no romper operaciones de negocio
    }
  }

  /// Borra archivos en /product_images que ya no están referenciados en DB.
  /// Se ejecuta de forma defensiva tras cambios que pueden dejar huérfanos.
  Future<void> cleanupOrphanProductImages() async {
    final db = await AppDb.database;

    final dir = await _ensureProductsImagesDir();
    if (!await dir.exists()) return;

    final rows = await db.query(
      DbTables.products,
      columns: ['image_path'],
      // NOTE: In SQLite, double-quotes denote identifiers (columns), not strings.
      // Use single quotes for the empty-string literal.
      where: "image_path IS NOT NULL AND TRIM(image_path) != ''",
    );

    final referenced = <String>{
      for (final r in rows)
        if (r['image_path'] != null) p.normalize(r['image_path'] as String),
    };

    try {
      final entries = dir.listSync(followLinks: false);
      for (final e in entries) {
        if (e is! File) continue;
        final filePath = p.normalize(e.path);
        if (!referenced.contains(filePath)) {
          try {
            e.deleteSync();
          } catch (_) {
            // Ignorar
          }
        }
      }
    } catch (_) {
      // Ignorar
    }
  }

  /// Obtiene todos los productos con filtros opcionales
  Future<List<ProductModel>> getAll({
    ProductFilters? filters,
    bool includeDeleted = false,
  }) async {
    final db = await AppDb.database;

    String where = '';
    List<dynamic> whereArgs = [];

    if (!includeDeleted) {
      where = 'deleted_at_ms IS NULL';
    }

    // Aplicar filtros
    if (filters != null) {
      if (filters.categoryId != null) {
        where += where.isEmpty ? '' : ' AND ';
        where += 'category_id = ?';
        whereArgs.add(filters.categoryId);
      }

      if (filters.supplierId != null) {
        where += where.isEmpty ? '' : ' AND ';
        where += 'supplier_id = ?';
        whereArgs.add(filters.supplierId);
      }

      if (filters.isActive != null) {
        where += where.isEmpty ? '' : ' AND ';
        where += 'is_active = ?';
        whereArgs.add(filters.isActive! ? 1 : 0);
      }

      if (filters.createdAfter != null) {
        where += where.isEmpty ? '' : ' AND ';
        where += 'created_at_ms >= ?';
        whereArgs.add(filters.createdAfter!.millisecondsSinceEpoch);
      }

      if (filters.createdBefore != null) {
        where += where.isEmpty ? '' : ' AND ';
        where += 'created_at_ms <= ?';
        whereArgs.add(filters.createdBefore!.millisecondsSinceEpoch);
      }

      if (filters.hasLowStock == true) {
        where += where.isEmpty ? '' : ' AND ';
        where += 'stock <= stock_min AND stock > 0';
      }

      if (filters.isOutOfStock == true) {
        where += where.isEmpty ? '' : ' AND ';
        where += 'stock <= 0';
      }
    }

    final List<Map<String, dynamic>> maps = await db.query(
      DbTables.products,
      where: where.isEmpty ? null : where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'name ASC',
    );

    return List.generate(maps.length, (i) => ProductModel.fromMap(maps[i]));
  }

  /// Busca productos por código o nombre
  Future<List<ProductModel>> search(
    String query, {
    ProductFilters? filters,
    bool includeDeleted = false,
  }) async {
    final db = await AppDb.database;

    String where = '(code LIKE ? OR name LIKE ?)';
    List<dynamic> whereArgs = ['%$query%', '%$query%'];

    if (!includeDeleted) {
      where += ' AND deleted_at_ms IS NULL';
    }

    // Aplicar filtros adicionales
    if (filters != null) {
      if (filters.categoryId != null) {
        where += ' AND category_id = ?';
        whereArgs.add(filters.categoryId);
      }

      if (filters.supplierId != null) {
        where += ' AND supplier_id = ?';
        whereArgs.add(filters.supplierId);
      }

      if (filters.isActive != null) {
        where += ' AND is_active = ?';
        whereArgs.add(filters.isActive! ? 1 : 0);
      }

      if (filters.createdAfter != null) {
        where += ' AND created_at_ms >= ?';
        whereArgs.add(filters.createdAfter!.millisecondsSinceEpoch);
      }

      if (filters.createdBefore != null) {
        where += ' AND created_at_ms <= ?';
        whereArgs.add(filters.createdBefore!.millisecondsSinceEpoch);
      }

      if (filters.hasLowStock == true) {
        where += ' AND stock <= stock_min AND stock > 0';
      }

      if (filters.isOutOfStock == true) {
        where += ' AND stock <= 0';
      }
    }

    final List<Map<String, dynamic>> maps = await db.query(
      DbTables.products,
      where: where,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );

    return List.generate(maps.length, (i) => ProductModel.fromMap(maps[i]));
  }

  /// Obtiene un producto por ID
  Future<ProductModel?> getById(int id) async {
    final db = await AppDb.database;

    final List<Map<String, dynamic>> maps = await db.query(
      DbTables.products,
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return ProductModel.fromMap(maps.first);
  }

  /// Obtiene un producto por código
  Future<ProductModel?> getByCode(String code) async {
    final db = await AppDb.database;

    final List<Map<String, dynamic>> maps = await db.query(
      DbTables.products,
      where: 'code = ? AND deleted_at_ms IS NULL',
      whereArgs: [code],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return ProductModel.fromMap(maps.first);
  }

  /// Crea un nuevo producto
  Future<int> create(ProductModel product) async {
    final db = await AppDb.database;

    final prepared = _withPlaceholderDefaults(product);
    _validateRequiredForSave(prepared);

    // Verificar que el codigo sea unico
    final exists = await existsByCode(prepared.code);
    if (exists) {
      throw ArgumentError(
        'Ya existe un producto con el codigo ${prepared.code}',
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final productToInsert = prepared.copyWith(
      createdAtMs: now,
      updatedAtMs: now,
    );

    return await db.transaction((txn) async {
      await AppDb.deleteDemoProducts(txn);
      await AppDb.deleteDemoCategories(txn);

      // Si existe un producto eliminado con el mismo cÃ³digo, reactivarlo y actualizarlo.
      final deletedRows = await txn.query(
        DbTables.products,
        columns: ['id'],
        where: 'code = ? AND deleted_at_ms IS NOT NULL',
        whereArgs: [prepared.code],
        limit: 1,
      );
      if (deletedRows.isNotEmpty) {
        final id = deletedRows.first['id'] as int;
        final revived = productToInsert.copyWith(id: id).toMap()
          ..['deleted_at_ms'] = null;
        await txn.update(
          DbTables.products,
          revived,
          where: 'id = ?',
          whereArgs: [id],
        );
        return id;
      }

      return await txn.insert(
        DbTables.products,
        productToInsert.toMap(),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    });
  }

  /// Actualiza un producto existente
  Future<int> update(ProductModel product) async {
    if (product.id == null) {
      throw ArgumentError('El producto debe tener un ID para actualizarlo');
    }

    final db = await AppDb.database;
    final prepared = _withPlaceholderDefaults(product);

    _validateRequiredForSave(prepared);

    // Capturar el image_path anterior para limpiar si cambia
    String? oldImagePath;
    try {
      final prev = await db.query(
        DbTables.products,
        columns: ['image_path'],
        where: 'id = ?',
        whereArgs: [prepared.id],
        limit: 1,
      );
      if (prev.isNotEmpty) {
        oldImagePath = prev.first['image_path'] as String?;
      }
    } catch (_) {
      // Si falla, no bloquea la actualizacion
    }

    // Verificar que el codigo sea unico (excluyendo el producto actual)
    final exists = await existsByCode(prepared.code, excludeId: prepared.id);
    if (exists) {
      throw ArgumentError(
        'Ya existe un producto con el codigo ${prepared.code}',
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final productToUpdate = prepared.copyWith(updatedAtMs: now);

    final updatedRows = await db.update(
      DbTables.products,
      productToUpdate.toMap(),
      where: 'id = ?',
      whereArgs: [prepared.id],
    );

    final newImagePath = productToUpdate.imagePath;
    final oldTrimmed = oldImagePath?.trim();
    final newTrimmed = newImagePath?.trim();
    final changed = (oldTrimmed ?? '') != (newTrimmed ?? '');

    if (changed) {
      await _deleteImageFileIfUnused(
        db,
        oldTrimmed,
        excludeProductId: prepared.id,
      );
      await cleanupOrphanProductImages();
    }

    return updatedRows;
  }

  /// Elimina lógicamente (soft delete) un producto
  Future<int> softDelete(int id) async {
    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;

    String? oldImagePath;
    try {
      final prev = await db.query(
        DbTables.products,
        columns: ['image_path'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (prev.isNotEmpty) {
        oldImagePath = prev.first['image_path'] as String?;
      }
    } catch (_) {
      // Ignorar
    }

    final rows = await db.update(
      DbTables.products,
      {'deleted_at_ms': now, 'updated_at_ms': now, 'image_path': null},
      where: 'id = ?',
      whereArgs: [id],
    );

    await _deleteImageFileIfUnused(db, oldImagePath, excludeProductId: id);
    await cleanupOrphanProductImages();
    await AppDb.syncDemoCatalog(db);

    return rows;
  }

  /// Elimina lógicamente (soft delete) todos los productos no eliminados.
  ///
  /// NOTA: Se ejecuta en bloque por performance y para evitar múltiples syncs.
  /// También limpia imágenes huérfanas después de dejar image_path en null.
  Future<int> softDeleteAll() async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    final rows = await db.update(DbTables.products, {
      'deleted_at_ms': now,
      'updated_at_ms': now,
      'image_path': null,
    }, where: 'deleted_at_ms IS NULL');

    await cleanupOrphanProductImages();
    await AppDb.syncDemoCatalog(db);
    return rows;
  }

  /// Restaura un producto eliminado
  Future<int> restore(int id) async {
    final db = await AppDb.database;

    final existing = await getById(id);
    if (existing == null) {
      throw ArgumentError('Producto no encontrado');
    }

    final conflict = await existsByCode(existing.code, excludeId: id);
    if (conflict) {
      throw ArgumentError(
        'No se puede restaurar: ya existe un producto activo con el código ${existing.code}',
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.update(
      DbTables.products,
      {'deleted_at_ms': null, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Elimina permanentemente un producto
  Future<int> hardDelete(int id) async {
    final db = await AppDb.database;

    String? oldImagePath;
    try {
      final prev = await db.query(
        DbTables.products,
        columns: ['image_path'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (prev.isNotEmpty) {
        oldImagePath = prev.first['image_path'] as String?;
      }
    } catch (_) {
      // Ignorar
    }

    final rows = await db.delete(
      DbTables.products,
      where: 'id = ?',
      whereArgs: [id],
    );

    await _deleteImageFileIfUnused(db, oldImagePath, excludeProductId: id);
    await cleanupOrphanProductImages();
    await AppDb.syncDemoCatalog(db);

    return rows;
  }

  /// Activa o desactiva un producto
  Future<int> toggleActive(int id, bool isActive) async {
    final db = await AppDb.database;

    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.update(
      DbTables.products,
      {'is_active': isActive ? 1 : 0, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Actualiza solo el stock de un producto
  Future<int> updateStock(int id, double newStock) async {
    final db = await AppDb.database;

    if (newStock < 0) {
      throw ArgumentError('El stock no puede ser negativo');
    }

    final now = DateTime.now().millisecondsSinceEpoch;

    return await db.update(
      DbTables.products,
      {'stock': newStock, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Cuenta los productos
  Future<int> count({
    ProductFilters? filters,
    bool includeDeleted = false,
  }) async {
    final db = await AppDb.database;

    String where = '';
    List<dynamic> whereArgs = [];

    if (!includeDeleted) {
      where = 'deleted_at_ms IS NULL';
    }

    // Aplicar filtros
    if (filters != null) {
      if (filters.categoryId != null) {
        where += where.isEmpty ? '' : ' AND ';
        where += 'category_id = ?';
        whereArgs.add(filters.categoryId);
      }

      if (filters.supplierId != null) {
        where += where.isEmpty ? '' : ' AND ';
        where += 'supplier_id = ?';
        whereArgs.add(filters.supplierId);
      }

      if (filters.isActive != null) {
        where += where.isEmpty ? '' : ' AND ';
        where += 'is_active = ?';
        whereArgs.add(filters.isActive! ? 1 : 0);
      }

      if (filters.hasLowStock == true) {
        where += where.isEmpty ? '' : ' AND ';
        where += 'stock <= stock_min AND stock > 0';
      }

      if (filters.isOutOfStock == true) {
        where += where.isEmpty ? '' : ' AND ';
        where += 'stock <= 0';
      }
    }

    final result = await db.query(
      DbTables.products,
      columns: ['COUNT(*) as count'],
      where: where.isEmpty ? null : where,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Verifica si existe un producto con el mismo código
  Future<bool> existsByCode(String code, {int? excludeId}) async {
    final db = await AppDb.database;

    String where = 'code = ? AND deleted_at_ms IS NULL';
    List<dynamic> whereArgs = [code];

    if (excludeId != null) {
      where += ' AND id != ?';
      whereArgs.add(excludeId);
    }

    final result = await db.query(
      DbTables.products,
      columns: ['COUNT(*) as count'],
      where: where,
      whereArgs: whereArgs,
    );

    final count = Sqflite.firstIntValue(result) ?? 0;
    return count > 0;
  }

  /// Obtiene productos con stock bajo
  Future<List<ProductModel>> getLowStock({bool includeDeleted = false}) async {
    return getAll(
      filters: const ProductFilters(hasLowStock: true, isActive: true),
      includeDeleted: includeDeleted,
    );
  }

  /// Obtiene productos agotados
  Future<List<ProductModel>> getOutOfStock({
    bool includeDeleted = false,
  }) async {
    return getAll(
      filters: const ProductFilters(isOutOfStock: true, isActive: true),
      includeDeleted: includeDeleted,
    );
  }

  /// Calcula el valor total del inventario
  Future<double> calculateTotalInventoryValue() async {
    final products = await getAll(
      filters: const ProductFilters(isActive: true),
    );
    return products.fold<double>(
      0.0,
      (sum, product) => sum + product.inventoryValue,
    );
  }

  /// Calcula el valor potencial de venta del inventario
  Future<double> calculateTotalPotentialRevenue() async {
    final products = await getAll(
      filters: const ProductFilters(isActive: true),
    );
    return products.fold<double>(
      0.0,
      (sum, product) => sum + product.potentialRevenue,
    );
  }

  /// Calcula la ganancia potencial del inventario
  Future<double> calculateTotalPotentialProfit() async {
    final products = await getAll(
      filters: const ProductFilters(isActive: true),
    );
    return products.fold<double>(
      0.0,
      (sum, product) => sum + (product.profit * product.stock),
    );
  }

  /// Calcula el total de unidades fヮsicas en inventario (solo activos)
  Future<double> calculateTotalUnits() async {
    final db = await AppDb.database;
    final rows = await db.rawQuery('''
      SELECT SUM(stock) AS total_units
      FROM ${DbTables.products}
      WHERE deleted_at_ms IS NULL AND is_active = 1
    ''');
    final total = rows.isNotEmpty ? rows.first['total_units'] as num? : null;
    return (total ?? 0).toDouble();
  }

  /// Cuenta los productos activos (sin eliminados)
  Future<int> countActive() async {
    return count(filters: const ProductFilters(isActive: true));
  }

  Future<ProductsImportSummary> importProducts(
    List<ProductModel> products,
  ) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    var inserted = 0;
    var updated = 0;

    return db.transaction((txn) async {
      await AppDb.deleteDemoProducts(txn);
      await AppDb.deleteDemoCategories(txn);

      for (final product in products) {
        final prepared = _withPlaceholderDefaults(product);
        _validateRequiredForSave(prepared);

        final rows = await txn.query(
          DbTables.products,
          columns: ['id', 'created_at_ms'],
          where: 'code = ?',
          whereArgs: [prepared.code],
          limit: 1,
        );

        if (rows.isNotEmpty) {
          final id = rows.first['id'] as int;
          final createdAtMs = rows.first['created_at_ms'] as int? ?? now;
          final toUpdate = prepared.copyWith(
            id: id,
            createdAtMs: createdAtMs,
            updatedAtMs: now,
            deletedAtMs: null,
          );
          await txn.update(
            DbTables.products,
            toUpdate.toMap(),
            where: 'id = ?',
            whereArgs: [id],
          );
          updated++;
        } else {
          final toInsert = prepared.copyWith(
            createdAtMs: now,
            updatedAtMs: now,
            deletedAtMs: null,
          );
          await txn.insert(
            DbTables.products,
            toInsert.toMap(),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
          inserted++;
        }
      }

      return ProductsImportSummary(inserted: inserted, updated: updated);
    });
  }

  /// Resumen de inventario por categoría
  Future<List<Map<String, dynamic>>> getInventoryByCategory() async {
    final db = await AppDb.database;
    final rows = await db.rawQuery('''
      SELECT
        -1 as id,
        'Sin categoria' as name,
        COALESCE(SUM(p.purchase_price * p.stock), 0) as total_value,
        COALESCE(SUM(p.sale_price * p.stock), 0) as total_revenue,
        COALESCE(SUM(p.stock), 0) as total_units,
        COUNT(p.id) as product_count
      FROM ${DbTables.products} p
      WHERE p.category_id IS NULL
        AND p.deleted_at_ms IS NULL
        AND p.is_active = 1
      UNION ALL
      SELECT
        c.id as id,
        c.name as name,
        COALESCE(SUM(p.purchase_price * p.stock), 0) as total_value,
        COALESCE(SUM(p.sale_price * p.stock), 0) as total_revenue,
        COALESCE(SUM(p.stock), 0) as total_units,
        COUNT(p.id) as product_count
      FROM ${DbTables.categories} c
      LEFT JOIN ${DbTables.products} p
        ON p.category_id = c.id
        AND p.deleted_at_ms IS NULL
        AND p.is_active = 1
      GROUP BY c.id, c.name
      ORDER BY total_value DESC, name COLLATE NOCASE ASC
    ''');
    return rows;
  }

  /// Resumen de inventario por suplidor
  Future<List<Map<String, dynamic>>> getInventoryBySupplier() async {
    final db = await AppDb.database;
    final rows = await db.rawQuery('''
      SELECT
        -1 as id,
        'Sin suplidor' as name,
        COALESCE(SUM(p.purchase_price * p.stock), 0) as total_value,
        COALESCE(SUM(p.sale_price * p.stock), 0) as total_revenue,
        COALESCE(SUM(p.stock), 0) as total_units,
        COUNT(p.id) as product_count
      FROM ${DbTables.products} p
      WHERE p.supplier_id IS NULL
        AND p.deleted_at_ms IS NULL
        AND p.is_active = 1
      UNION ALL
      SELECT
        s.id as id,
        s.name as name,
        COALESCE(SUM(p.purchase_price * p.stock), 0) as total_value,
        COALESCE(SUM(p.sale_price * p.stock), 0) as total_revenue,
        COALESCE(SUM(p.stock), 0) as total_units,
        COUNT(p.id) as product_count
      FROM ${DbTables.suppliers} s
      LEFT JOIN ${DbTables.products} p
        ON p.supplier_id = s.id
        AND p.deleted_at_ms IS NULL
        AND p.is_active = 1
      GROUP BY s.id, s.name
      ORDER BY total_value DESC, name COLLATE NOCASE ASC
    ''');
    return rows;
  }
}

class ProductsImportSummary {
  final int inserted;
  final int updated;

  const ProductsImportSummary({required this.inserted, required this.updated});
}
