import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbPath = args.isNotEmpty ? args.first : r'C:\Users\PC\Documents\fullpos.db';
  if (!File(dbPath).existsSync()) {
    stderr.writeln('DB not found: $dbPath');
    exitCode = 2;
    return;
  }

  final db = await databaseFactory.openDatabase(dbPath);
  try {
    Future<void> q(String title, String sql, [List<Object?>? params]) async {
      stdout.writeln('\n=== $title ===');
      final rows = await db.rawQuery(sql, params);
      for (final row in rows) {
        stdout.writeln(row);
      }
    }

    await q(
      'Products summary',
      '''
      SELECT
        COUNT(*) AS products,
        SUM(CASE WHEN COALESCE(purchase_price, 0) > 0 THEN 1 ELSE 0 END) AS with_cost,
        ROUND(AVG(COALESCE(purchase_price, 0)), 2) AS avg_cost,
        MAX(COALESCE(purchase_price, 0)) AS max_cost,
        SUM(CASE WHEN COALESCE(sale_price, 0) > 0 THEN 1 ELSE 0 END) AS with_sale_price
      FROM products
      WHERE deleted_at_ms IS NULL
      ''',
    );

    await q(
      'Sale items summary',
      '''
      SELECT
        COUNT(*) AS items,
        SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS product_id_null,
        SUM(CASE WHEN product_code_snapshot IS NULL OR TRIM(product_code_snapshot) = '' OR product_code_snapshot = 'N/A' THEN 1 ELSE 0 END) AS code_missing,
        SUM(CASE WHEN COALESCE(purchase_price_snapshot, 0) > 0 THEN 1 ELSE 0 END) AS with_snapshot_cost,
        SUM(CASE WHEN COALESCE(total_line, 0) > 0 THEN 1 ELSE 0 END) AS with_total_line
      FROM sale_items
      ''',
    );

    await q(
      'HEALTH CHECK (should be >0 after a new sale with real products)',
      '''
      SELECT
        SUM(CASE WHEN COALESCE(si.total_line, 0) > 0 THEN 1 ELSE 0 END) AS items_with_total_line,
        SUM(CASE WHEN si.product_id IS NOT NULL THEN 1 ELSE 0 END) AS items_with_product_id,
        SUM(
          CASE
            WHEN COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0) > 0 THEN 1
            ELSE 0
          END
        ) AS items_with_any_cost,
        SUM(
          CASE
            WHEN COALESCE(si.total_line, 0) > 0
             AND COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0) > 0
            THEN 1
            ELSE 0
          END
        ) AS items_eligible_for_profit
      FROM sale_items si
      INNER JOIN sales s ON si.sale_id = s.id
      LEFT JOIN products p
        ON (si.product_id = p.id)
        OR (
          si.product_id IS NULL
          AND TRIM(si.product_code_snapshot) COLLATE NOCASE = TRIM(p.code) COLLATE NOCASE
        )
      WHERE s.kind IN ('invoice', 'sale')
        AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND')
        AND s.deleted_at_ms IS NULL
      ''',
    );

    await q(
      'How many sale_items can resolve a product cost (by id or code)',
      '''
      SELECT
        SUM(CASE WHEN p_by_id.id IS NOT NULL THEN 1 ELSE 0 END) AS match_by_id,
        SUM(CASE WHEN p_by_code.id IS NOT NULL THEN 1 ELSE 0 END) AS match_by_code,
        SUM(CASE WHEN COALESCE(p_by_id.purchase_price, 0) > 0 THEN 1 ELSE 0 END) AS cost_by_id_gt0,
        SUM(CASE WHEN COALESCE(p_by_code.purchase_price, 0) > 0 THEN 1 ELSE 0 END) AS cost_by_code_gt0
      FROM sale_items si
      LEFT JOIN products p_by_id ON si.product_id = p_by_id.id
      LEFT JOIN products p_by_code ON TRIM(si.product_code_snapshot) COLLATE NOCASE = TRIM(p_by_code.code) COLLATE NOCASE
      ''',
    );

    await q(
      'Computed totals (all time)',
      '''
      SELECT
        ROUND(COALESCE(SUM(COALESCE(si.total_line, 0)), 0), 2) AS total_sales,
        ROUND(COALESCE(SUM(COALESCE(si.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0)), 0), 2) AS total_cost,
        ROUND(COALESCE(SUM(COALESCE(si.total_line, 0) - (COALESCE(si.qty, 0) * COALESCE(NULLIF(si.purchase_price_snapshot, 0), p.purchase_price, 0))), 0), 2) AS total_profit
      FROM sale_items si
      INNER JOIN sales s ON si.sale_id = s.id
      LEFT JOIN products p
        ON (si.product_id = p.id)
        OR (
          si.product_id IS NULL
          AND TRIM(si.product_code_snapshot) COLLATE NOCASE = TRIM(p.code) COLLATE NOCASE
        )
      WHERE s.kind IN ('invoice', 'sale')
        AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND')
        AND s.deleted_at_ms IS NULL
      ''',
    );

    await q(
      'Sample latest 15 sale_items with cost signals',
      '''
      SELECT
        si.id,
        si.sale_id,
        si.product_id,
        si.product_code_snapshot,
        si.product_name_snapshot,
        si.qty,
        si.total_line,
        si.purchase_price_snapshot,
        p.purchase_price AS product_purchase_price,
        p.code AS product_code
      FROM sale_items si
      INNER JOIN sales s ON si.sale_id = s.id
      LEFT JOIN products p
        ON (si.product_id = p.id)
        OR (
          si.product_id IS NULL
          AND TRIM(si.product_code_snapshot) COLLATE NOCASE = TRIM(p.code) COLLATE NOCASE
        )
      WHERE s.kind IN ('invoice', 'sale')
        AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND')
        AND s.deleted_at_ms IS NULL
      ORDER BY si.id DESC
      LIMIT 15
      ''',
    );

    await q(
      'Sales table totals (all time)',
      '''
      SELECT
        COUNT(*) AS sales,
        ROUND(COALESCE(SUM(total), 0), 2) AS total_sales
      FROM sales
      WHERE kind IN ('invoice', 'sale')
        AND status IN ('completed', 'PAID', 'PARTIAL_REFUND')
        AND deleted_at_ms IS NULL
      ''',
    );
  } finally {
    await db.close();
  }
}
