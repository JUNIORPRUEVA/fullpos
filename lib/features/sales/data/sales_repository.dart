import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../../core/db/app_db.dart';
import '../../../core/db/tables.dart';
import '../../../core/db_hardening/db_hardening.dart';
import '../../../core/utils/app_event_bus.dart';
import '../../../core/validation/business_rules.dart';
import 'sales_model.dart';
import 'sale_item_model.dart' as new_models;

enum StockUpdateMode { deduct, reserve, none }

/// Repositorio de ventas con lógica de negocio completa
class SalesRepository {
  SalesRepository._();

  static final Random _random = Random();

  /// Genera código local único: V-YYYYMMDD-XXXXXXX (microsegundos + aleatorio).
  static String _generateLocalCode() {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final microSuffix = (now.microsecondsSinceEpoch % 1000000)
        .toString()
        .padLeft(6, '0');
    final randomSuffix = _random.nextInt(1000).toString().padLeft(3, '0');
    return 'V-$dateStr-$microSuffix$randomSuffix';
  }

  /// Genera el siguiente código local (compatible con versión anterior)
  static Future<String> generateNextLocalCode(String kind) async {
    return _generateLocalCode();
  }

  /// Crea una venta (compatible con versión anterior - wrapper)
  static Future<int> createSale({
    required String localCode,
    required String kind,
    required List<dynamic> items,
    String status = 'completed',
    bool allowNegativeStock = false,
    bool itbisEnabled = true,
    double itbisRate = 0.18,
    double discountTotal = 0.0,
    double? subtotalOverride,
    double? itbisAmountOverride,
    double? totalOverride,
    String? paymentMethod,
    int? sessionId,
    int? customerId,
    String? ncfFull,
    String? ncfType,
    bool fiscalEnabled = false,
    String? customerName,
    String? customerPhone,
    String? customerRnc,
    double? paidAmount,
    double? changeAmount,
    StockUpdateMode stockUpdateMode = StockUpdateMode.deduct,
    double creditInterestRate = 0.0,
    int? creditTermDays,
    int? creditDueDateMs,
    int? creditInstallments,
    String? creditNote,
  }) async {
    // Convertir items al formato esperado
    final convertedItems = <Map<String, dynamic>>[];
    for (final item in items) {
      var recognizedType = false;
      double subtotal = 0;
      double qty = 1.0;
      double unitPrice = 0.0;
      int? productId;
      String productCode = 'N/A';
      String productName = 'Item';
      double purchasePrice = 0.0;
      double discountLine = 0.0;
      double? totalLineOverride;

      if (item is SaleItemModel) {
        recognizedType = true;
        // Si es SaleItemModel, extraer propiedades directamente y convertir a double
        qty = item.qty.toDouble();
        unitPrice = item.unitPrice.toDouble();
        productId = item.productId;
        productCode = (item.productCodeSnapshot.isNotEmpty
            ? item.productCodeSnapshot
            : 'N/A');
        productName = (item.productNameSnapshot.isNotEmpty
            ? item.productNameSnapshot
            : 'Item');
        purchasePrice = item.purchasePriceSnapshot.toDouble();
        discountLine = item.discountLine.toDouble();
        subtotal = (qty * unitPrice) - discountLine;
        if (subtotal <= 0 && item.totalLine > 0) {
          subtotal = item.totalLine;
          if (unitPrice <= 0 && qty > 0) unitPrice = item.totalLine / qty;
        }
        if (unitPrice <= 0 && subtotal > 0 && qty > 0) {
          unitPrice = subtotal / qty;
        }
      } else if (item is new_models.SaleItemModel) {
        recognizedType = true;
        // SaleItemModel (nuevo) usado por SalesPage
        qty = item.qty.toDouble();
        unitPrice = item.unitPrice.toDouble();
        productId = item.productId;
        productCode = (item.productCodeSnapshot.isNotEmpty
            ? item.productCodeSnapshot
            : 'N/A');
        productName = (item.productNameSnapshot.isNotEmpty
            ? item.productNameSnapshot
            : 'Item');
        purchasePrice = item.purchasePriceSnapshot.toDouble();
        discountLine = item.discountLine.toDouble();
        subtotal = (qty * unitPrice) - discountLine;
        if (subtotal <= 0 && item.totalLine > 0) {
          subtotal = item.totalLine;
          if (unitPrice <= 0 && qty > 0) unitPrice = item.totalLine / qty;
        }
        if (unitPrice <= 0 && subtotal > 0 && qty > 0) {
          unitPrice = subtotal / qty;
        }
      } else if (item is Map) {
        recognizedType = true;
        // Si es Map, usar formato anterior y convertir a double
        double readNum(dynamic value, {double fallback = 0}) {
          if (value == null) return fallback;
          if (value is num) return value.toDouble();
          return double.tryParse(value.toString()) ?? fallback;
        }

        double? readNumNullable(dynamic value) {
          if (value == null) return null;
          if (value is num) return value.toDouble();
          return double.tryParse(value.toString());
        }

        qty = readNum(item['qty'], fallback: 1.0);
        unitPrice = readNum(
          item['unit_price'] ??
              item['price'] ??
              item['sale_price'] ??
              item['unitPrice'],
          fallback: 0.0,
        );
        productId = item['product_id'] as int? ?? item['id'] as int?;
        productCode =
            (item['product_code_snapshot'] ??
                    item['product_code'] ??
                    item['code'] ??
                    item['sku'] ??
                    'N/A')
                as String;
        productName =
            (item['product_name_snapshot'] ??
                    item['product_name'] ??
                    item['name'] ??
                    item['description'] ??
                    'Item')
                as String;
        purchasePrice = readNum(
          item['purchase_price_snapshot'] ??
              item['purchase_price'] ??
              item['cost'],
          fallback: 0.0,
        );
        discountLine = readNum(
          item['discount_line'] ?? item['discount'],
          fallback: 0.0,
        );
        totalLineOverride = readNumNullable(item['total_line']);

        if (productName.trim().isEmpty) productName = 'Item';
        if (productCode.trim().isEmpty) productCode = 'N/A';

        subtotal = (qty * unitPrice) - discountLine;
        if (subtotal <= 0 && (totalLineOverride ?? 0) > 0) {
          subtotal = totalLineOverride!;
          if (unitPrice <= 0 && qty > 0) unitPrice = subtotal / qty;
        }
        if (unitPrice <= 0 && subtotal > 0 && qty > 0) {
          unitPrice = subtotal / qty;
        }
      }

      if (!recognizedType) {
        throw ArgumentError(
          'Unsupported sale item payload type: ${item.runtimeType}. '
          'Expected SaleItemModel, new_models.SaleItemModel, or Map.',
        );
      }

      // Refuerzo final: si aún faltan datos y hay product_id, traer snapshot directo de BD
      if (productId != null &&
          (unitPrice <= 0 ||
              purchasePrice <= 0 ||
              subtotal <= 0 ||
              productName == 'Item' ||
              productCode == 'N/A')) {
        try {
          final db = await AppDb.database;
          final rows = await db.query(
            DbTables.products,
            columns: ['code', 'name', 'sale_price', 'purchase_price'],
            where: 'id = ?',
            whereArgs: [productId],
            limit: 1,
          );
          if (rows.isNotEmpty) {
            final row = rows.first;
            final dbCode = (row['code'] as String?) ?? 'N/A';
            final dbName = (row['name'] as String?) ?? 'Item';
            final dbSale = (row['sale_price'] as num?)?.toDouble() ?? 0.0;
            final dbCost = (row['purchase_price'] as num?)?.toDouble() ?? 0.0;

            if (productCode == 'N/A' || productCode.trim().isEmpty) {
              productCode = dbCode;
            }
            if (productName == 'Item' || productName.trim().isEmpty) {
              productName = dbName;
            }
            if (unitPrice <= 0 && dbSale > 0) {
              unitPrice = dbSale;
            }
            if (purchasePrice <= 0 && dbCost > 0) {
              purchasePrice = dbCost;
            }
            if (subtotal <= 0 && unitPrice > 0 && qty > 0) {
              subtotal = (qty * unitPrice) - discountLine;
            }
          }
        } catch (_) {
          // fallback silencioso; no queremos fallar la venta por snapshot
        }
      }

      convertedItems.add({
        'product_id': productId,
        'product_code_snapshot': productCode,
        'product_name_snapshot': productName,
        'qty': qty,
        'unit_price': unitPrice,
        'purchase_price_snapshot': purchasePrice,
        'discount_line': discountLine,
        'total_line': subtotal,
      });
    }

    // Validaciones mínimas para evitar datos inconsistentes.
    BusinessRules.requireNonNegative(discountTotal, 'discount_total');
    for (final item in convertedItems) {
      final qty = (item['qty'] as num?)?.toDouble() ?? 0.0;
      final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
      final discountLine = (item['discount_line'] as num?)?.toDouble() ?? 0.0;
      final totalLine = (item['total_line'] as num?)?.toDouble() ?? 0.0;

      BusinessRules.requirePositive(qty, 'qty');
      BusinessRules.requireNonNegative(unitPrice, 'unit_price');
      BusinessRules.requireNonNegative(discountLine, 'discount_line');
      BusinessRules.requireNonNegative(totalLine, 'total_line');
    }

    // Calcular subtotal si no viene precalculado
    double subtotal;
    if (subtotalOverride != null) {
      subtotal = subtotalOverride.clamp(0.0, double.infinity);
    } else {
      double tmp = 0;
      for (final item in convertedItems) {
        final totalLine = item['total_line'];
        if (totalLine is num) {
          tmp += totalLine.toDouble();
        } else {
          tmp += double.tryParse(totalLine.toString()) ?? 0.0;
        }
      }
      subtotal = (tmp - discountTotal).clamp(0.0, double.infinity);
    }

    final itbisAmount =
        itbisAmountOverride ?? (itbisEnabled ? (subtotal * itbisRate) : 0.0);
    final total = totalOverride ?? (subtotal + itbisAmount);

    String currentLocalCode = localCode;
    int? saleId;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        saleId = await saveSaleWithItems(
          localCode: currentLocalCode,
          kind: kind,
          customerId: customerId,
          customerName: customerName,
          customerPhone: customerPhone,
          customerRnc: customerRnc,
          itbisEnabled: itbisEnabled ? 1 : 0,
          itbisRate: itbisRate,
          discountTotal: discountTotal,
          subtotal: subtotal,
          itbisAmount: itbisAmount,
          total: total,
          paymentMethod: paymentMethod,
          paidAmount: paidAmount ?? total,
          changeAmount: changeAmount ?? 0.0,
          creditInterestRate: creditInterestRate,
          creditTermDays: creditTermDays,
          creditDueDateMs: creditDueDateMs,
          creditInstallments: creditInstallments,
          creditNote: creditNote,
          fiscalEnabled: fiscalEnabled ? 1 : 0,
          ncfFull: ncfFull,
          ncfType: ncfType,
          sessionId: sessionId,
          items: convertedItems,
          allowNegativeStock: allowNegativeStock,
          status: status,
          stockUpdateMode: stockUpdateMode,
        );
        break;
      } on DatabaseException catch (e) {
        if (!_isLocalCodeUniqueConstraint(e) || attempt == 5) {
          rethrow;
        }
        currentLocalCode = await generateNextLocalCode(kind);
      }
    }
    if (saleId == null) {
      throw StateError('No se pudo crear la venta con un código local único.');
    }

    // Usar la fecha real guardada en BD para que Reportes filtre por rango con precisión
    int createdAtMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final db = await AppDb.database;
      final rows = await db.query(
        DbTables.sales,
        columns: ['created_at_ms'],
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        createdAtMs = (rows.first['created_at_ms'] as int?) ?? createdAtMs;
      }
    } catch (_) {
      // No bloquear emisión del evento
    }

    AppEventBus.emit(
      SaleCompletedEvent(saleId: saleId, createdAtMs: createdAtMs),
    );

    return saleId;
  }

  /// Guarda una venta completa con transacción atómica
  /// Incluye: venta + items + ajuste de stock automático
  static Future<int> saveSaleWithItems({
    required String localCode,
    required String kind,
    int? customerId,
    String? customerName,
    String? customerPhone,
    String? customerRnc,
    required int itbisEnabled,
    required double itbisRate,
    required double discountTotal,
    required double subtotal,
    required double itbisAmount,
    required double total,
    required String? paymentMethod,
    required double paidAmount,
    required double changeAmount,
    required double creditInterestRate,
    int? creditTermDays,
    int? creditDueDateMs,
    int? creditInstallments,
    String? creditNote,
    required int fiscalEnabled,
    String? ncfFull,
    String? ncfType,
    int? sessionId,
    required List<Map<String, dynamic>> items,
    bool allowNegativeStock = false,
    String status = 'completed',
    StockUpdateMode stockUpdateMode = StockUpdateMode.deduct,
  }) {
    // FULLPOS DB HARDENING: proteger la creación completa de ventas.
    return DbHardening.instance.runDbSafe<int>(() async {
      final db = await AppDb.database;

      return await db.transaction((txn) async {
        final now = DateTime.now().millisecondsSinceEpoch;

        final saleId = await txn.insert(DbTables.sales, {
          'local_code': localCode,
          'kind': kind,
          'status': status,
          'customer_id': customerId,
          'customer_name_snapshot': customerName,
          'customer_phone_snapshot': customerPhone,
          'customer_rnc_snapshot': customerRnc,
          'itbis_enabled': itbisEnabled,
          'itbis_rate': itbisRate,
          'discount_total': discountTotal,
          'subtotal': subtotal,
          'itbis_amount': itbisAmount,
          'total': total,
          'payment_method': paymentMethod,
          'paid_amount': paidAmount,
          'change_amount': changeAmount,
          'credit_interest_rate': creditInterestRate,
          'credit_term_days': creditTermDays,
          'credit_due_date_ms': creditDueDateMs,
          'credit_installments': creditInstallments,
          'credit_note': creditNote,
          'fiscal_enabled': fiscalEnabled,
          'ncf_full': ncfFull,
          'ncf_type': ncfType,
          'session_id': sessionId,
          'created_at_ms': now,
          'updated_at_ms': now,
        });

        if (paymentMethod == 'credit' && customerId != null) {
          await txn.update(
            DbTables.clients,
            {'has_credit': 1, 'updated_at_ms': now},
            where: 'id = ?',
            whereArgs: [customerId],
          );
        }

        // Insertar items de venta
        for (final item in items) {
          int? resolvedProductId = item['product_id'] as int?;
          final codeSnapshotRaw = item['product_code_snapshot']?.toString();
          final codeSnapshot = codeSnapshotRaw?.trim();

          double resolvedPurchaseSnapshot;
          final purchaseRaw = item['purchase_price_snapshot'];
          if (purchaseRaw is num) {
            resolvedPurchaseSnapshot = purchaseRaw.toDouble();
          } else {
            resolvedPurchaseSnapshot =
                double.tryParse(purchaseRaw?.toString() ?? '') ?? 0.0;
          }

          // Si falta product_id o falta costo snapshot, intentar resolver desde products
          // usando primero product_id y luego product_code_snapshot.
          if ((resolvedProductId == null || resolvedPurchaseSnapshot <= 0) &&
              codeSnapshot != null &&
              codeSnapshot.isNotEmpty &&
              codeSnapshot != 'N/A') {
            final rows = await txn.query(
              DbTables.products,
              columns: ['id', 'purchase_price'],
              where: 'TRIM(code) = TRIM(?) COLLATE NOCASE',
              whereArgs: [codeSnapshot],
              limit: 1,
            );

            if (rows.isNotEmpty) {
              resolvedProductId =
                  resolvedProductId ?? (rows.first['id'] as int?);
              final cost =
                  (rows.first['purchase_price'] as num?)?.toDouble() ?? 0.0;
              if (resolvedPurchaseSnapshot <= 0 && cost > 0) {
                resolvedPurchaseSnapshot = cost;
              }
            }
          }

          if (resolvedProductId != null && resolvedPurchaseSnapshot <= 0) {
            final rows = await txn.query(
              DbTables.products,
              columns: ['purchase_price'],
              where: 'id = ?',
              whereArgs: [resolvedProductId],
              limit: 1,
            );

            if (rows.isNotEmpty) {
              final cost =
                  (rows.first['purchase_price'] as num?)?.toDouble() ?? 0.0;
              if (cost > 0) {
                resolvedPurchaseSnapshot = cost;
              }
            }
          }

          await txn.insert(DbTables.saleItems, {
            'sale_id': saleId,
            'product_id': resolvedProductId,
            'product_code_snapshot': item['product_code_snapshot'],
            'product_name_snapshot': item['product_name_snapshot'],
            'qty': item['qty'],
            'unit_price': item['unit_price'],
            'purchase_price_snapshot': resolvedPurchaseSnapshot,
            'discount_line': item['discount_line'] ?? 0.0,
            'total_line': item['total_line'],
            'created_at_ms': now,
          });

          // Ajustar stock automáticamente si tiene product_id
          if (resolvedProductId != null) {
            final productId = resolvedProductId;
            final qtyValue = item['qty'];
            final qty = qtyValue is num
                ? qtyValue.toDouble()
                : double.tryParse(qtyValue.toString()) ?? 1.0;

            if (qty <= 0) {
              throw BusinessRuleException(
                code: 'invalid_qty',
                messageUser: 'Verifica las cantidades e intenta de nuevo.',
                messageDev: 'Sale item qty must be > 0 (qty=$qty).',
              );
            }

            // Validar stock antes de descontar (evita negativos y ventas incompletas).
            final productRows = await txn.query(
              DbTables.products,
              columns: ['stock', 'reserved_stock', 'name', 'code'],
              where: 'id = ?',
              whereArgs: [productId],
              limit: 1,
            );

            if (productRows.isEmpty) {
              throw BusinessRuleException(
                code: 'product_not_found',
                messageUser:
                    'No se encontró un producto de la venta. Reintenta.',
                messageDev:
                    'Product not found while saving sale. productId=$productId',
              );
            }

            final currentStock =
                (productRows.first['stock'] as num?)?.toDouble() ?? 0.0;
            final reservedStock =
                (productRows.first['reserved_stock'] as num?)?.toDouble() ??
                0.0;
            final availableStock = currentStock - reservedStock;
            final newStock = currentStock - qty;

            if (stockUpdateMode != StockUpdateMode.none) {
              final remaining = availableStock - qty;
              if (!allowNegativeStock && remaining < 0) {
                final code =
                    (productRows.first['code'] as String?)?.trim() ?? 'N/A';
                final name =
                    (productRows.first['name'] as String?)?.trim() ??
                    'Producto';
                throw BusinessRuleException(
                  code: 'stock_negative',
                  messageUser:
                      'Stock insuficiente para "$name" ($code). Ajusta la cantidad o confirma venta sin stock.',
                  messageDev:
                      'Stock would go negative for productId=$productId code=$code name="$name": current=$currentStock reserved=$reservedStock qty=$qty remaining=$remaining.',
                );
              }
            }

            if (stockUpdateMode == StockUpdateMode.deduct) {
              // Restar stock del producto
              await txn.rawUpdate(
                'UPDATE ${DbTables.products} SET stock = stock - ? WHERE id = ?',
                [qty, productId],
              );

              // Registrar movimiento de stock
              await txn.insert(DbTables.stockMovements, {
                'product_id': productId,
                'type': 'SALE',
                'quantity': -qty,
                'note': allowNegativeStock && newStock < 0
                    ? 'Venta #$saleId - $localCode (sin stock)'
                    : 'Venta #$saleId - $localCode',
                'created_at_ms': now,
              });
            } else if (stockUpdateMode == StockUpdateMode.reserve) {
              await txn.rawUpdate(
                'UPDATE ${DbTables.products} SET reserved_stock = reserved_stock + ? WHERE id = ?',
                [qty, productId],
              );
            }
          }
        }

        return saleId;
      });
    }, stage: 'save_sale_with_items');
  }

  /// Obtiene una venta con sus items
  static Future<Map<String, dynamic>?> getSaleWithItems(int saleId) async {
    final db = await AppDb.database;

    final sale = await db.query(
      DbTables.sales,
      where: 'id = ?',
      whereArgs: [saleId],
    );

    if (sale.isEmpty) return null;

    final items = await db.query(
      DbTables.saleItems,
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );

    return {
      'sale': SaleModel.fromMap(sale.first),
      'items': items.map((item) => SaleItemModel.fromMap(item)).toList(),
    };
  }

  /// Lista ventas con filtros opcionales
  static Future<List<SaleModel>> listSales({
    int? customerId,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? status,
    String? paymentMethod,
  }) async {
    final db = await AppDb.database;

    String where = '1=1';
    List<dynamic> args = [];

    if (customerId != null) {
      where += ' AND customer_id = ?';
      args.add(customerId);
    }

    if (dateFrom != null) {
      final fromMs = dateFrom.millisecondsSinceEpoch;
      where += ' AND created_at_ms >= ?';
      args.add(fromMs);
    }

    if (dateTo != null) {
      final toMs = dateTo.add(Duration(days: 1)).millisecondsSinceEpoch;
      where += ' AND created_at_ms < ?';
      args.add(toMs);
    }

    if (status != null) {
      where += ' AND status = ?';
      args.add(status);
    }

    if (paymentMethod != null) {
      where += ' AND payment_method = ?';
      args.add(paymentMethod);
    }

    final result = await db.query(
      DbTables.sales,
      where: where,
      whereArgs: args,
      orderBy: 'created_at_ms DESC',
    );

    return result.map((map) => SaleModel.fromMap(map)).toList();
  }

  /// Lista ventas por sesion de caja
  static Future<List<SaleModel>> listSalesBySession(
    int sessionId, {
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await AppDb.database;

    final where = <String>[
      'session_id = ?',
      "kind = 'invoice'",
      'deleted_at_ms IS NULL',
      "status IN ('completed', 'PAID', 'PARTIAL_REFUND')",
    ];
    final args = <dynamic>[sessionId];

    if (dateFrom != null) {
      where.add('created_at_ms >= ?');
      args.add(dateFrom.millisecondsSinceEpoch);
    }
    if (dateTo != null) {
      where.add('created_at_ms < ?');
      args.add(dateTo.add(const Duration(days: 1)).millisecondsSinceEpoch);
    }

    final result = await db.query(
      DbTables.sales,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at_ms DESC',
    );

    return result.map((map) => SaleModel.fromMap(map)).toList();
  }

  /// Resumen de compras (ventas tipo invoice) de un cliente.
  /// - count: cantidad de ventas
  /// - total: total invertido
  /// - lastAtMs: fecha de la última compra
  static Future<Map<String, dynamic>> getCustomerPurchaseSummary(
    int customerId, {
    bool includePartialRefund = true,
  }) async {
    final db = await AppDb.database;

    final statusClause = includePartialRefund
        ? "status IN ('completed', 'PARTIAL_REFUND')"
        : "status = 'completed'";

    final rows = await db.rawQuery(
      '''
      SELECT
        COUNT(*) AS count,
        COALESCE(SUM(total), 0) AS total,
        MAX(created_at_ms) AS last_at_ms
      FROM ${DbTables.sales}
      WHERE customer_id = ?
        AND kind = 'invoice'
        AND deleted_at_ms IS NULL
        AND $statusClause
      ''',
      [customerId],
    );

    final row = rows.isNotEmpty ? rows.first : <String, Object?>{};
    return {
      'count': (row['count'] as int?) ?? 0,
      'total': (row['total'] as num?)?.toDouble() ?? 0.0,
      'lastAtMs': (row['last_at_ms'] as int?) ?? 0,
    };
  }

  /// Lista compras (ventas tipo invoice) de un cliente.
  static Future<List<SaleModel>> listCustomerPurchases(
    int customerId, {
    int limit = 30,
    int offset = 0,
    bool includePartialRefund = true,
  }) async {
    final db = await AppDb.database;

    final statusClause = includePartialRefund
        ? "status IN ('completed', 'PARTIAL_REFUND')"
        : "status = 'completed'";

    final maps = await db.query(
      DbTables.sales,
      where:
          "customer_id = ? AND kind = 'invoice' AND deleted_at_ms IS NULL AND $statusClause",
      whereArgs: [customerId],
      orderBy: 'created_at_ms DESC',
      limit: limit,
      offset: offset,
    );

    return maps.map((m) => SaleModel.fromMap(m)).toList();
  }

  /// Lista ventas de un cliente por tipo (invoice/quote/return).
  /// Para invoices aplica filtro de estados completados (y parcial) por defecto.
  static Future<List<SaleModel>> listCustomerSalesByKind(
    int customerId, {
    required String kind,
    int limit = 30,
    int offset = 0,
    DateTime? dateFrom,
    DateTime? dateTo,
    bool includePartialRefund = true,
  }) async {
    final db = await AppDb.database;

    final whereClauses = <String>[
      'customer_id = ?',
      'kind = ?',
      'deleted_at_ms IS NULL',
    ];
    final whereArgs = <dynamic>[customerId, kind];

    if (dateFrom != null) {
      whereClauses.add('created_at_ms >= ?');
      whereArgs.add(dateFrom.millisecondsSinceEpoch);
    }
    if (dateTo != null) {
      whereClauses.add('created_at_ms < ?');
      whereArgs.add(dateTo.add(const Duration(days: 1)).millisecondsSinceEpoch);
    }

    if (kind == 'invoice') {
      final statusClause = includePartialRefund
          ? "status IN ('completed', 'PAID', 'PARTIAL_REFUND')"
          : "status IN ('completed', 'PAID')";
      whereClauses.add(statusClause);
    }

    final maps = await db.query(
      DbTables.sales,
      where: whereClauses.join(' AND '),
      whereArgs: whereArgs,
      orderBy: 'created_at_ms DESC',
      limit: limit,
      offset: offset,
    );

    return maps.map((m) => SaleModel.fromMap(m)).toList();
  }

  /// KPIs globales de clientes por intervalo (basado en ventas tipo invoice).
  /// - clientsTotal: total de clientes registrados en la tienda
  /// - totalPurchased: total vendido a clientes en el intervalo
  /// - visitsCount: cantidad de tickets (ventas) a clientes en el intervalo
  static Future<Map<String, dynamic>> getClientsKpis({
    DateTime? dateFrom,
    DateTime? dateTo,
    bool includePartialRefund = true,
  }) async {
    final db = await AppDb.database;

    // Total de clientes registrados (no depende del intervalo)
    final clientRows = await db.rawQuery('''
      SELECT COUNT(*) AS clients_total
      FROM ${DbTables.clients}
      WHERE deleted_at_ms IS NULL
      ''');
    final clientsTotal =
        (clientRows.isNotEmpty
            ? (clientRows.first['clients_total'] as int?)
            : null) ??
        0;

    final where = <String>[
      "kind = 'invoice'",
      'customer_id IS NOT NULL',
      'deleted_at_ms IS NULL',
      includePartialRefund
          ? "status IN ('completed', 'PAID', 'PARTIAL_REFUND')"
          : "status IN ('completed', 'PAID')",
    ];
    final args = <dynamic>[];

    if (dateFrom != null) {
      where.add('created_at_ms >= ?');
      args.add(dateFrom.millisecondsSinceEpoch);
    }
    if (dateTo != null) {
      where.add('created_at_ms < ?');
      args.add(dateTo.add(const Duration(days: 1)).millisecondsSinceEpoch);
    }

    final rows = await db.rawQuery('''
      SELECT
        COUNT(DISTINCT customer_id) AS clients_count,
        COUNT(*) AS visits_count,
        COALESCE(SUM(total), 0) AS total_purchased
      FROM ${DbTables.sales}
      WHERE ${where.join(' AND ')}
      ''', args);

    final row = rows.isNotEmpty ? rows.first : <String, Object?>{};
    return {
      'clientsTotal': clientsTotal,
      'visitsCount': (row['visits_count'] as int?) ?? 0,
      'totalPurchased': (row['total_purchased'] as num?)?.toDouble() ?? 0.0,
    };
  }

  /// Busca ventas por código local o cliente
  static Future<List<SaleModel>> searchSales(String query) async {
    final db = await AppDb.database;

    final result = await db.query(
      DbTables.sales,
      where:
          'local_code LIKE ? OR customer_name_snapshot LIKE ? OR customer_phone_snapshot LIKE ?',
      whereArgs: ['%$query%', '%$query%', '%$query%'],
      orderBy: 'created_at_ms DESC',
    );

    return result.map((map) => SaleModel.fromMap(map)).toList();
  }

  /// Actualiza el estado de una venta
  static Future<bool> updateSaleStatus(int saleId, String newStatus) async {
    final db = await AppDb.database;

    final count = await db.update(
      DbTables.sales,
      {
        'status': newStatus,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [saleId],
    );

    return count > 0;
  }

  /// Obtiene estadísticas de ventas
  static Future<Map<String, dynamic>> getSalesStats({
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await AppDb.database;

    String where = '1=1';
    List<dynamic> args = [];

    if (dateFrom != null) {
      final fromMs = dateFrom.millisecondsSinceEpoch;
      where += ' AND created_at_ms >= ?';
      args.add(fromMs);
    }

    if (dateTo != null) {
      final toMs = dateTo.add(Duration(days: 1)).millisecondsSinceEpoch;
      where += ' AND created_at_ms < ?';
      args.add(toMs);
    }

    // Total de ventas
    final totalResult = await db.rawQuery(
      '''SELECT COUNT(*) as count, SUM(total) as total, SUM(itbis_amount) as itbis 
         FROM ${DbTables.sales} WHERE $where''',
      args,
    );

    final count = (totalResult.first['count'] as int?) ?? 0;
    final total = (totalResult.first['total'] as num?)?.toDouble() ?? 0.0;
    final itbis = (totalResult.first['itbis'] as num?)?.toDouble() ?? 0.0;

    return {
      'count': count,
      'total': total,
      'itbis': itbis,
      'average': count > 0 ? total / count : 0.0,
    };
  }

  /// Obtiene una venta por ID
  static Future<SaleModel?> getSaleById(int id) async {
    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.sales,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return SaleModel.fromMap(maps.first);
  }

  /// Lista ventas completadas (para devoluciones)
  static Future<List<SaleModel>> listCompletedSales({
    String? query,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    final db = await AppDb.database;

    String where =
        "status IN ('completed', 'PARTIAL_REFUND') AND kind = 'invoice' AND deleted_at_ms IS NULL";
    List<dynamic> args = [];

    if (query != null && query.isNotEmpty) {
      where += ' AND (local_code LIKE ? OR customer_name_snapshot LIKE ?)';
      args.addAll(['%$query%', '%$query%']);
    }

    if (dateFrom != null) {
      where += ' AND created_at_ms >= ?';
      args.add(dateFrom.millisecondsSinceEpoch);
    }

    if (dateTo != null) {
      where += ' AND created_at_ms <= ?';
      args.add(dateTo.add(const Duration(days: 1)).millisecondsSinceEpoch);
    }

    final maps = await db.query(
      DbTables.sales,
      where: where,
      whereArgs: args,
      orderBy: 'created_at_ms DESC',
      limit: 100,
    );

    return maps.map((m) => SaleModel.fromMap(m)).toList();
  }

  /// Obtiene los items de una venta
  static Future<List<SaleItemModel>> getItemsBySaleId(int saleId) async {
    final db = await AppDb.database;
    final maps = await db.query(
      DbTables.saleItems,
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'id ASC',
    );

    return maps.map((m) => SaleItemModel.fromMap(m)).toList();
  }

  /// Obtiene todas las ventas (sin filtros)
  static Future<List<SaleModel>> getAllSales() async {
    final db = await AppDb.database;
    final maps = await db.query(DbTables.sales, orderBy: 'created_at_ms DESC');
    return maps.map((m) => SaleModel.fromMap(m)).toList();
  }

  /// Completa purchase_price_snapshot faltante con el costo actual del producto
  /// Devuelve la cantidad de items actualizados
  static Future<int> backfillMissingPurchasePrices() async {
    final db = await AppDb.database;
    final rows = await db.rawQuery('''
      SELECT 
        si.id,
        si.product_id,
        si.product_code_snapshot,
        COALESCE(p.purchase_price, 0) AS cost,
        p.id AS resolved_product_id
      FROM ${DbTables.saleItems} si
      LEFT JOIN ${DbTables.products} p
        ON (si.product_id = p.id)
        OR (
          si.product_id IS NULL
          AND TRIM(si.product_code_snapshot) COLLATE NOCASE = TRIM(p.code) COLLATE NOCASE
        )
      WHERE (si.purchase_price_snapshot IS NULL OR si.purchase_price_snapshot <= 0)
        AND si.product_code_snapshot IS NOT NULL
    ''');

    if (rows.isEmpty) return 0;

    int updated = 0;
    await db.transaction((txn) async {
      for (final row in rows) {
        final itemId = row['id'] as int?;
        final cost = (row['cost'] as num?)?.toDouble() ?? 0.0;
        final resolvedProductId = row['resolved_product_id'] as int?;

        if (itemId != null && cost > 0) {
          final values = <String, Object?>{'purchase_price_snapshot': cost};

          if (row['product_id'] == null && resolvedProductId != null) {
            values['product_id'] = resolvedProductId;
          }

          await txn.update(
            DbTables.saleItems,
            values,
            where: 'id = ?',
            whereArgs: [itemId],
          );
          updated++;
        }
      }
    });

    return updated;
  }

  /// Cancela/Anula una venta y restaura el stock
  static Future<bool> cancelSale(int saleId, {String? reason}) async {
    final db = await AppDb.database;

    return await db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Obtener la venta
      final saleRows = await txn.query(
        DbTables.sales,
        where: 'id = ?',
        whereArgs: [saleId],
      );

      if (saleRows.isEmpty) return false;

      final sale = SaleModel.fromMap(saleRows.first);
      if (sale.status == 'cancelled') return false; // Ya está cancelada

      // Obtener los items de la venta
      final items = await txn.query(
        DbTables.saleItems,
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );

      // Restaurar stock de cada producto
      for (final item in items) {
        final productId = item['product_id'] as int?;
        final qty = (item['qty'] as num?)?.toDouble() ?? 0.0;

        if (productId != null && qty > 0) {
          // Restaurar stock
          await txn.rawUpdate(
            'UPDATE ${DbTables.products} SET stock = stock + ? WHERE id = ?',
            [qty, productId],
          );

          // Registrar movimiento de stock (cancelación)
          final cancelNote = reason != null && reason.trim().isNotEmpty
              ? reason.trim()
              : null;

          await txn.insert(DbTables.stockMovements, {
            'product_id': productId,
            'type': 'CANCELLATION',
            'quantity': qty,
            'note': cancelNote == null
                ? 'Anulación venta #$saleId - ${sale.localCode}'
                : 'Anulación venta #$saleId - ${sale.localCode} | Motivo: $cancelNote',
            'created_at_ms': now,
          });
        }
      }

      // Actualizar estado de la venta
      await txn.update(
        DbTables.sales,
        {'status': 'cancelled', 'updated_at_ms': now},
        where: 'id = ?',
        whereArgs: [saleId],
      );

      return true;
    });
  }

  static bool _isLocalCodeUniqueConstraint(DatabaseException e) {
    final message = e.toString().toLowerCase();
    return message.contains('unique constraint failed: sales.local_code');
  }
}
