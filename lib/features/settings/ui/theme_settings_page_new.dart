import 'package:flutter/material.dart';

import 'theme_settings_page.dart';

/// Wrapper legado (evita confusión con dos implementaciones distintas).
@Deprecated('Usa ThemeSettingsPage en theme_settings_page.dart')
class ThemeSettingsPageNew extends StatelessWidget {
  const ThemeSettingsPageNew({super.key});

  @override
  Widget build(BuildContext context) {
    return const ThemeSettingsPage();
  }
}
