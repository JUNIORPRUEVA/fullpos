import 'package:flutter/foundation.dart';

enum AppErrorType {
  network,
  timeout,
  database,
  validation,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  server,
  unknown,
}

@immutable
class AppException implements Exception {
  const AppException({
    required this.type,
    required this.messageUser,
    required this.messageDev,
    this.code,
    this.originalError,
    this.stackTrace,
  });

  final AppErrorType type;
  final String? code;
  final String messageUser;
  final String messageDev;
  final Object? originalError;
  final StackTrace? stackTrace;

  AppException copyWith({
    AppErrorType? type,
    String? code,
    String? messageUser,
    String? messageDev,
    Object? originalError,
    StackTrace? stackTrace,
  }) {
    return AppException(
      type: type ?? this.type,
      code: code ?? this.code,
      messageUser: messageUser ?? this.messageUser,
      messageDev: messageDev ?? this.messageDev,
      originalError: originalError ?? this.originalError,
      stackTrace: stackTrace ?? this.stackTrace,
    );
  }

  @override
  String toString() => 'AppException($type, code=$code, dev=$messageDev)';
}

