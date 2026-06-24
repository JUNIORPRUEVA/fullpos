import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'app_exception.dart';

class ErrorMapper {
  ErrorMapper._();

  static AppException map(
    Object error, [
    StackTrace? stackTrace,
    String? module,
  ]) {
    if (error is AppException) {
      return error.stackTrace == null && stackTrace != null
          ? error.copyWith(stackTrace: stackTrace)
          : error;
    }

    final st = stackTrace ?? StackTrace.current;
    final devPrefix = module == null ? '' : '[$module] ';

    if (error is SocketException) {
      return AppException(
        type: AppErrorType.network,
        messageUser:
            'No hay conexión a internet. Revisa tu conexión y vuelve a intentar.',
        messageDev: '${devPrefix}SocketException: ${error.message}',
        originalError: error,
        stackTrace: st,
      );
    }

    if (error is TimeoutException) {
      return AppException(
        type: AppErrorType.timeout,
        messageUser:
            'La operación está tomando demasiado tiempo. Verifica tu conexión e intenta de nuevo.',
        messageDev: '${devPrefix}TimeoutException: ${error.message}',
        originalError: error,
        stackTrace: st,
      );
    }

    if (error is FormatException) {
      return AppException(
        type: AppErrorType.validation,
        messageUser:
            'No se pudo procesar la información. Verifica los datos e intenta de nuevo.',
        messageDev: '${devPrefix}FormatException: ${error.message}',
        originalError: error,
        stackTrace: st,
      );
    }

    if (error is ArgumentError) {
      return AppException(
        type: AppErrorType.validation,
        messageUser: 'Verifica los datos e intenta de nuevo.',
        messageDev: '${devPrefix}ArgumentError: ${error.message}',
        originalError: error,
        stackTrace: st,
      );
    }

    if (error is DatabaseException) {
      final msg = error.toString().toLowerCase();
      if (msg.contains('unique constraint failed') &&
          (msg.contains('users.username') || msg.contains('users.user'))) {
        return AppException(
          type: AppErrorType.validation,
          messageUser: 'Ese nombre de usuario ya existe. Elige otro.',
          messageDev:
              '${devPrefix}DatabaseException(unique): ${error.toString()}',
          originalError: error,
          stackTrace: st,
        );
      }
      return AppException(
        type: AppErrorType.database,
        messageUser:
            'No se pudo acceder a la base de datos. Reintenta y, si persiste, reinicia la app.',
        messageDev: '${devPrefix}DatabaseException: ${error.toString()}',
        originalError: error,
        stackTrace: st,
      );
    }

    if (error is FileSystemException) {
      return AppException(
        type: AppErrorType.unknown,
        messageUser: 'No se pudo acceder a un archivo necesario. Reintenta.',
        messageDev: '${devPrefix}FileSystemException: ${error.message}',
        originalError: error,
        stackTrace: st,
      );
    }

    if (error is HttpException) {
      return AppException(
        type: AppErrorType.server,
        messageUser:
            'No se pudo completar la solicitud. Reintenta en unos segundos.',
        messageDev: '${devPrefix}HttpException: ${error.message}',
        originalError: error,
        stackTrace: st,
      );
    }

    if (error is PlatformException) {
      return AppException(
        type: AppErrorType.unknown,
        code: error.code,
        messageUser: 'No se pudo completar la acción. Intenta nuevamente.',
        messageDev:
            '${devPrefix}PlatformException(code=${error.code}, message=${error.message}, details=${error.details})',
        originalError: error,
        stackTrace: st,
      );
    }

    final cashError = _mapCashOperationError(
      error,
      stackTrace: st,
      module: module,
      devPrefix: devPrefix,
    );
    if (cashError != null) return cashError;

    if (error is FlutterErrorDetails) {
      return AppException(
        type: AppErrorType.unknown,
        messageUser:
            'No se pudo completar la acción. Intenta nuevamente o vuelve a la pantalla anterior.',
        messageDev:
            '${devPrefix}FlutterErrorDetails: ${error.exceptionAsString()}',
        originalError: error.exception,
        stackTrace: error.stack ?? st,
      );
    }

    if (error is AssertionError) {
      return AppException(
        type: AppErrorType.unknown,
        messageUser:
            'No se pudo completar la acción. Intenta nuevamente o vuelve a la pantalla anterior.',
        messageDev: '${devPrefix}AssertionError: ${error.message ?? error}',
        originalError: error,
        stackTrace: st,
      );
    }

    return AppException(
      type: AppErrorType.unknown,
      messageUser:
          'No se pudo completar la acción. Intenta nuevamente. Si continúa, contacta a soporte.',
      messageDev: '$devPrefix${error.runtimeType}: $error',
      originalError: error,
      stackTrace: st,
    );
  }

  static AppException? _mapCashOperationError(
    Object error, {
    required StackTrace stackTrace,
    required String? module,
    required String devPrefix,
  }) {
    final moduleKey = module?.trim().toLowerCase() ?? '';
    final isCashModule =
        moduleKey.startsWith('cash/') || moduleKey == 'auth/logout';
    if (!isCashModule) return null;

    final raw = error.toString();
    final msg = raw.toLowerCase();

    AppException build({
      required AppErrorType type,
      required String code,
      required String messageUser,
    }) {
      return AppException(
        type: type,
        code: code,
        messageUser: messageUser,
        messageDev: '$devPrefix${error.runtimeType}: $raw',
        originalError: error,
        stackTrace: stackTrace,
      );
    }

    if (msg.contains('múltiples turnos abiertos') ||
        msg.contains('multiples turnos abiertos') ||
        msg.contains('varios turnos abiertos')) {
      return build(
        type: AppErrorType.conflict,
        code: 'cash_duplicate_open_shifts',
        messageUser:
            'Hay más de un turno abierto para este usuario. Revisa el historial de caja o contacta a soporte para corregirlo antes de continuar.',
      );
    }

    if (msg.contains('otra sesión activa') ||
        msg.contains('otra sesion activa') ||
        msg.contains('existen turnos abiertos') ||
        msg.contains('todavía existe otra sesión') ||
        msg.contains('todavia existe otra sesion')) {
      return build(
        type: AppErrorType.conflict,
        code: 'cash_other_open_shift',
        messageUser:
            'No se puede cerrar la caja completa porque todavía hay otro turno abierto. Cierra primero los turnos pendientes o deja la caja abierta.',
      );
    }

    if (msg.contains('pertenece a otro usuario') ||
        msg.contains('pertenece a otro cajero')) {
      return build(
        type: AppErrorType.forbidden,
        code: 'cash_shift_owner_mismatch',
        messageUser:
            'Este turno pertenece a otro usuario. Inicia sesión con el cajero correcto o pide a un supervisor que lo revise.',
      );
    }

    if (msg.contains('no existe una sesión activa') ||
        msg.contains('no existe una sesion activa') ||
        msg.contains('turno no encontrado') ||
        msg.contains('no hay caja diaria abierta') ||
        msg.contains('no hay caja abierta')) {
      return build(
        type: AppErrorType.notFound,
        code: 'cash_shift_not_available',
        messageUser:
            'No encontramos un turno abierto para completar esta acción. Actualiza la pantalla y vuelve a intentarlo.',
      );
    }

    if (msg.contains('identificar al usuario') ||
        msg.contains('inicie sesión') ||
        msg.contains('inicie sesion')) {
      return build(
        type: AppErrorType.unauthorized,
        code: 'cash_user_not_identified',
        messageUser:
            'No se pudo confirmar el usuario actual. Cierra sesión, vuelve a iniciar y reintenta.',
      );
    }

    if (moduleKey == 'cash/open') {
      return build(
        type: AppErrorType.conflict,
        code: 'cash_open_failed',
        messageUser:
            'No se pudo abrir la caja. Verifica si ya existe un turno abierto y vuelve a intentarlo.',
      );
    }

    if (moduleKey == 'cash/close') {
      return build(
        type: AppErrorType.conflict,
        code: 'cash_close_failed',
        messageUser:
            'No se pudo cerrar el turno. Verifica que la caja esté abierta y que este turno pertenezca al usuario actual.',
      );
    }

    if (moduleKey == 'cash/summary' ||
        moduleKey == 'cash/refunds' ||
        moduleKey == 'cash/movements' ||
        moduleKey == 'cash/category_summary') {
      return build(
        type: AppErrorType.database,
        code: 'cash_summary_failed',
        messageUser:
            'No se pudo cargar el resumen del turno. Actualiza la pantalla e intenta nuevamente.',
      );
    }

    return null;
  }
}
