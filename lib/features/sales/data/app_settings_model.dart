/// Modelo para configuración de la aplicación
class AppSettingsModel {
  final int? id;
  final bool itbisEnabledDefault;
  final double itbisRate;
  final String ticketSize; // '80mm' or 'A4'
  final int updatedAtMs;

  AppSettingsModel({
    this.id,
    required this.itbisEnabledDefault,
    required this.itbisRate,
    required this.ticketSize,
    required this.updatedAtMs,
  });

  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);

  factory AppSettingsModel.fromMap(Map<String, dynamic> map) {
    return AppSettingsModel(
      id: map['id'] as int?,
      itbisEnabledDefault: (map['itbis_enabled_default'] as int) == 1,
      itbisRate: (map['itbis_rate'] as num).toDouble(),
      ticketSize: map['ticket_size'] as String,
      updatedAtMs: map['updated_at_ms'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'itbis_enabled_default': itbisEnabledDefault ? 1 : 0,
      'itbis_rate': itbisRate,
      'ticket_size': ticketSize,
      'updated_at_ms': updatedAtMs,
    };
  }

  AppSettingsModel copyWith({
    int? id,
    bool? itbisEnabledDefault,
    double? itbisRate,
    String? ticketSize,
    int? updatedAtMs,
  }) {
    return AppSettingsModel(
      id: id ?? this.id,
      itbisEnabledDefault: itbisEnabledDefault ?? this.itbisEnabledDefault,
      itbisRate: itbisRate ?? this.itbisRate,
      ticketSize: ticketSize ?? this.ticketSize,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }
}
