import 'package:flutter/material.dart';

/// Paleta personalizada basada en el nuevo logo Lonchericon
class AppColors {
  AppColors._();

  // Marca principal (azul intenso)
  static const Color brandBlueDark = Color(0xFF030A17);
  static const Color brandBlue = Color(0xFF0D5EC3);
  static const Color brandBlueLight = Color(0xFF3F85FF);
  static const Color brandBlueAccent = Color(0xFF1A7FFF);

  // Aliados legacy (teal/gold) para evitar romper referencias
  static const Color teal = brandBlue;
  static const Color teal900 = brandBlueDark;
  static const Color teal800 = brandBlueDark;
  static const Color teal700 = brandBlue;
  static const Color teal600 = brandBlueLight;
  static const Color teal500 = brandBlueAccent;
  static const Color teal400 = brandBlueLight;
  static const Color teal300 = Color(0xFF6EA9FF);

  static const Color gold = brandBlueAccent;
  static const Color goldBright = Color(0xFF6EC2FF);
  static const Color goldSoft = Color(0xFFB1D9FF);
  static const Color goldDark = brandBlueDark;

  // Fondo global
  static const Color bgLight = brandBlue;
  static const Color bgLightAlt = Color(0xFF0B2F82);

  // Superficies claras (tarjetas, paneles blancos)
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceLightVariant = Color(0xFFF2F5FB);
  static const Color surfaceLightBorder = Color(0xFFDCE3EE);

  // Superficies oscuras (nav, paneles negros)
  static const Color bgDark = Color(0xFF010101);
  static const Color surfaceDark = Color(0xFF0F0F0F);
  static const Color surfaceDarkVariant = Color(0xFF1A1A1A);

  // Textos
  static const Color textDark = Color(0xFF111827);
  static const Color textDarkSecondary = Color(0xFF4B5563);
  static const Color textDarkMuted = Color(0xFF6B7280);
  static const Color textLight = Color(0xFFFFFFFF);
  static const Color textLightSecondary = Color(0xFFE5E7EB);
  static const Color textLightMuted = Color(0xFFB7C5D3);

  // Legacy
  static const Color textPrimary = textDark;
  static const Color textSecondary = textDarkSecondary;
  static const Color textMuted = textDarkMuted;
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

  // Gradiente ejecutivo (brand blue -> blanco suave)
  static const Color executiveDark = brandBlueDark;
  static const Color executiveMid = brandBlue;
  static const Color executiveLight = surfaceLight;
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
