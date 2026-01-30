/// Modelo de Suplidor
class SupplierModel {
  final int? id;
  final String name;
  final String? phone;
  final String? note;
  final bool isActive;
  final int? deletedAtMs;
  final int createdAtMs;
  final int updatedAtMs;

  SupplierModel({
    this.id,
    required this.name,
    this.phone,
    this.note,
    this.isActive = true,
    this.deletedAtMs,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  /// Crea desde mapa (base de datos)
  factory SupplierModel.fromMap(Map<String, dynamic> map) {
    return SupplierModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      note: map['note'] as String?,
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
      'name': name,
      'phone': phone,
      'note': note,
      'is_active': isActive ? 1 : 0,
      'deleted_at_ms': deletedAtMs,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
    };
  }

  /// Copia con modificaciones
  SupplierModel copyWith({
    int? id,
    String? name,
    String? phone,
    String? note,
    bool? isActive,
    int? deletedAtMs,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return SupplierModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      note: note ?? this.note,
      isActive: isActive ?? this.isActive,
      deletedAtMs: deletedAtMs ?? this.deletedAtMs,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  /// Si está eliminado (soft delete)
  bool get isDeleted => deletedAtMs != null;

  /// Fecha de creación
  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);

  /// Fecha de actualización
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);

  /// Fecha de eliminación (si existe)
  DateTime? get deletedAt => deletedAtMs != null
      ? DateTime.fromMillisecondsSinceEpoch(deletedAtMs!)
      : null;

  @override
  String toString() {
    return 'SupplierModel(id: $id, name: $name, phone: $phone, isActive: $isActive, isDeleted: $isDeleted)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is SupplierModel &&
        other.id == id &&
        other.name == name &&
        other.phone == phone &&
        other.note == note &&
        other.isActive == isActive &&
        other.deletedAtMs == deletedAtMs &&
        other.createdAtMs == createdAtMs &&
        other.updatedAtMs == updatedAtMs;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        phone.hashCode ^
        note.hashCode ^
        isActive.hashCode ^
        deletedAtMs.hashCode ^
        createdAtMs.hashCode ^
        updatedAtMs.hashCode;
  }
}
