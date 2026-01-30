import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import '../data/theme_settings_model.dart';
import '../../../core/constants/app_sizes.dart';

/// Widget para selector de tema de la aplicaciÃ³n
class ThemeSelector extends ConsumerWidget {
  final EdgeInsets padding;

  const ThemeSelector({super.key, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeProvider);
    final scheme = Theme.of(context).colorScheme;
    final themeNotifier = ref.read(themeProvider.notifier);

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TÃ­tulo
          Text(
            'Tema de la aplicaciÃ³n',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Elige uno de los 2 temas o personaliza todo',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),

          // Modo oscuro
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
              border: Border.all(color: scheme.outlineVariant.withAlpha(80)),
            ),
            child: Row(
              children: [
                const Icon(Icons.dark_mode_outlined, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Modo oscuro',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Switch(
                  value: settings.isDarkMode,
                  onChanged: (_) => themeNotifier.toggleDarkMode(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Opcion 1: Azul royal + oro (por defecto)
          _buildPresetOption(
            context,
            scheme: scheme,
            presetKey: 'default',
            title: 'Dominicano Dark',
            description: 'Azul oscuro con acentos dorado/verde/rojo',
            settings: PresetThemes.getPreset('default'),
            isSelected: _isSamePalette(
              ref.watch(themeProvider),
              PresetThemes.getPreset('default'),
            ),
            onTap: () => themeNotifier.applyPreset('default'),
          ),
          const SizedBox(height: 12),

          // Opcion 2: Claro ejecutivo
          _buildPresetOption(
            context,
            scheme: scheme,
            presetKey: 'sand',
            title: 'Marfil Ejecutivo',
            description: 'Claro premium con contraste profesional',
            settings: PresetThemes.getPreset('sand'),
            isSelected: _isSamePalette(
              ref.watch(themeProvider),
              PresetThemes.getPreset('sand'),
            ),
            onTap: () => themeNotifier.applyPreset('sand'),
          ),

          const SizedBox(height: 24),

          // Preview del tema actual
          _buildThemePreview(context, scheme),
        ],
      ),
    );
  }

  bool _isSamePalette(ThemeSettings current, ThemeSettings preset) {
    return current.primaryColor == preset.primaryColor &&
        current.accentColor == preset.accentColor &&
        current.sidebarColor == preset.sidebarColor &&
        current.footerColor == preset.footerColor &&
        current.isDarkMode == preset.isDarkMode;
  }

  Widget _buildPresetOption(
    BuildContext context, {
    required ColorScheme scheme,
    required String presetKey,
    required String title,
    required String description,
    required ThemeSettings settings,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.radiusM),
          border: Border.all(
            color: isSelected
                ? settings.primaryColor
                : scheme.outlineVariant.withAlpha(100),
            width: isSelected ? 2.5 : 1.5,
          ),
          color: isSelected
              ? settings.primaryColor.withAlpha(15)
              : Colors.transparent,
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Indicador selecciÃ³n
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  width: 2,
                  color: isSelected
                      ? settings.primaryColor
                      : scheme.outlineVariant.withAlpha(140),
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: settings.primaryColor,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),

            // InformaciÃ³n del tema
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),

            // Mini preview de colores
            SizedBox(
              width: 100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildColorPreview(scheme, settings.primaryColor, size: 24),
                  const SizedBox(width: 6),
                  _buildColorPreview(scheme, settings.accentColor, size: 24),
                  const SizedBox(width: 6),
                  _buildColorPreview(
                    scheme,
                    settings.surfaceColor,
                    size: 24,
                    hasBorder: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Construir un cÃ­rculo de color
  Widget _buildColorPreview(
    ColorScheme scheme,
    Color color, {
    double size = 24,
    bool hasBorder = false,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: hasBorder
            ? Border.all(color: scheme.outlineVariant.withAlpha(150), width: 1)
            : null,
      ),
    );
  }

  /// Construir preview del tema completo
  Widget _buildThemePreview(BuildContext context, ColorScheme scheme) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSizes.radiusL),
        border: Border.all(
          color: scheme.outlineVariant.withAlpha(100),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TÃ­tulo
          Text(
            'Vista previa del tema actual',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 12),

          // Vista previa tipo AppBar
          Container(
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
            ),
            child: Center(
              child: Text(
                'AppBar Preview',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Ejemplo de contenido
          Container(
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(AppSizes.radiusM),
              border: Border.all(
                color: scheme.outlineVariant.withAlpha(100),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TÃ­tulo de contenido',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Este es un texto normal de demostraciÃ³n para mostrar cÃ³mo se verÃ­a el contenido con este tema.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('BotÃ³n'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {},
                      child: const Text('Outlined'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
