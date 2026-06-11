/// Modelo de Categoría
class CategoryModel {
  static const Object _unset = Object();
  final int? id;
  final String name;
  final String? imagePath;
  final bool isActive;
  final int? deletedAtMs;
  final int createdAtMs;
  final int updatedAtMs;

  CategoryModel({
    this.id,
    required this.name,
    this.imagePath,
    this.isActive = true,
    this.deletedAtMs,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  /// Crea desde mapa (base de datos)
  factory CategoryModel.fromMap(Map<String, dynamic> map) {
    return CategoryModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      imagePath: map['image_path'] as String?,
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
      'image_path': imagePath,
      'is_active': isActive ? 1 : 0,
      'deleted_at_ms': deletedAtMs,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
    };
  }

  /// Copia con modificaciones
  CategoryModel copyWith({
    int? id,
    String? name,
    Object? imagePath = _unset,
    bool? isActive,
    Object? deletedAtMs = _unset,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      imagePath: imagePath == _unset ? this.imagePath : imagePath as String?,
      isActive: isActive ?? this.isActive,
      deletedAtMs: deletedAtMs == _unset
          ? this.deletedAtMs
          : deletedAtMs as int?,
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
    return 'CategoryModel(id: $id, name: $name, isActive: $isActive, isDeleted: $isDeleted)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CategoryModel &&
        other.id == id &&
        other.name == name &&
        other.imagePath == imagePath &&
        other.isActive == isActive &&
        other.deletedAtMs == deletedAtMs &&
        other.createdAtMs == createdAtMs &&
        other.updatedAtMs == updatedAtMs;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        name.hashCode ^
        imagePath.hashCode ^
        isActive.hashCode ^
        deletedAtMs.hashCode ^
        createdAtMs.hashCode ^
        updatedAtMs.hashCode;
  }
}
