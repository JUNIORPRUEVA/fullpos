import 'package:flutter/material.dart';

/// Tema para controles especificos de la pagina de ventas.
///
/// Varios colores pueden venir transparentes (alpha=0) para indicar
/// "usa el fallback del Theme/ColorScheme".
class SalesPageTheme extends ThemeExtension<SalesPageTheme> {
  const SalesPageTheme({
    required this.controlBarBackgroundColor,
    required this.controlBarContentBackgroundColor,
    required this.controlBarBorderColor,
    required this.controlBarTextColor,
    required this.controlBarDropdownBackgroundColor,
    required this.controlBarDropdownBorderColor,
    required this.controlBarDropdownTextColor,
    required this.controlBarPopupBackgroundColor,
    required this.controlBarPopupTextColor,
    required this.controlBarPopupSelectedBackgroundColor,
    required this.controlBarPopupSelectedTextColor,
    required this.footerButtonsBackgroundColor,
    required this.footerButtonsTextColor,
    required this.footerButtonsBorderColor,
  });

  final Color controlBarBackgroundColor;
  final Color controlBarContentBackgroundColor;
  final Color controlBarBorderColor;
  final Color controlBarTextColor;
  final Color controlBarDropdownBackgroundColor;
  final Color controlBarDropdownBorderColor;
  final Color controlBarDropdownTextColor;
  final Color controlBarPopupBackgroundColor;
  final Color controlBarPopupTextColor;
  final Color controlBarPopupSelectedBackgroundColor;
  final Color controlBarPopupSelectedTextColor;
  final Color footerButtonsBackgroundColor;
  final Color footerButtonsTextColor;
  final Color footerButtonsBorderColor;

  @override
  SalesPageTheme copyWith({
    Color? controlBarBackgroundColor,
    Color? controlBarContentBackgroundColor,
    Color? controlBarBorderColor,
    Color? controlBarTextColor,
    Color? controlBarDropdownBackgroundColor,
    Color? controlBarDropdownBorderColor,
    Color? controlBarDropdownTextColor,
    Color? controlBarPopupBackgroundColor,
    Color? controlBarPopupTextColor,
    Color? controlBarPopupSelectedBackgroundColor,
    Color? controlBarPopupSelectedTextColor,
    Color? footerButtonsBackgroundColor,
    Color? footerButtonsTextColor,
    Color? footerButtonsBorderColor,
  }) {
    return SalesPageTheme(
      controlBarBackgroundColor:
          controlBarBackgroundColor ?? this.controlBarBackgroundColor,
      controlBarContentBackgroundColor:
          controlBarContentBackgroundColor ??
          this.controlBarContentBackgroundColor,
      controlBarBorderColor:
          controlBarBorderColor ?? this.controlBarBorderColor,
      controlBarTextColor: controlBarTextColor ?? this.controlBarTextColor,
      controlBarDropdownBackgroundColor:
          controlBarDropdownBackgroundColor ??
          this.controlBarDropdownBackgroundColor,
      controlBarDropdownBorderColor:
          controlBarDropdownBorderColor ?? this.controlBarDropdownBorderColor,
      controlBarDropdownTextColor:
          controlBarDropdownTextColor ?? this.controlBarDropdownTextColor,
      controlBarPopupBackgroundColor:
          controlBarPopupBackgroundColor ?? this.controlBarPopupBackgroundColor,
      controlBarPopupTextColor:
          controlBarPopupTextColor ?? this.controlBarPopupTextColor,
      controlBarPopupSelectedBackgroundColor:
          controlBarPopupSelectedBackgroundColor ??
          this.controlBarPopupSelectedBackgroundColor,
      controlBarPopupSelectedTextColor:
          controlBarPopupSelectedTextColor ??
          this.controlBarPopupSelectedTextColor,
      footerButtonsBackgroundColor:
          footerButtonsBackgroundColor ?? this.footerButtonsBackgroundColor,
      footerButtonsTextColor:
          footerButtonsTextColor ?? this.footerButtonsTextColor,
      footerButtonsBorderColor:
          footerButtonsBorderColor ?? this.footerButtonsBorderColor,
    );
  }

  @override
  SalesPageTheme lerp(ThemeExtension<SalesPageTheme>? other, double t) {
    if (other is! SalesPageTheme) return this;
    return SalesPageTheme(
      controlBarBackgroundColor:
          Color.lerp(
            controlBarBackgroundColor,
            other.controlBarBackgroundColor,
            t,
          ) ??
          controlBarBackgroundColor,
      controlBarContentBackgroundColor:
          Color.lerp(
            controlBarContentBackgroundColor,
            other.controlBarContentBackgroundColor,
            t,
          ) ??
          controlBarContentBackgroundColor,
      controlBarBorderColor:
          Color.lerp(controlBarBorderColor, other.controlBarBorderColor, t) ??
          controlBarBorderColor,
      controlBarTextColor:
          Color.lerp(controlBarTextColor, other.controlBarTextColor, t) ??
          controlBarTextColor,
      controlBarDropdownBackgroundColor:
          Color.lerp(
            controlBarDropdownBackgroundColor,
            other.controlBarDropdownBackgroundColor,
            t,
          ) ??
          controlBarDropdownBackgroundColor,
      controlBarDropdownBorderColor:
          Color.lerp(
            controlBarDropdownBorderColor,
            other.controlBarDropdownBorderColor,
            t,
          ) ??
          controlBarDropdownBorderColor,
      controlBarDropdownTextColor:
          Color.lerp(
            controlBarDropdownTextColor,
            other.controlBarDropdownTextColor,
            t,
          ) ??
          controlBarDropdownTextColor,
      controlBarPopupBackgroundColor:
          Color.lerp(
            controlBarPopupBackgroundColor,
            other.controlBarPopupBackgroundColor,
            t,
          ) ??
          controlBarPopupBackgroundColor,
      controlBarPopupTextColor:
          Color.lerp(
            controlBarPopupTextColor,
            other.controlBarPopupTextColor,
            t,
          ) ??
          controlBarPopupTextColor,
      controlBarPopupSelectedBackgroundColor:
          Color.lerp(
            controlBarPopupSelectedBackgroundColor,
            other.controlBarPopupSelectedBackgroundColor,
            t,
          ) ??
          controlBarPopupSelectedBackgroundColor,
      controlBarPopupSelectedTextColor:
          Color.lerp(
            controlBarPopupSelectedTextColor,
            other.controlBarPopupSelectedTextColor,
            t,
          ) ??
          controlBarPopupSelectedTextColor,
      footerButtonsBackgroundColor:
          Color.lerp(
            footerButtonsBackgroundColor,
            other.footerButtonsBackgroundColor,
            t,
          ) ??
          footerButtonsBackgroundColor,
      footerButtonsTextColor:
          Color.lerp(footerButtonsTextColor, other.footerButtonsTextColor, t) ??
          footerButtonsTextColor,
      footerButtonsBorderColor:
          Color.lerp(
            footerButtonsBorderColor,
            other.footerButtonsBorderColor,
            t,
          ) ??
          footerButtonsBorderColor,
    );
  }
}
