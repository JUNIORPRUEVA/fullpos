/// Tipo de movimiento de stock
enum StockMovementType {
  input('in', 'Entrada'),
  output('out', 'Salida'),
  adjust('adjust', 'Ajuste');

  final String value;
  final String label;

  const StockMovementType(this.value, this.label);

  static StockMovementType fromString(String value) {
    return StockMovementType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => StockMovementType.adjust,
    );
  }
}

/// Modelo de Movimiento de Stock
class StockMovementModel {
  final int? id;
  final int productId;
  final StockMovementType type;
  final double quantity;
  final String? note;
  final int? userId;
  final int createdAtMs;

  StockMovementModel({
    this.id,
    required this.productId,
    required this.type,
    required this.quantity,
    this.note,
    this.userId,
    required this.createdAtMs,
  });

  /// Crea desde mapa (base de datos)
  factory StockMovementModel.fromMap(Map<String, dynamic> map) {
    return StockMovementModel(
      id: map['id'] as int?,
      productId: map['product_id'] as int,
      type: StockMovementType.fromString(map['type'] as String),
      quantity: (map['quantity'] as num).toDouble(),
      note: map['note'] as String?,
      userId: map['user_id'] as int?,
      createdAtMs: map['created_at_ms'] as int,
    );
  }

  /// Convierte a mapa (para base de datos)
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'product_id': productId,
      'type': type.value,
      'quantity': quantity,
      'note': note,
      'user_id': userId,
      'created_at_ms': createdAtMs,
    };
  }

  /// Copia con modificaciones
  StockMovementModel copyWith({
    int? id,
    int? productId,
    StockMovementType? type,
    double? quantity,
    String? note,
    int? userId,
    int? createdAtMs,
  }) {
    return StockMovementModel(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      type: type ?? this.type,
      quantity: quantity ?? this.quantity,
      note: note ?? this.note,
      userId: userId ?? this.userId,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  /// Fecha de creación
  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);

  /// Si es entrada de stock
  bool get isInput => type == StockMovementType.input;

  /// Si es salida de stock
  bool get isOutput => type == StockMovementType.output;

  /// Si es ajuste de stock
  bool get isAdjust => type == StockMovementType.adjust;

  @override
  String toString() {
    return 'StockMovementModel(id: $id, productId: $productId, type: ${type.label}, quantity: $quantity, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is StockMovementModel &&
        other.id == id &&
        other.productId == productId &&
        other.type == type &&
        other.quantity == quantity &&
        other.note == note &&
        other.userId == userId &&
        other.createdAtMs == createdAtMs;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        productId.hashCode ^
        type.hashCode ^
        quantity.hashCode ^
        note.hashCode ^
        userId.hashCode ^
        createdAtMs.hashCode;
  }
}

/// Detalle enriquecido de un movimiento (para vistas e historiales)
class StockMovementDetail {
  final StockMovementModel movement;
  final String? productName;
  final String? productCode;
  final double? currentStock;
  final String? userDisplayName;
  final String? userUsername;

  const StockMovementDetail({
    required this.movement,
    this.productName,
    this.productCode,
    this.currentStock,
    this.userDisplayName,
    this.userUsername,
  });

  /// Etiqueta amigable para el usuario que lo registrゴ.
  String get userLabel {
    if (userDisplayName != null && userDisplayName!.trim().isNotEmpty) {
      return userDisplayName!;
    }
    if (userUsername != null && userUsername!.trim().isNotEmpty) {
      return userUsername!;
    }
    return 'Sistema';
  }

  /// Etiqueta amigable para el producto.
  String get productLabel => productName ?? 'Producto #${movement.productId}';
}

/// Resumen agregado de movimientos de inventario.
class StockSummary {
  final double totalInputs;
  final double totalOutputs;
  final double totalAdjustments;
  final int movementsCount;

  const StockSummary({
    this.totalInputs = 0,
    this.totalOutputs = 0,
    this.totalAdjustments = 0,
    this.movementsCount = 0,
  });

  double get netChange => totalInputs - totalOutputs + totalAdjustments;
}
