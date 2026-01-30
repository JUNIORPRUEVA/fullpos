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
            'No hay conexión a internet. Revisa tu red y reintenta.',
        messageDev: '${devPrefix}SocketException: ${error.message}',
        originalError: error,
        stackTrace: st,
      );
    }

    if (error is TimeoutException) {
      return AppException(
        type: AppErrorType.timeout,
        messageUser: 'La operación tardó demasiado. Reintenta.',
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
          messageDev: '${devPrefix}DatabaseException(unique): ${error.toString()}',
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
        messageUser:
            'No se pudo acceder a un archivo necesario. Reintenta.',
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
        messageUser:
            'Ocurrió un problema al usar una función del sistema. Reintenta.',
        messageDev:
            '${devPrefix}PlatformException(code=${error.code}, message=${error.message}, details=${error.details})',
        originalError: error,
        stackTrace: st,
      );
    }

    if (error is FlutterErrorDetails) {
      return AppException(
        type: AppErrorType.unknown,
        messageUser:
            'Ups… ocurrió un problema. Reintenta o vuelve atrás.',
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
            'Ups… ocurrió un problema. Reintenta o vuelve atrás.',
        messageDev: '${devPrefix}AssertionError: ${error.message ?? error}',
        originalError: error,
        stackTrace: st,
      );
    }

    return AppException(
      type: AppErrorType.unknown,
      messageUser: 'Ups… ocurrió un problema. Reintenta.',
      messageDev: '$devPrefix${error.runtimeType}: $error',
      originalError: error,
      stackTrace: st,
    );
  }
}
