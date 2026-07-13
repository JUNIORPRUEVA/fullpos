import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/features/products/models/category_model.dart';
import 'package:fullpos/features/products/models/product_model.dart';
import 'package:fullpos/features/products/models/supplier_model.dart';
import 'package:fullpos/features/products/utils/products_exporter.dart';

void main() {
  test('exported products workbook always includes purchase price', () {
    const now = 1720000000000;
    final workbook = ProductsExporter.buildProductsWorkbook(
      products: [
        ProductModel(
          code: 'SKU-001',
          name: 'Cafe molido',
          categoryId: 1,
          supplierId: 2,
          purchasePrice: 125.50,
          salePrice: 175.00,
          stock: 10,
          reservedStock: 1,
          stockMin: 2,
          createdAtMs: now,
          updatedAtMs: now,
        ),
      ],
      categories: [
        CategoryModel(
          id: 1,
          name: 'Abarrotes',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      ],
      suppliers: [
        SupplierModel(
          id: 2,
          name: 'Proveedor Uno',
          createdAtMs: now,
          updatedAtMs: now,
        ),
      ],
    );

    final sheet = workbook['Productos'];

    expect(
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0)).value,
      TextCellValue('Precio Compra'),
    );
    expect(
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1)).value,
      const DoubleCellValue(125.50),
    );
    expect(
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 0)).value,
      TextCellValue('Precio Venta'),
    );
  });
}
