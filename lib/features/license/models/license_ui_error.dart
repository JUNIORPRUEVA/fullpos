import 'package:flutter/foundation.dart';

enum LicenseErrorType {
  offline,
  timeout,
  dns,
  ssl,
  serverDown,
  unauthorized,
  notActivated,
  invalidLicenseFile,
  expired,
  corruptedLocalFile,
  unknown,
}

enum LicenseAction {
  retry,
  verifyConnection,
  openWhatsapp,
  copySupportCode,
  repairAndRetry,
  exportDiagnostics,
}

@immutable
class LicenseUiError {
  const LicenseUiError({
    required this.type,
    required this.title,
    required this.message,
    required this.supportCode,
    required this.actions,
    this.technicalSummary,
    this.endpoint,
    this.httpStatusCode,
  });

  final LicenseErrorType type;
  final String title;
  final String message;

  /// Código corto para soporte (ej: LIC-SSL-01)
  final String supportCode;

  /// Acciones recomendadas para resolver.
  final List<LicenseAction> actions;

  /// Resumen corto (solo soporte). No stacktrace.
  final String? technicalSummary;

  /// Último endpoint intentado (sin datos sensibles).
  final String? endpoint;

  /// HTTP status si aplica.
  final int? httpStatusCode;

  bool get isBlocking {
    switch (type) {
      case LicenseErrorType.expired:
      case LicenseErrorType.unauthorized:
        return true;
      case LicenseErrorType.offline:
      case LicenseErrorType.timeout:
      case LicenseErrorType.dns:
      case LicenseErrorType.ssl:
      case LicenseErrorType.serverDown:
      case LicenseErrorType.notActivated:
      case LicenseErrorType.invalidLicenseFile:
      case LicenseErrorType.corruptedLocalFile:
      case LicenseErrorType.unknown:
        return false;
    }
  }
}
