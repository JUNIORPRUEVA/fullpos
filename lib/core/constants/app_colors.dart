import 'package:flutter/material.dart';

/// Paleta premium FULLPOS (azul profundo + acento turquesa)
class AppColors {
  AppColors._();

  // Azul de marca (nuevos valores)
  static const Color teal = Color(0xFF0F2F4F); // Alias principal
  static const Color teal900 = Color(0xFF0A1E33);
  static const Color teal800 = Color(0xFF0F2F4F);
  static const Color teal700 = Color(0xFF16426A);
  static const Color teal600 = Color(0xFF1E5A88);
  static const Color teal500 = Color(0xFF2774A6);
  static const Color teal400 = Color(0xFF3B8FC4);
  static const Color teal300 = Color(0xFF6BB3DD);

  // Acento turquesa
  static const Color gold = Color(0xFF24D3BC);
  static const Color goldBright = Color(0xFF43E6D4);
  static const Color goldSoft = Color(0xFF8DEFE6);
  static const Color goldDark = Color(0xFF149A88);

  // Backgrounds claros
  static const Color bgLight = Color(0xFFE8EEF6);
  static const Color bgLightAlt = Color(0xFFE1E8F1);

  // Superficies claras
  static const Color surfaceLight = Color(0xFFF9FCFF);
  static const Color surfaceLightVariant = Color(0xFFF0F5FB);
  static const Color surfaceLightBorder = Color(0xFFD3DCE7);

  // Backgrounds oscuros (para sidebar/topbar)
  static const Color bgDark = Color(0xFF0A1726);
  static const Color surfaceDark = Color(0xFF11263A);
  static const Color surfaceDarkVariant = Color(0xFF183653);

  // Textos en fondos claros
  static const Color textDark = Color(0xFF111827);
  static const Color textDarkSecondary = Color(0xFF4B5563);
  static const Color textDarkMuted = Color(0xFF9CA3AF);

  // Textos en fondos oscuros
  static const Color textLight = Color(0xFFFFFFFF);
  static const Color textLightSecondary = Color(0xFFE5E7EB);
  static const Color textLightMuted = Color(0xFFB7C5D3);

  // Aliases para compatibilidad (legacy)
  static const Color textPrimary = textLight;
  static const Color textSecondary = textLightSecondary;
  static const Color textMuted = textLightMuted;
  static const Color surface = surfaceDark;
  static const Color surfaceVariant = surfaceDarkVariant;

  // Estados
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFFD1FAE5);
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoLight = Color(0xFFDBEAFE);

  // Executive background gradient (dark blue -> soft white).
  static const Color executiveDark = Color(0xFF0A1F44);
  static const Color executiveMid = Color(0xFF153A75);
  static const Color executiveLight = Color(0xFFE8EEF6);
}

class AppGradients {
  AppGradients._();

  static const LinearGradient executive = LinearGradient(
    colors: [
      AppColors.executiveDark,
      AppColors.executiveMid,
      AppColors.executiveLight,
    ],
    stops: [0.0, 0.7, 1.0],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
