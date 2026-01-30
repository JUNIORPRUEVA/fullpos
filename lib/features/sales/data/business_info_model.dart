/// Modelo para información del negocio
class BusinessInfoModel {
  final int? id;
  final String name;
  final String? phone;
  final String? address;
  final String? rnc;
  final String? slogan;
  final int updatedAtMs;

  BusinessInfoModel({
    this.id,
    required this.name,
    this.phone,
    this.address,
    this.rnc,
    this.slogan,
    required this.updatedAtMs,
  });

  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);

  factory BusinessInfoModel.fromMap(Map<String, dynamic> map) {
    return BusinessInfoModel(
      id: map['id'] as int?,
      name: map['name'] as String,
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      rnc: map['rnc'] as String?,
      slogan: map['slogan'] as String?,
      updatedAtMs: map['updated_at_ms'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'rnc': rnc,
      'slogan': slogan,
      'updated_at_ms': updatedAtMs,
    };
  }

  BusinessInfoModel copyWith({
    int? id,
    String? name,
    String? phone,
    String? address,
    String? rnc,
    String? slogan,
    int? updatedAtMs,
  }) {
    return BusinessInfoModel(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      rnc: rnc ?? this.rnc,
      slogan: slogan ?? this.slogan,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}
