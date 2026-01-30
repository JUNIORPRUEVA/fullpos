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

class SalesDetailGradientTheme extends ThemeExtension<SalesDetailGradientTheme> {
  const SalesDetailGradientTheme({
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
  SalesDetailGradientTheme copyWith({Color? start, Color? mid, Color? end}) {
    return SalesDetailGradientTheme(
      start: start ?? this.start,
      mid: mid ?? this.mid,
      end: end ?? this.end,
    );
  }

  @override
  SalesDetailGradientTheme lerp(
    ThemeExtension<SalesDetailGradientTheme>? other,
    double t,
  ) {
    if (other is! SalesDetailGradientTheme) return this;
    return SalesDetailGradientTheme(
      start: Color.lerp(start, other.start, t) ?? start,
      mid: Color.lerp(mid, other.mid, t) ?? mid,
      end: Color.lerp(end, other.end, t) ?? end,
    );
  }
}

class SalesDetailTextTheme extends ThemeExtension<SalesDetailTextTheme> {
  const SalesDetailTextTheme({required this.textColor});

  final Color textColor;

  @override
  SalesDetailTextTheme copyWith({Color? textColor}) {
    return SalesDetailTextTheme(textColor: textColor ?? this.textColor);
  }

  @override
  SalesDetailTextTheme lerp(
    ThemeExtension<SalesDetailTextTheme>? other,
    double t,
  ) {
    if (other is! SalesDetailTextTheme) return this;
    return SalesDetailTextTheme(
      textColor: Color.lerp(textColor, other.textColor, t) ?? textColor,
    );
  }
}
