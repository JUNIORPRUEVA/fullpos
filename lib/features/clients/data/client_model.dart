/// Modelo de cliente
class ClientModel {
  final int? id;
  final String nombre;
  final String? telefono;
  final String? direccion;
  final String? rnc;
  final String? cedula;
  final bool isActive;
  final bool hasCredit;
  final int? deletedAtMs;
  final int createdAtMs;
  final int updatedAtMs;

  ClientModel({
    this.id,
    required this.nombre,
    this.telefono,
    this.direccion,
    this.rnc,
    this.cedula,
    this.isActive = true,
    this.hasCredit = false,
    this.deletedAtMs,
    required int createdAtMs,
    required int updatedAtMs,
  }) : createdAtMs = createdAtMs > 0 ? createdAtMs : DateTime.now().millisecondsSinceEpoch,
       updatedAtMs = updatedAtMs > 0 ? updatedAtMs : DateTime.now().millisecondsSinceEpoch;

  /// Crea un cliente desde un mapa (base de datos)
  factory ClientModel.fromMap(Map<String, dynamic> map) {
    return ClientModel(
      id: map['id'] as int?,
      nombre: map['nombre'] as String,
      telefono: map['telefono'] as String?,
      direccion: map['direccion'] as String?,
      rnc: map['rnc'] as String?,
      cedula: map['cedula'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      hasCredit: (map['has_credit'] as int? ?? 0) == 1,
      deletedAtMs: map['deleted_at_ms'] as int?,
      createdAtMs: map['created_at_ms'] as int,
      updatedAtMs: map['updated_at_ms'] as int,
    );
  }

  /// Convierte el cliente a un mapa (para base de datos)
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nombre': nombre,
      'telefono': telefono,
      'direccion': direccion,
      'rnc': rnc,
      'cedula': cedula,
      'is_active': isActive ? 1 : 0,
      'has_credit': hasCredit ? 1 : 0,
      'deleted_at_ms': deletedAtMs,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
    };
  }

  /// Copia el cliente con nuevos valores
  ClientModel copyWith({
    int? id,
    String? nombre,
    String? telefono,
    String? direccion,
    String? rnc,
    String? cedula,
    bool? isActive,
    bool? hasCredit,
    int? deletedAtMs,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return ClientModel(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      telefono: telefono ?? this.telefono,
      direccion: direccion ?? this.direccion,
      rnc: rnc ?? this.rnc,
      cedula: cedula ?? this.cedula,
      isActive: isActive ?? this.isActive,
      hasCredit: hasCredit ?? this.hasCredit,
      deletedAtMs: deletedAtMs ?? this.deletedAtMs,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  /// Helper: indica si el cliente está eliminado (soft delete)
  bool get isDeleted => deletedAtMs != null;
}

