/// Modelo de Producto con soporte de imagen o placeholder por color.
class ProductModel {
  final int? id;
  final String code;
  final String name;
  final String? imagePath;
  final String? imageUrl;
  final String? placeholderColorHex;
  final String placeholderType; // 'image' | 'color'
  final int? categoryId;
  final int? supplierId;
  final double purchasePrice;
  final double salePrice;
  final double stock;
  final double reservedStock;
  final double stockMin;
  final bool isActive;
  final int? deletedAtMs;
  final int createdAtMs;
  final int updatedAtMs;

  ProductModel({
    this.id,
    required this.code,
    required this.name,
    this.imagePath,
    this.imageUrl,
    this.placeholderColorHex,
    this.placeholderType = 'image',
    this.categoryId,
    this.supplierId,
    this.purchasePrice = 0.0,
    this.salePrice = 0.0,
    this.stock = 0.0,
    this.reservedStock = 0.0,
    this.stockMin = 0.0,
    this.isActive = true,
    this.deletedAtMs,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  /// Crea desde mapa (base de datos)
  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] as int?,
      code: map['code'] as String,
      name: map['name'] as String,
      imagePath: map['image_path'] as String?,
      imageUrl: map['image_url'] as String?,
      placeholderColorHex: map['placeholder_color_hex'] as String?,
      placeholderType: (map['placeholder_type'] as String?)?.toLowerCase() ??
          'image',
      categoryId: map['category_id'] as int?,
      supplierId: map['supplier_id'] as int?,
      purchasePrice: (map['purchase_price'] as num?)?.toDouble() ?? 0.0,
      salePrice: (map['sale_price'] as num?)?.toDouble() ?? 0.0,
      stock: (map['stock'] as num?)?.toDouble() ?? 0.0,
      reservedStock: (map['reserved_stock'] as num?)?.toDouble() ?? 0.0,
      stockMin: (map['stock_min'] as num?)?.toDouble() ?? 0.0,
      isActive: (map['is_active'] as int) == 1,
      deletedAtMs: map['deleted_at_ms'] as int?,
      createdAtMs: map['created_at_ms'] as int,
      updatedAtMs: map['updated_at_ms'] as int,
    );
  }

  /// Convierte a mapa (para base de datos)
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'name': name,
      'image_path': imagePath,
      'image_url': imageUrl,
      'placeholder_color_hex': placeholderColorHex,
      'placeholder_type': placeholderType,
      'category_id': categoryId,
      'supplier_id': supplierId,
      'purchase_price': purchasePrice,
      'sale_price': salePrice,
      'stock': stock,
      'reserved_stock': reservedStock,
      'stock_min': stockMin,
      'is_active': isActive ? 1 : 0,
      'deleted_at_ms': deletedAtMs,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
    };
  }

  /// Copia con modificaciones
  ProductModel copyWith({
    int? id,
    String? code,
    String? name,
    String? imagePath,
    String? imageUrl,
    String? placeholderColorHex,
    String? placeholderType,
    int? categoryId,
    int? supplierId,
    double? purchasePrice,
    double? salePrice,
    double? stock,
    double? reservedStock,
    double? stockMin,
    bool? isActive,
    int? deletedAtMs,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return ProductModel(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      imagePath: imagePath ?? this.imagePath,
      imageUrl: imageUrl ?? this.imageUrl,
      placeholderColorHex: placeholderColorHex ?? this.placeholderColorHex,
      placeholderType: placeholderType ?? this.placeholderType,
      categoryId: categoryId ?? this.categoryId,
      supplierId: supplierId ?? this.supplierId,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      salePrice: salePrice ?? this.salePrice,
      stock: stock ?? this.stock,
      reservedStock: reservedStock ?? this.reservedStock,
      stockMin: stockMin ?? this.stockMin,
      isActive: isActive ?? this.isActive,
      deletedAtMs: deletedAtMs ?? this.deletedAtMs,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  /// Si está eliminado (soft delete)
  bool get isDeleted => deletedAtMs != null;

  /// Si tiene stock bajo
  bool get hasLowStock => stock <= stockMin && stock > 0;

  /// Si está agotado
  bool get isOutOfStock => stock <= 0;

  /// Stock disponible (descontando apartados)
  double get availableStock => stock - reservedStock;

  /// Margen de ganancia
  double get profit => salePrice - purchasePrice;

  /// Porcentaje de margen
  double get profitPercentage =>
      purchasePrice > 0 ? (profit / purchasePrice) * 100 : 0;

  /// Valor del inventario de este producto
  double get inventoryValue => stock * purchasePrice;

  /// Valor potencial de venta de este producto
  double get potentialRevenue => stock * salePrice;

  /// Fecha de creación
  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);

  /// Fecha de actualización
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);

  /// Fecha de eliminación (si existe)
  DateTime? get deletedAt => deletedAtMs != null
      ? DateTime.fromMillisecondsSinceEpoch(deletedAtMs!)
      : null;

  bool get prefersImage => placeholderType == 'image';
  bool get hasImagePath => imagePath != null && imagePath!.trim().isNotEmpty;
  bool get hasImageUrl => imageUrl != null && imageUrl!.trim().isNotEmpty;
  bool get hasAnyImage => hasImagePath || hasImageUrl;

  @override
  String toString() {
    return 'ProductModel(id: $id, code: $code, name: $name, stock: $stock, reservedStock: $reservedStock, salePrice: $salePrice, isActive: $isActive, placeholderType: $placeholderType)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ProductModel &&
        other.id == id &&
        other.code == code &&
        other.name == name &&
        other.imagePath == imagePath &&
        other.imageUrl == imageUrl &&
        other.placeholderColorHex == placeholderColorHex &&
        other.placeholderType == placeholderType &&
        other.categoryId == categoryId &&
        other.supplierId == supplierId &&
        other.purchasePrice == purchasePrice &&
        other.salePrice == salePrice &&
        other.stock == stock &&
        other.reservedStock == reservedStock &&
        other.stockMin == stockMin &&
        other.isActive == isActive &&
        other.deletedAtMs == deletedAtMs &&
        other.createdAtMs == createdAtMs &&
        other.updatedAtMs == updatedAtMs;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        code.hashCode ^
        name.hashCode ^
        imagePath.hashCode ^
        imageUrl.hashCode ^
        placeholderColorHex.hashCode ^
        placeholderType.hashCode ^
        categoryId.hashCode ^
        supplierId.hashCode ^
        purchasePrice.hashCode ^
        salePrice.hashCode ^
        stock.hashCode ^
        reservedStock.hashCode ^
        stockMin.hashCode ^
        isActive.hashCode ^
        deletedAtMs.hashCode ^
        createdAtMs.hashCode ^
        updatedAtMs.hashCode;
  }
}
