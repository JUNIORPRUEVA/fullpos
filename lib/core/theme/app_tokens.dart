import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Tokens que describen decisiones visuales compartidas entre pantallas.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  final Color panelBackground;
  final Color panelBorder;
  final Color cardBackground;
  final Color cardBorder;
  final Color sidebarBackground;
  final Color sidebarBorder;
  final Color sidebarText;
  final Color controlBarBackground;
  final Color controlBarBorder;
  final Color controlBarText;
  final Color buttonPrimary;
  final Color buttonSecondary;
  final Color buttonDanger;
  final Color searchFieldBackground;
  final Color searchFieldText;
  final Color searchFieldIcon;
  final Color tileHover;
  final Color outline;

  const AppTokens({
    required this.panelBackground,
    required this.panelBorder,
    required this.cardBackground,
    required this.cardBorder,
    required this.sidebarBackground,
    required this.sidebarBorder,
    required this.sidebarText,
    required this.controlBarBackground,
    required this.controlBarBorder,
    required this.controlBarText,
    required this.buttonPrimary,
    required this.buttonSecondary,
    required this.buttonDanger,
    required this.searchFieldBackground,
    required this.searchFieldText,
    required this.searchFieldIcon,
    required this.tileHover,
    required this.outline,
  });

  @override
  AppTokens copyWith({
    Color? panelBackground,
    Color? panelBorder,
    Color? cardBackground,
    Color? cardBorder,
    Color? sidebarBackground,
    Color? sidebarBorder,
    Color? sidebarText,
    Color? controlBarBackground,
    Color? controlBarBorder,
    Color? controlBarText,
    Color? buttonPrimary,
    Color? buttonSecondary,
    Color? buttonDanger,
    Color? searchFieldBackground,
    Color? searchFieldText,
    Color? searchFieldIcon,
    Color? tileHover,
    Color? outline,
  }) {
    return AppTokens(
      panelBackground: panelBackground ?? this.panelBackground,
      panelBorder: panelBorder ?? this.panelBorder,
      cardBackground: cardBackground ?? this.cardBackground,
      cardBorder: cardBorder ?? this.cardBorder,
      sidebarBackground: sidebarBackground ?? this.sidebarBackground,
      sidebarBorder: sidebarBorder ?? this.sidebarBorder,
      sidebarText: sidebarText ?? this.sidebarText,
      controlBarBackground: controlBarBackground ?? this.controlBarBackground,
      controlBarBorder: controlBarBorder ?? this.controlBarBorder,
      controlBarText: controlBarText ?? this.controlBarText,
      buttonPrimary: buttonPrimary ?? this.buttonPrimary,
      buttonSecondary: buttonSecondary ?? this.buttonSecondary,
      buttonDanger: buttonDanger ?? this.buttonDanger,
      searchFieldBackground:
          searchFieldBackground ?? this.searchFieldBackground,
      searchFieldText: searchFieldText ?? this.searchFieldText,
      searchFieldIcon: searchFieldIcon ?? this.searchFieldIcon,
      tileHover: tileHover ?? this.tileHover,
      outline: outline ?? this.outline,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) {
      return this;
    }
    return AppTokens(
      panelBackground:
          Color.lerp(panelBackground, other.panelBackground, t) ??
              panelBackground,
      panelBorder:
          Color.lerp(panelBorder, other.panelBorder, t) ?? panelBorder,
      cardBackground:
          Color.lerp(cardBackground, other.cardBackground, t) ??
              cardBackground,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t) ?? cardBorder,
      sidebarBackground: Color.lerp(
            sidebarBackground,
            other.sidebarBackground,
            t,
          ) ??
          sidebarBackground,
      sidebarBorder:
          Color.lerp(sidebarBorder, other.sidebarBorder, t) ?? sidebarBorder,
      sidebarText:
          Color.lerp(sidebarText, other.sidebarText, t) ?? sidebarText,
      controlBarBackground: Color.lerp(
            controlBarBackground,
            other.controlBarBackground,
            t,
          ) ??
          controlBarBackground,
      controlBarBorder:
          Color.lerp(controlBarBorder, other.controlBarBorder, t) ??
              controlBarBorder,
      controlBarText:
          Color.lerp(controlBarText, other.controlBarText, t) ?? controlBarText,
      buttonPrimary:
          Color.lerp(buttonPrimary, other.buttonPrimary, t) ?? buttonPrimary,
      buttonSecondary: Color.lerp(
            buttonSecondary,
            other.buttonSecondary,
            t,
          ) ??
          buttonSecondary,
      buttonDanger:
          Color.lerp(buttonDanger, other.buttonDanger, t) ?? buttonDanger,
      searchFieldBackground: Color.lerp(
            searchFieldBackground,
            other.searchFieldBackground,
            t,
          ) ??
          searchFieldBackground,
      searchFieldText:
          Color.lerp(searchFieldText, other.searchFieldText, t) ??
              searchFieldText,
      searchFieldIcon:
          Color.lerp(searchFieldIcon, other.searchFieldIcon, t) ??
              searchFieldIcon,
      tileHover: Color.lerp(tileHover, other.tileHover, t) ?? tileHover,
      outline: Color.lerp(outline, other.outline, t) ?? outline,
    );
  }

  @override
  int get hashCode => Object.hashAll([
        panelBackground,
        panelBorder,
        cardBackground,
        cardBorder,
        sidebarBackground,
        sidebarBorder,
        sidebarText,
        controlBarBackground,
        controlBarBorder,
        controlBarText,
        buttonPrimary,
        buttonSecondary,
        buttonDanger,
        searchFieldBackground,
        searchFieldText,
        searchFieldIcon,
        tileHover,
        outline,
      ]);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppTokens &&
            panelBackground == other.panelBackground &&
            panelBorder == other.panelBorder &&
            cardBackground == other.cardBackground &&
            cardBorder == other.cardBorder &&
            sidebarBackground == other.sidebarBackground &&
            sidebarBorder == other.sidebarBorder &&
            sidebarText == other.sidebarText &&
            controlBarBackground == other.controlBarBackground &&
            controlBarBorder == other.controlBarBorder &&
            controlBarText == other.controlBarText &&
            buttonPrimary == other.buttonPrimary &&
            buttonSecondary == other.buttonSecondary &&
            buttonDanger == other.buttonDanger &&
            searchFieldBackground == other.searchFieldBackground &&
            searchFieldText == other.searchFieldText &&
            searchFieldIcon == other.searchFieldIcon &&
            tileHover == other.tileHover &&
            outline == other.outline;
  }

  static const AppTokens defaultTokens = AppTokens(
    panelBackground: AppColors.bgDark,
    panelBorder: AppColors.surfaceDarkVariant,
    cardBackground: AppColors.surfaceLight,
    cardBorder: AppColors.surfaceLightBorder,
    sidebarBackground: AppColors.bgDark,
    sidebarBorder: AppColors.surfaceDark,
    sidebarText: AppColors.textLight,
    controlBarBackground: AppColors.surfaceDark,
    controlBarBorder: AppColors.surfaceDarkVariant,
    controlBarText: AppColors.textLight,
    buttonPrimary: AppColors.brandBlue,
    buttonSecondary: AppColors.surfaceDarkVariant,
    buttonDanger: AppColors.error,
    searchFieldBackground: AppColors.surfaceDarkVariant,
    searchFieldText: AppColors.textDark,
    searchFieldIcon: AppColors.textLight,
    tileHover: AppColors.surfaceDarkVariant,
    outline: AppColors.surfaceLightBorder,
  );
}
