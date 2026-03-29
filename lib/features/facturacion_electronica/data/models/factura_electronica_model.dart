class FacturaElectronicaModel {
  static const String statusLocal = 'local';
  static const String statusConfigPending = 'pendiente_configuracion';
  static const String statusPending = 'pendiente_dgii';
  static const String statusAccepted = 'aceptada';
  static const String statusRejected = 'rechazada';

  final int? id;
  final int saleId;
  final String localCode;
  final String? ecf;
  final String tipoDocumento;
  final String? xmlPayload;
  final String? xmlFirmado;
  final String? dgiiTrackId;
  final String estadoDgii;
  final String? codigoDgii;
  final String? mensajeDgii;
  final String? ambiente;
  final double montoTotal;
  final String? clienteNombre;
  final String? clienteRnc;
  final int createdAtMs;
  final int updatedAtMs;
  final int? sentAtMs;
  final int? acknowledgedAtMs;

  const FacturaElectronicaModel({
    this.id,
    required this.saleId,
    required this.localCode,
    this.ecf,
    required this.tipoDocumento,
    this.xmlPayload,
    this.xmlFirmado,
    this.dgiiTrackId,
    required this.estadoDgii,
    this.codigoDgii,
    this.mensajeDgii,
    this.ambiente,
    required this.montoTotal,
    this.clienteNombre,
    this.clienteRnc,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.sentAtMs,
    this.acknowledgedAtMs,
  });

  String get statusLabel {
    switch (estadoDgii) {
      case statusAccepted:
        return 'Aceptada';
      case statusRejected:
        return 'Rechazada';
      case statusPending:
        return 'Pendiente DGII';
      case statusConfigPending:
        return 'Configurar';
      default:
        return 'Local';
    }
  }

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'sale_id': saleId,
    'local_code': localCode,
    'ecf': ecf,
    'tipo_documento': tipoDocumento,
    'xml_payload': xmlPayload,
    'xml_firmado': xmlFirmado,
    'dgii_track_id': dgiiTrackId,
    'estado_dgii': estadoDgii,
    'codigo_dgii': codigoDgii,
    'mensaje_dgii': mensajeDgii,
    'ambiente': ambiente,
    'monto_total': montoTotal,
    'cliente_nombre': clienteNombre,
    'cliente_rnc': clienteRnc,
    'created_at_ms': createdAtMs,
    'updated_at_ms': updatedAtMs,
    'sent_at_ms': sentAtMs,
    'acknowledged_at_ms': acknowledgedAtMs,
  };

  factory FacturaElectronicaModel.fromMap(Map<String, dynamic> map) {
    return FacturaElectronicaModel(
      id: map['id'] as int?,
      saleId: map['sale_id'] as int,
      localCode: map['local_code'] as String,
      ecf: map['ecf'] as String?,
      tipoDocumento: map['tipo_documento'] as String? ?? 'venta',
      xmlPayload: map['xml_payload'] as String?,
      xmlFirmado: map['xml_firmado'] as String?,
      dgiiTrackId: map['dgii_track_id'] as String?,
      estadoDgii: map['estado_dgii'] as String? ?? statusLocal,
      codigoDgii: map['codigo_dgii'] as String?,
      mensajeDgii: map['mensaje_dgii'] as String?,
      ambiente: map['ambiente'] as String?,
      montoTotal: (map['monto_total'] as num?)?.toDouble() ?? 0.0,
      clienteNombre: map['cliente_nombre'] as String?,
      clienteRnc: map['cliente_rnc'] as String?,
      createdAtMs: map['created_at_ms'] as int,
      updatedAtMs: map['updated_at_ms'] as int,
      sentAtMs: map['sent_at_ms'] as int?,
      acknowledgedAtMs: map['acknowledged_at_ms'] as int?,
    );
  }

  FacturaElectronicaModel copyWith({
    int? id,
    int? saleId,
    String? localCode,
    String? ecf,
    String? tipoDocumento,
    String? xmlPayload,
    String? xmlFirmado,
    String? dgiiTrackId,
    String? estadoDgii,
    String? codigoDgii,
    String? mensajeDgii,
    String? ambiente,
    double? montoTotal,
    String? clienteNombre,
    String? clienteRnc,
    int? createdAtMs,
    int? updatedAtMs,
    int? sentAtMs,
    int? acknowledgedAtMs,
  }) {
    return FacturaElectronicaModel(
      id: id ?? this.id,
      saleId: saleId ?? this.saleId,
      localCode: localCode ?? this.localCode,
      ecf: ecf ?? this.ecf,
      tipoDocumento: tipoDocumento ?? this.tipoDocumento,
      xmlPayload: xmlPayload ?? this.xmlPayload,
      xmlFirmado: xmlFirmado ?? this.xmlFirmado,
      dgiiTrackId: dgiiTrackId ?? this.dgiiTrackId,
      estadoDgii: estadoDgii ?? this.estadoDgii,
      codigoDgii: codigoDgii ?? this.codigoDgii,
      mensajeDgii: mensajeDgii ?? this.mensajeDgii,
      ambiente: ambiente ?? this.ambiente,
      montoTotal: montoTotal ?? this.montoTotal,
      clienteNombre: clienteNombre ?? this.clienteNombre,
      clienteRnc: clienteRnc ?? this.clienteRnc,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      sentAtMs: sentAtMs ?? this.sentAtMs,
      acknowledgedAtMs: acknowledgedAtMs ?? this.acknowledgedAtMs,
    );
  }
}