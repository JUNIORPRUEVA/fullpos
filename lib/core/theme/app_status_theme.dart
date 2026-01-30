import 'package:flutter/material.dart';

class AppStatusTheme extends ThemeExtension<AppStatusTheme> {
  const AppStatusTheme({
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
  });

  final Color success;
  final Color warning;
  final Color error;
  final Color info;

  @override
  AppStatusTheme copyWith({
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
  }) {
    return AppStatusTheme(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
    );
  }

  @override
  AppStatusTheme lerp(ThemeExtension<AppStatusTheme>? other, double t) {
    if (other is! AppStatusTheme) return this;
    return AppStatusTheme(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      error: Color.lerp(error, other.error, t) ?? error,
      info: Color.lerp(info, other.info, t) ?? info,
    );
  }
}
