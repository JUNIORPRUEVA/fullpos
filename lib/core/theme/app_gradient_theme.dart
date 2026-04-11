import 'package:flutter/material.dart';

class AppGradientTheme extends ThemeExtension<AppGradientTheme> {
  const AppGradientTheme({
    required this.start,
    required this.mid,
    required this.end,
  });

  final Color start;
  final Color mid;
  final Color end;

  LinearGradient get backgroundGradient => LinearGradient(
        colors: [start, mid, end],
        stops: const [0.0, 0.7, 1.0],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  @override
  AppGradientTheme copyWith({Color? start, Color? mid, Color? end}) {
    return AppGradientTheme(
      start: start ?? this.start,
      mid: mid ?? this.mid,
      end: end ?? this.end,
    );
  }

  @override
  AppGradientTheme lerp(ThemeExtension<AppGradientTheme>? other, double t) {
    if (other is! AppGradientTheme) return this;
    return AppGradientTheme(
      start: Color.lerp(start, other.start, t) ?? start,
      mid: Color.lerp(mid, other.mid, t) ?? mid,
      end: Color.lerp(end, other.end, t) ?? end,
    );
  }
}

class SalesDetailTheme extends ThemeExtension<SalesDetailTheme> {
  const SalesDetailTheme({
    required this.backgroundColor,
    required this.textColor,
  });

  final Color backgroundColor;
  final Color textColor;

  @override
  SalesDetailTheme copyWith({Color? backgroundColor, Color? textColor}) {
    return SalesDetailTheme(
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
    );
  }

  @override
  SalesDetailTheme lerp(ThemeExtension<SalesDetailTheme>? other, double t) {
    if (other is! SalesDetailTheme) return this;
    return SalesDetailTheme(
      backgroundColor:
          Color.lerp(backgroundColor, other.backgroundColor, t) ??
          backgroundColor,
      textColor: Color.lerp(textColor, other.textColor, t) ?? textColor,
    );
  }
}
