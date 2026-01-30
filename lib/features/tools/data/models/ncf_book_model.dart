/// Modelo para representar un libro/talonario de NCF
class NcfBookModel {
  final int? id;
  final String type; // B01, B02, B14, B15, etc.
  final String? series; // Serie opcional (ej: A, B, C)
  final int fromN;
  final int toN;
  final int nextN;
  final bool isActive;
  final DateTime? expiresAt;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  NcfBookModel({
    this.id,
    required this.type,
    this.series,
    required this.fromN,
    required this.toN,
    required this.nextN,
    this.isActive = true,
    this.expiresAt,
    this.note,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  /// Genera el NCF completo con formato: TIPO + SERIE (opcional) + NÚMERO (8 dígitos)
  /// Ejemplo: B0100000001 o B01A00000001
  String generateFullNcf() {
    final seriesPart = series ?? '';
    final numberPart = nextN.toString().padLeft(8, '0');
    return '$type$seriesPart$numberPart';
  }

  /// Verifica si el talonario está disponible (tiene números disponibles)
  bool get isAvailable => nextN <= toN;

  /// Verifica si el talonario está agotado
  bool get isExhausted => nextN > toN;

  /// Cantidad de números disponibles
  int get availableCount => (toN - nextN + 1).clamp(0, toN - fromN + 1);

  /// Porcentaje de uso (0.0 a 1.0)
  double get usagePercentage {
    final total = toN - fromN + 1;
    final used = nextN - fromN;
    return (used / total).clamp(0.0, 1.0);
  }

  /// Estado del talonario para mostrar en UI
  String get statusLabel {
    if (!isActive) return 'Inactivo';
    if (isExhausted) return 'Agotado';
    if (expiresAt != null && expiresAt!.isBefore(DateTime.now())) {
      return 'Vencido';
    }
    return 'Disponible';
  }

  /// Color del estado para UI
  String get statusColor {
    if (!isActive) return 'gray';
    if (isExhausted) return 'red';
    if (expiresAt != null && expiresAt!.isBefore(DateTime.now())) {
      return 'orange';
    }
    return 'green';
  }

  /// Crear desde Map (DB)
  factory NcfBookModel.fromMap(Map<String, dynamic> map) {
    return NcfBookModel(
      id: map['id'] as int?,
      type: map['type'] as String,
      series: map['series'] as String?,
      fromN: map['from_n'] as int,
      toN: map['to_n'] as int,
      nextN: map['next_n'] as int,
      isActive: (map['is_active'] as int) == 1,
      expiresAt: map['expires_at_ms'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['expires_at_ms'] as int)
          : null,
      note: map['note'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        map['created_at_ms'] as int,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updated_at_ms'] as int,
      ),
      deletedAt: map['deleted_at_ms'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['deleted_at_ms'] as int)
          : null,
    );
  }

  /// Convertir a Map (DB)
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'type': type,
      'series': series,
      'from_n': fromN,
      'to_n': toN,
      'next_n': nextN,
      'is_active': isActive ? 1 : 0,
      'expires_at_ms': expiresAt?.millisecondsSinceEpoch,
      'note': note,
      'created_at_ms': createdAt.millisecondsSinceEpoch,
      'updated_at_ms': updatedAt.millisecondsSinceEpoch,
      if (deletedAt != null) 'deleted_at_ms': deletedAt!.millisecondsSinceEpoch,
    };
  }

  /// Crear copia con cambios
  NcfBookModel copyWith({
    int? id,
    String? type,
    String? series,
    int? fromN,
    int? toN,
    int? nextN,
    bool? isActive,
    DateTime? expiresAt,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) {
    return NcfBookModel(
      id: id ?? this.id,
      type: type ?? this.type,
      series: series ?? this.series,
      fromN: fromN ?? this.fromN,
      toN: toN ?? this.toN,
      nextN: nextN ?? this.nextN,
      isActive: isActive ?? this.isActive,
      expiresAt: expiresAt ?? this.expiresAt,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }

  @override
  String toString() {
    return 'NcfBookModel(id: $id, type: $type, series: $series, '
        'range: $fromN-$toN, next: $nextN, active: $isActive)';
  }
}

/// Tipos de NCF comunes en República Dominicana
class NcfTypes {
  static const String b01 = 'B01'; // Facturas de Crédito Fiscal
  static const String b02 = 'B02'; // Facturas de Consumo
  static const String b14 = 'B14'; // Notas de Crédito
  static const String b15 = 'B15'; // Notas de Débito
  static const String b16 = 'B16'; // Comprobante de Compras

  static const List<String> all = [b01, b02, b14, b15, b16];

  static String getDescription(String type) {
    switch (type) {
      case b01:
        return 'Crédito Fiscal';
      case b02:
        return 'Consumo';
      case b14:
        return 'Nota de Crédito';
      case b15:
        return 'Nota de Débito';
      case b16:
        return 'Comprobante de Compras';
      default:
        return type;
    }
  }
}
