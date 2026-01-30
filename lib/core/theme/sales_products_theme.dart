import 'package:flutter/material.dart';

/// Tema para la pagina de ventas (grid y tarjetas de productos).
///
/// Nota: varios colores pueden venir transparentes (alpha=0) para indicar
/// "usa el fallback del ColorScheme".
class SalesProductsTheme extends ThemeExtension<SalesProductsTheme> {
  const SalesProductsTheme({
    required this.gridBackgroundColor,
    required this.cardBackgroundColor,
    required this.cardBorderColor,
    required this.cardTextColor,
    required this.cardAltBackgroundColor,
    required this.cardAltBorderColor,
    required this.cardAltTextColor,
    required this.priceColor,
  });

  final Color gridBackgroundColor;
  final Color cardBackgroundColor;
  final Color cardBorderColor;
  final Color cardTextColor;
  final Color cardAltBackgroundColor;
  final Color cardAltBorderColor;
  final Color cardAltTextColor;
  final Color priceColor;

  @override
  SalesProductsTheme copyWith({
    Color? gridBackgroundColor,
    Color? cardBackgroundColor,
    Color? cardBorderColor,
    Color? cardTextColor,
    Color? cardAltBackgroundColor,
    Color? cardAltBorderColor,
    Color? cardAltTextColor,
    Color? priceColor,
  }) {
    return SalesProductsTheme(
      gridBackgroundColor: gridBackgroundColor ?? this.gridBackgroundColor,
      cardBackgroundColor: cardBackgroundColor ?? this.cardBackgroundColor,
      cardBorderColor: cardBorderColor ?? this.cardBorderColor,
      cardTextColor: cardTextColor ?? this.cardTextColor,
      cardAltBackgroundColor:
          cardAltBackgroundColor ?? this.cardAltBackgroundColor,
      cardAltBorderColor: cardAltBorderColor ?? this.cardAltBorderColor,
      cardAltTextColor: cardAltTextColor ?? this.cardAltTextColor,
      priceColor: priceColor ?? this.priceColor,
    );
  }

  @override
  SalesProductsTheme lerp(ThemeExtension<SalesProductsTheme>? other, double t) {
    if (other is! SalesProductsTheme) return this;
    return SalesProductsTheme(
      gridBackgroundColor:
          Color.lerp(gridBackgroundColor, other.gridBackgroundColor, t) ??
          gridBackgroundColor,
      cardBackgroundColor:
          Color.lerp(cardBackgroundColor, other.cardBackgroundColor, t) ??
          cardBackgroundColor,
      cardBorderColor:
          Color.lerp(cardBorderColor, other.cardBorderColor, t) ??
          cardBorderColor,
      cardTextColor:
          Color.lerp(cardTextColor, other.cardTextColor, t) ?? cardTextColor,
      cardAltBackgroundColor:
          Color.lerp(cardAltBackgroundColor, other.cardAltBackgroundColor, t) ??
          cardAltBackgroundColor,
      cardAltBorderColor:
          Color.lerp(cardAltBorderColor, other.cardAltBorderColor, t) ??
          cardAltBorderColor,
      cardAltTextColor:
          Color.lerp(cardAltTextColor, other.cardAltTextColor, t) ??
          cardAltTextColor,
      priceColor: Color.lerp(priceColor, other.priceColor, t) ?? priceColor,
    );
  }
}
