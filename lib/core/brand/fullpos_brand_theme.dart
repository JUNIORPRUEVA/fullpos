import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Tema corporativo FIJO de FULLPOS.
///
/// Regla: NO depende de configuración del cliente.
class FullposBrandTheme {
  static const String appName = 'FULLPOS';

  /// Logo oficial FULLPOS (asset). Debe ser fijo.
  static const String logoAsset = 'assets/imagen/lonchericon.png';

  static const Color primary = AppColors.gold;
  static const Color secondary = AppColors.teal900;
  static const Color background = AppColors.brandBlueDark;
  static const Color surface = AppColors.surfaceDark;

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.brandBlueDark, AppColors.brandBlue, AppColors.bgDark],
    stops: [0.0, 0.68, 1.0],
  );

  static ThemeData get theme {
    const scheme = ColorScheme.dark(
      primary: primary,
      secondary: secondary,
      surface: surface,
      onPrimary: Colors.black,
      onSecondary: Colors.white,
      onSurface: AppColors.textLight,
      error: AppColors.error,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: AppColors.textLight,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: Colors.black.withOpacity(0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: primary.withOpacity(0.14)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textLight,
          side: BorderSide(color: primary.withOpacity(0.45)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceDarkVariant.withOpacity(0.55),
        labelStyle: TextStyle(color: AppColors.textLight.withOpacity(0.85)),
        hintStyle: TextStyle(color: AppColors.textLight.withOpacity(0.55)),
        prefixIconColor: primary,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: primary.withOpacity(0.18)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: primary),
    );
  }
}

/// Wrapper para aplicar el tema corporativo fijo a una sub-árbol.
class FullposBrandScope extends StatelessWidget {
  final Widget child;

  const FullposBrandScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Theme(data: FullposBrandTheme.theme, child: child);
  }
}
