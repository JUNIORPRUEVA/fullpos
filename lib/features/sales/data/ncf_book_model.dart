/// Modelo para talonarios de NCF (Números de Comprobante Fiscal)
class NcfBookModel {
  final int? id;
  final String type; // B01, B02, B14, B15
  final String? series;
  final int fromN;
  final int toN;
  final int nextN;
  final bool isActive;
  final int? expiresAtMs;
  final String? note;
  final int createdAtMs;
  final int updatedAtMs;
  final int? deletedAtMs;

  NcfBookModel({
    this.id,
    required this.type,
    this.series,
    required this.fromN,
    required this.toN,
    required this.nextN,
    this.isActive = true,
    this.expiresAtMs,
    this.note,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.deletedAtMs,
  });

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  DateTime? get expiresAt => expiresAtMs != null
      ? DateTime.fromMillisecondsSinceEpoch(expiresAtMs!)
      : null;
  DateTime? get deletedAt => deletedAtMs != null
      ? DateTime.fromMillisecondsSinceEpoch(deletedAtMs!)
      : null;

  bool get isDeleted => deletedAtMs != null;
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
  bool get isAvailable => isActive && !isDeleted && !isExpired && nextN <= toN;
  int get remaining => toN - nextN + 1;

  /// Construye el NCF completo: type + series (opcional) + número padded
  String buildNcf({int? number}) {
    final paddedNumber = (number ?? nextN).toString().padLeft(8, '0');
    return series != null ? '$type$series$paddedNumber' : '$type$paddedNumber';
  }

  factory NcfBookModel.fromMap(Map<String, dynamic> map) {
    return NcfBookModel(
      id: map['id'] as int?,
      type: map['type'] as String,
      series: map['series'] as String?,
      fromN: map['from_n'] as int,
      toN: map['to_n'] as int,
      nextN: map['next_n'] as int,
      isActive: (map['is_active'] as int) == 1,
      expiresAtMs: map['expires_at_ms'] as int?,
      note: map['note'] as String?,
      createdAtMs: map['created_at_ms'] as int,
      updatedAtMs: map['updated_at_ms'] as int,
      deletedAtMs: map['deleted_at_ms'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'type': type,
      'series': series,
      'from_n': fromN,
      'to_n': toN,
      'next_n': nextN,
      'is_active': isActive ? 1 : 0,
      'expires_at_ms': expiresAtMs,
      'note': note,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
      'deleted_at_ms': deletedAtMs,
    };
  }

  NcfBookModel copyWith({
    int? id,
    String? type,
    String? series,
    int? fromN,
    int? toN,
    int? nextN,
    bool? isActive,
    int? expiresAtMs,
    String? note,
    int? createdAtMs,
    int? updatedAtMs,
    int? deletedAtMs,
  }) {
    return NcfBookModel(
      id: id ?? this.id,
      type: type ?? this.type,
      series: series ?? this.series,
      fromN: fromN ?? this.fromN,
      toN: toN ?? this.toN,
      nextN: nextN ?? this.nextN,
      isActive: isActive ?? this.isActive,
      expiresAtMs: expiresAtMs ?? this.expiresAtMs,
      note: note ?? this.note,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      deletedAtMs: deletedAtMs ?? this.deletedAtMs,
    );
  }
}

/// Tipos de NCF disponibles
class NcfType {
  static const String creditoFiscal = 'B01';
  static const String consumidorFinal = 'B02';
  static const String regimenesEspeciales = 'B14';
  static const String gubernamental = 'B15';

  static const List<String> all = [
    creditoFiscal,
    consumidorFinal,
    regimenesEspeciales,
    gubernamental,
  ];

  static String getDescription(String type) {
    switch (type) {
      case creditoFiscal:
        return 'B01 - Crédito Fiscal';
      case consumidorFinal:
        return 'B02 - Consumidor Final';
      case regimenesEspeciales:
        return 'B14 - Regímenes Especiales';
      case gubernamental:
        return 'B15 - Gubernamental';
      default:
        return type;
    }
  }
}
