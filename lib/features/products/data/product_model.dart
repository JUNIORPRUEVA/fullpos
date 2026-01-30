/// Modelo de producto (versión simplificada para data layer legacy).
class ProductModel {
  final int? id;
  final String nombre;
  final String? codigo;
  final double precio;
  final int stock;
  final int reservedStock;
  final int createdAtMs;
  final int updatedAtMs;
  final String? imageUrl;
  final String? imagePath;
  final String? placeholderColorHex;
  final String placeholderType;

  ProductModel({
    this.id,
    required this.nombre,
    this.codigo,
    required this.precio,
    required this.stock,
    this.reservedStock = 0,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.imageUrl,
    this.imagePath,
    this.placeholderColorHex,
    this.placeholderType = 'image',
  });

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] as int?,
      nombre: map['nombre'] as String,
      codigo: map['codigo'] as String?,
      precio: (map['precio'] as num).toDouble(),
      stock: map['stock'] as int,
      reservedStock: (map['reserved_stock'] as num?)?.toInt() ?? 0,
      createdAtMs: map['created_at_ms'] as int,
      updatedAtMs: map['updated_at_ms'] as int,
      imageUrl: map['image_url'] as String?,
      imagePath: map['image_path'] as String?,
      placeholderColorHex: map['placeholder_color_hex'] as String?,
      placeholderType:
          (map['placeholder_type'] as String?)?.toLowerCase() ?? 'image',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nombre': nombre,
      'codigo': codigo,
      'precio': precio,
      'stock': stock,
      'reserved_stock': reservedStock,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
      'image_url': imageUrl,
      'image_path': imagePath,
      'placeholder_color_hex': placeholderColorHex,
      'placeholder_type': placeholderType,
    };
  }
}
