import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';
import '../data/license_models.dart';
import '../models/license_ui_error.dart';

@immutable
class LicenseErrorContext {
  const LicenseErrorContext({
    this.operation,
    this.endpoint,
    this.httpStatusCode,
    this.backendCode,
  });

  final String? operation;
  final String? endpoint;
  final int? httpStatusCode;
  final String? backendCode;
}

class LicenseErrorMapper {
  static LicenseUiError map(
    Object error, {
    LicenseErrorContext context = const LicenseErrorContext(),
  }) {
    if (error is LicenseUiError) return error;

    // ApiException comes from ApiClient (timeouts, sockets, SSL, etc.).
    if (error is ApiException) {
      return _fromMessage(
        error.message,
        context: context,
        technical: 'ApiException(${error.statusCode ?? '-'})',
        status: error.statusCode,
      );
    }

    if (error is TimeoutException) {
      return LicenseUiError(
        type: LicenseErrorType.timeout,
        title: 'Tiempo de espera agotado',
        message:
            'La verificación de licencia está tardando demasiado. Revisa tu conexión e intenta de nuevo.',
        supportCode: 'LIC-NET-02',
        actions: const [
          LicenseAction.retry,
          LicenseAction.verifyConnection,
          LicenseAction.openWhatsapp,
          LicenseAction.copySupportCode,
        ],
        technicalSummary: 'Timeout (${context.operation ?? 'licensing'})',
        endpoint: context.endpoint,
      );
    }

    if (error is SocketException) {
      final msg = (error.message).toLowerCase();
      final isDns =
          msg.contains('failed host lookup') ||
          msg.contains('name not resolved') ||
          msg.contains('no address associated') ||
          msg.contains('getaddrinfo');

      if (isDns) {
        return LicenseUiError(
          type: LicenseErrorType.dns,
          title: 'No se pudo encontrar el servidor',
          message:
              'Parece un problema de red o DNS. Prueba otra red o reinicia el router.',
          supportCode: 'LIC-NET-03',
          actions: const [
            LicenseAction.retry,
            LicenseAction.verifyConnection,
            LicenseAction.openWhatsapp,
            LicenseAction.copySupportCode,
          ],
          technicalSummary: 'DNS: ${error.osError?.message ?? error.message}',
          endpoint: context.endpoint,
        );
      }

      return LicenseUiError(
        type: LicenseErrorType.offline,
        title: 'Sin internet',
        message:
            'No pudimos conectarnos para verificar tu licencia. Si tu licencia ya está guardada o tu prueba sigue activa, puedes continuar usando el sistema.',
        supportCode: 'LIC-NET-01',
        actions: const [
          LicenseAction.retry,
          LicenseAction.verifyConnection,
          LicenseAction.openWhatsapp,
          LicenseAction.copySupportCode,
        ],
        technicalSummary: 'Socket: ${error.osError?.message ?? error.message}',
        endpoint: context.endpoint,
      );
    }

    if (error is HandshakeException) {
      return LicenseUiError(
        type: LicenseErrorType.ssl,
        title: 'Conexión segura falló',
        message:
            'Tu computadora no pudo validar la conexión segura. Revisa la fecha y hora de Windows y vuelve a intentar. Si estás en una red corporativa, puede estar bloqueando la conexión.',
        supportCode: 'LIC-SSL-01',
        actions: const [
          LicenseAction.retry,
          LicenseAction.verifyConnection,
          LicenseAction.openWhatsapp,
          LicenseAction.copySupportCode,
        ],
        technicalSummary: 'SSL handshake',
        endpoint: context.endpoint,
      );
    }

    if (error is LicenseApiException) {
      final status = error.statusCode ?? context.httpStatusCode;
      if (status == 204) {
        return LicenseUiError(
          type: LicenseErrorType.notActivated,
          title: 'Esperando activación',
          message:
              'Tu solicitud fue recibida. Cuando el administrador active tu licencia, se descargará automáticamente.',
          supportCode: 'LIC-ACT-01',
          actions: const [
            LicenseAction.retry,
            LicenseAction.openWhatsapp,
            LicenseAction.copySupportCode,
          ],
          technicalSummary: 'HTTP 204 / not activated',
          endpoint: context.endpoint,
          httpStatusCode: status,
        );
      }

      if (status == 401 || status == 403) {
        return LicenseUiError(
          type: LicenseErrorType.unauthorized,
          title: 'Acceso no autorizado',
          message:
              'No pudimos validar esta licencia con el servidor. Verifica que la clave sea correcta y vuelve a intentar.',
          supportCode: 'LIC-AUTH-01',
          actions: const [
            LicenseAction.retry,
            LicenseAction.openWhatsapp,
            LicenseAction.copySupportCode,
          ],
          technicalSummary: 'HTTP $status code=${error.code ?? ''}',
          endpoint: context.endpoint,
          httpStatusCode: status,
        );
      }

      if (status != null && status >= 500 && status <= 599) {
        return LicenseUiError(
          type: LicenseErrorType.serverDown,
          title: 'Servidor no disponible',
          message:
              'Estamos teniendo un problema temporal en el servidor. Intenta de nuevo en unos minutos.',
          supportCode: 'LIC-SRV-05',
          actions: const [
            LicenseAction.retry,
            LicenseAction.openWhatsapp,
            LicenseAction.copySupportCode,
          ],
          technicalSummary: 'HTTP $status code=${error.code ?? ''}',
          endpoint: context.endpoint,
          httpStatusCode: status,
        );
      }

      final code = (error.code ?? context.backendCode ?? '').toUpperCase();
      if (code == 'EXPIRED') {
        return LicenseUiError(
          type: LicenseErrorType.expired,
          title: 'Licencia vencida',
          message:
              'Tu licencia está vencida. Escríbenos por WhatsApp y te ayudamos a renovarla.',
          supportCode: 'LIC-EXP-01',
          actions: const [
            LicenseAction.openWhatsapp,
            LicenseAction.copySupportCode,
          ],
          technicalSummary: 'Expired (backend code=$code)',
          endpoint: context.endpoint,
          httpStatusCode: status,
        );
      }

      if (code == 'BLOCKED') {
        return LicenseUiError(
          type: LicenseErrorType.unauthorized,
          title: 'Cuenta bloqueada',
          message:
              'Tu cuenta está bloqueada. Escríbenos por WhatsApp y lo resolvemos contigo.',
          supportCode: 'LIC-BLK-01',
          actions: const [
            LicenseAction.openWhatsapp,
            LicenseAction.copySupportCode,
          ],
          technicalSummary: 'Blocked (backend code=$code)',
          endpoint: context.endpoint,
          httpStatusCode: status,
        );
      }

      final msg = error.message.toLowerCase();
      if (msg.contains('archivo de licencia') ||
          msg.contains('firma') ||
          msg.contains('no corresponde')) {
        return LicenseUiError(
          type: LicenseErrorType.invalidLicenseFile,
          title: 'Archivo de licencia inválido',
          message:
              'El archivo seleccionado no es válido para este negocio o dispositivo. Verifica que sea el archivo correcto e intenta de nuevo.',
          supportCode: 'LIC-FILE-02',
          actions: const [
            LicenseAction.retry,
            LicenseAction.openWhatsapp,
            LicenseAction.copySupportCode,
          ],
          technicalSummary: 'Invalid offline file (${error.code ?? '-'})',
          endpoint: context.endpoint,
          httpStatusCode: status,
        );
      }

      return LicenseUiError(
        type: LicenseErrorType.unknown,
        title: 'No se pudo completar la verificación',
        message:
            'Ocurrió un inconveniente validando la licencia. Intenta de nuevo.',
        supportCode: 'LIC-UNK-01',
        actions: const [
          LicenseAction.retry,
          LicenseAction.openWhatsapp,
          LicenseAction.copySupportCode,
        ],
        technicalSummary: 'LicenseApiException($status ${error.code ?? ''})',
        endpoint: context.endpoint,
        httpStatusCode: status,
      );
    }

    return _fromMessage(
      error.toString(),
      context: context,
      technical: error.runtimeType.toString(),
      status: context.httpStatusCode,
    );
  }

  static LicenseUiError _fromMessage(
    String message, {
    required LicenseErrorContext context,
    required String technical,
    int? status,
  }) {
    final msg = message.toLowerCase();

    if (msg.contains('ssl') ||
        msg.contains('certificate') ||
        msg.contains('certificado') ||
        msg.contains('handshake')) {
      return LicenseUiError(
        type: LicenseErrorType.ssl,
        title: 'Conexión segura falló',
        message:
            'Tu computadora no pudo validar la conexión segura. Revisa la fecha y hora de Windows y vuelve a intentar.',
        supportCode: 'LIC-SSL-01',
        actions: const [
          LicenseAction.retry,
          LicenseAction.verifyConnection,
          LicenseAction.openWhatsapp,
          LicenseAction.copySupportCode,
        ],
        technicalSummary: technical,
        endpoint: context.endpoint,
        httpStatusCode: status,
      );
    }

    if (status != null && status >= 500 && status <= 599) {
      return LicenseUiError(
        type: LicenseErrorType.serverDown,
        title: 'Servidor no disponible',
        message:
            'Estamos teniendo un problema temporal en el servidor. Intenta de nuevo en unos minutos.',
        supportCode: 'LIC-SRV-05',
        actions: const [
          LicenseAction.retry,
          LicenseAction.openWhatsapp,
          LicenseAction.copySupportCode,
        ],
        technicalSummary: technical,
        endpoint: context.endpoint,
        httpStatusCode: status,
      );
    }

    return LicenseUiError(
      type: LicenseErrorType.unknown,
      title: 'No se pudo completar la verificación',
      message:
          'Ocurrió un inconveniente validando la licencia. Intenta de nuevo.',
      supportCode: 'LIC-UNK-01',
      actions: const [
        LicenseAction.retry,
        LicenseAction.openWhatsapp,
        LicenseAction.copySupportCode,
      ],
      technicalSummary: technical,
      endpoint: context.endpoint,
      httpStatusCode: status,
    );
  }
}
