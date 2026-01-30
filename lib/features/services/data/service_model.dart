/// Modelo de servicio
/// TODO: Implementar modelo completo
class ServiceModel {
  final int? id;
  final String nombre;
  final double precio;
  final int createdAtMs;

  ServiceModel({
    this.id,
    required this.nombre,
    required this.precio,
    required this.createdAtMs,
  });

  factory ServiceModel.fromMap(Map<String, dynamic> map) {
    return ServiceModel(
      id: map['id'] as int?,
      nombre: map['nombre'] as String,
      precio: map['precio'] as double,
      createdAtMs: map['created_at_ms'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'nombre': nombre,
      'precio': precio,
      'created_at_ms': createdAtMs,
    };
  }
}
