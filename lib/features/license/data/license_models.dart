import 'package:flutter/foundation.dart';

@immutable
class LicenseInfo {
  final String backendBaseUrl;
  final String licenseKey;
  final String deviceId;
  final String projectCode;

  final bool ok;
  final String? code;
  final String? tipo;
  final String? estado;
  final DateTime? fechaInicio;
  final DateTime? fechaFin;
  final int? maxDispositivos;
  final int? usados;
  final DateTime? lastCheckedAt;

  const LicenseInfo({
    required this.backendBaseUrl,
    required this.licenseKey,
    required this.deviceId,
    required this.projectCode,
    required this.ok,
    this.code,
    this.tipo,
    this.estado,
    this.fechaInicio,
    this.fechaFin,
    this.maxDispositivos,
    this.usados,
    this.lastCheckedAt,
  });

  bool get isActive {
    if (!ok) return false;
    final st = (estado ?? '').toUpperCase();
    if (st.isEmpty) return ok;
    return st == 'ACTIVA';
  }

  bool get isExpired {
    final fin = fechaFin;
    if (fin == null) return false;
    return fin.isBefore(DateTime.now());
  }

  Map<String, dynamic> toJson() {
    return {
      'backendBaseUrl': backendBaseUrl,
      'licenseKey': licenseKey,
      'deviceId': deviceId,
      'projectCode': projectCode,
      'ok': ok,
      'code': code,
      'tipo': tipo,
      'estado': estado,
      'fechaInicio': fechaInicio?.toIso8601String(),
      'fechaFin': fechaFin?.toIso8601String(),
      'maxDispositivos': maxDispositivos,
      'usados': usados,
      'lastCheckedAt': lastCheckedAt?.toIso8601String(),
    };
  }

  factory LicenseInfo.fromJson(Map<String, dynamic> map) {
    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      final raw = v.toString();
      if (raw.trim().isEmpty) return null;
      return DateTime.tryParse(raw);
    }

    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      return int.tryParse(v.toString());
    }

    return LicenseInfo(
      backendBaseUrl: (map['backendBaseUrl'] ?? '').toString(),
      licenseKey: (map['licenseKey'] ?? '').toString(),
      deviceId: (map['deviceId'] ?? '').toString(),
      projectCode: (map['projectCode'] ?? '').toString(),
      ok: map['ok'] == true,
      code: map['code']?.toString(),
      tipo: map['tipo']?.toString(),
      estado: map['estado']?.toString(),
      fechaInicio: parseDt(map['fechaInicio']),
      fechaFin: parseDt(map['fechaFin']),
      maxDispositivos: parseInt(map['maxDispositivos']),
      usados: parseInt(map['usados']),
      lastCheckedAt: parseDt(map['lastCheckedAt']),
    );
  }
}

@immutable
class LicenseApiException implements Exception {
  final int? statusCode;
  final String message;
  final String? code;

  const LicenseApiException({
    required this.message,
    this.statusCode,
    this.code,
  });

  @override
  String toString() =>
      'LicenseApiException(status=$statusCode code=$code message=$message)';
}
