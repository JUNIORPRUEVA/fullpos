import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/theme_settings_model.dart';
import '../providers/theme_provider.dart';
import 'settings_layout.dart';

/// Página de configuración simplificada del tema.
class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeProvider);
    final notifier = ref.read(themeProvider.notifier);
    ThemeSettings previewChromeBackground(Color color) {
      return settings.copyWith(
        appBarColor: settings.applyChromeToEntireLayout
            ? color
            : settings.appBarColor,
        topbarColor: color,
        sidebarColor: color,
        footerColor: color,
      );
    }

    ThemeSettings previewChromeText(Color color) {
      return settings.copyWith(
        appBarTextColor: settings.applyChromeToEntireLayout
            ? color
            : settings.appBarTextColor,
        topbarTextColor: color,
        sidebarTextColor: color,
        footerTextColor: color,
      );
    }

    ThemeSettings previewAppBarBackground(Color color) {
      return settings.copyWith(appBarColor: color);
    }

    ThemeSettings previewAppBarText(Color color) {
      return settings.copyWith(appBarTextColor: color);
    }

    ThemeSettings previewTopbarBackground(Color color) {
      return settings.copyWith(topbarColor: color);
    }

    ThemeSettings previewTopbarText(Color color) {
      return settings.copyWith(topbarTextColor: color);
    }

    ThemeSettings previewFooterBackground(Color color) {
      return settings.copyWith(footerColor: color);
    }

    ThemeSettings previewFooterText(Color color) {
      return settings.copyWith(footerTextColor: color);
    }

    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(title: const Text('Apariencia')),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SettingsLayout.pageFrame(
              constraints,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SettingsLayout.sectionHeading(
                      context,
                      title: 'Apariencia',
                      subtitle:
                          'Edita solo lo esencial. La apariencia base de FULLPOS sigue como configuración segura por defecto.',
                    ),
                    const SizedBox(height: 16),

                    _SectionCard(
                      title: 'Chrome principal',
                      child: Column(
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: settings.applyChromeToEntireLayout,
                            onChanged:
                                notifier.updateApplyChromeToEntireLayout,
                            title: const Text('Aplicar al layout completo'),
                            subtitle: const Text(
                              'Sincroniza AppBar de pantallas, topbar, sidebar y footer con el mismo color base.',
                            ),
                          ),
                          _ColorRow(
                            label: settings.applyChromeToEntireLayout
                                ? 'Color del layout completo'
                                : 'Color de topbar, sidebar y footer',
                            color: settings.topbarColor,
                            onPreview: (color) =>
                                notifier.previewSettings(
                                  previewChromeBackground(color),
                                ),
                            onPick: notifier.updateChromeBackgroundColor,
                          ),
                          _ColorRow(
                            label: settings.applyChromeToEntireLayout
                                ? 'Texto e iconos del layout completo'
                                : 'Texto e iconos de topbar, sidebar y footer',
                            color: settings.topbarTextColor,
                            onPreview: (color) => notifier.previewSettings(
                              previewChromeText(color),
                            ),
                            onPick: notifier.updateChromeTextColor,
                          ),
                        ],
                      ),
                    ),

                    _SectionCard(
                      title: 'Sidebar principal',
                      child: Column(
                        children: [
                          _ColorRow(
                            label: 'Fondo del sidebar',
                            color: settings.sidebarColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(sidebarColor: color),
                            ),
                            onPick: notifier.updateSidebarColor,
                          ),
                          _ColorRow(
                            label: 'Texto e iconos del sidebar',
                            color: settings.sidebarTextColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(sidebarTextColor: color),
                            ),
                            onPick: notifier.updateSidebarTextColor,
                          ),
                          _ColorRow(
                            label: 'Color activo del sidebar',
                            color: settings.sidebarActiveColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(sidebarActiveColor: color),
                            ),
                            onPick: notifier.updateSidebarActiveColor,
                          ),
                          _ColorRow(
                            label: 'Hover del sidebar',
                            color: settings.hoverColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(hoverColor: color),
                            ),
                            onPick: notifier.updateHoverColor,
                          ),
                        ],
                      ),
                    ),

                    _SectionCard(
                      title: 'AppBar de pantallas',
                      child: Column(
                        children: [
                          _ColorRow(
                            label: 'Fondo del AppBar de pantallas',
                            color: settings.appBarColor,
                            onPreview: (color) => notifier.previewSettings(
                              previewAppBarBackground(color),
                            ),
                            onPick: notifier.updateAppBarColor,
                          ),
                          _ColorRow(
                            label: 'Texto e iconos del AppBar de pantallas',
                            color: settings.appBarTextColor,
                            onPreview: (color) => notifier.previewSettings(
                              previewAppBarText(color),
                            ),
                            onPick: notifier.updateAppBarTextColor,
                          ),
                        ],
                      ),
                    ),

                    _SectionCard(
                      title: 'Topbar principal',
                      child: Column(
                        children: [
                          _ColorRow(
                            label: 'Fondo del topbar',
                            color: settings.topbarColor,
                            onPreview: (color) => notifier.previewSettings(
                              previewTopbarBackground(color),
                            ),
                            onPick: notifier.updateTopbarColor,
                          ),
                          _ColorRow(
                            label: 'Texto e iconos del topbar',
                            color: settings.topbarTextColor,
                            onPreview: (color) => notifier.previewSettings(
                              previewTopbarText(color),
                            ),
                            onPick: notifier.updateTopbarTextColor,
                          ),
                        ],
                      ),
                    ),

                    _SectionCard(
                      title: 'Footer principal',
                      child: Column(
                        children: [
                          _ColorRow(
                            label: 'Fondo del footer',
                            color: settings.footerColor,
                            onPreview: (color) => notifier.previewSettings(
                              previewFooterBackground(color),
                            ),
                            onPick: notifier.updateFooterColor,
                          ),
                          _ColorRow(
                            label: 'Texto del footer',
                            color: settings.footerTextColor,
                            onPreview: (color) => notifier.previewSettings(
                              previewFooterText(color),
                            ),
                            onPick: notifier.updateFooterTextColor,
                          ),
                        ],
                      ),
                    ),

                    _SectionCard(
                      title: 'Fondo general',
                      child: Column(
                        children: [
                          _ColorRow(
                            label: 'Fondo principal de la aplicación',
                            color: settings.backgroundColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(backgroundColor: color),
                            ),
                            onPick: notifier.updateBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Paneles y superficies',
                            color: settings.surfaceColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(surfaceColor: color),
                            ),
                            onPick: notifier.updateSurfaceColor,
                          ),
                          _ColorRow(
                            label: 'Tarjetas',
                            color: settings.cardColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(cardColor: color),
                            ),
                            onPick: notifier.updateCardColor,
                          ),
                          _ColorRow(
                            label: 'Texto general',
                            color: settings.textColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(textColor: color),
                            ),
                            onPick: notifier.updateTextColor,
                          ),
                        ],
                      ),
                    ),

                    _SectionCard(
                      title: 'Tipografía',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: settings.fontFamily,
                            decoration: const InputDecoration(
                              labelText: 'Tipo de letra',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Poppins',
                                child: Text('Poppins'),
                              ),
                              DropdownMenuItem(
                                value: 'Roboto',
                                child: Text('Roboto'),
                              ),
                              DropdownMenuItem(
                                value: 'Arial',
                                child: Text('Arial'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              notifier.updateFontFamily(value);
                            },
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _fontScaleLabel(settings.fontSize),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          Slider(
                            value: settings.fontSize.clamp(10.0, 22.0),
                            min: 10,
                            max: 22,
                            divisions: 12,
                            label: settings.fontSize.toStringAsFixed(0),
                            onChanged: notifier.updateFontSize,
                          ),
                        ],
                      ),
                    ),

                    _SectionCard(
                      title: 'Ventas: productos y grid',
                      child: Column(
                        children: [
                          _ColorRow(
                            label: 'Fondo del grid de productos',
                            color: settings.salesGridBackgroundColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesGridBackgroundColor: color,
                              ),
                            ),
                            onPick: notifier.updateSalesGridBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Fondo de la tarjeta de producto',
                            color: settings.salesProductCardBackgroundColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesProductCardBackgroundColor: color,
                              ),
                            ),
                            onPick:
                                notifier.updateSalesProductCardBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Borde de la tarjeta de producto',
                            color: settings.salesProductCardBorderColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesProductCardBorderColor: color,
                              ),
                            ),
                            onPick: notifier.updateSalesProductCardBorderColor,
                          ),
                          _ColorRow(
                            label: 'Texto de la tarjeta de producto',
                            color: settings.salesProductCardTextColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesProductCardTextColor: color,
                              ),
                            ),
                            onPick: notifier.updateSalesProductCardTextColor,
                          ),
                          _ColorRow(
                            label: 'Fondo alterno de la tarjeta de producto',
                            color: settings.salesProductCardAltBackgroundColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesProductCardAltBackgroundColor: color,
                              ),
                            ),
                            onPick:
                                notifier.updateSalesProductCardAltBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Borde alterno de la tarjeta de producto',
                            color: settings.salesProductCardAltBorderColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesProductCardAltBorderColor: color,
                              ),
                            ),
                            onPick:
                                notifier.updateSalesProductCardAltBorderColor,
                          ),
                          _ColorRow(
                            label: 'Texto alterno de la tarjeta de producto',
                            color: settings.salesProductCardAltTextColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesProductCardAltTextColor: color,
                              ),
                            ),
                            onPick:
                                notifier.updateSalesProductCardAltTextColor,
                          ),
                          _ColorRow(
                            label: 'Precio de producto',
                            color: settings.salesProductPriceColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(salesProductPriceColor: color),
                            ),
                            onPick: notifier.updateSalesProductPriceColor,
                          ),
                        ],
                      ),
                    ),

                    _SectionCard(
                      title: 'Ventas: columna de detalle',
                      child: Column(
                        children: [
                          _ColorRow(
                            label: 'Gradiente inicio',
                            color: settings.salesDetailGradientStart,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesDetailGradientStart: color,
                              ),
                            ),
                            onPick: notifier.updateSalesDetailGradientStart,
                          ),
                          _ColorRow(
                            label: 'Gradiente medio',
                            color: settings.salesDetailGradientMid,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(salesDetailGradientMid: color),
                            ),
                            onPick: notifier.updateSalesDetailGradientMid,
                          ),
                          _ColorRow(
                            label: 'Gradiente final',
                            color: settings.salesDetailGradientEnd,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(salesDetailGradientEnd: color),
                            ),
                            onPick: notifier.updateSalesDetailGradientEnd,
                          ),
                          _ColorRow(
                            label: 'Texto de la columna de detalle',
                            color: settings.salesDetailTextColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(salesDetailTextColor: color),
                            ),
                            onPick: notifier.updateSalesDetailTextColor,
                          ),
                        ],
                      ),
                    ),

                    _SectionCard(
                      title: 'Ventas: barra superior y dropdowns',
                      child: Column(
                        children: [
                          _ColorRow(
                            label: 'Fondo externo de la barra de ventas',
                            color: settings.salesControlBarBackgroundColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesControlBarBackgroundColor: color,
                              ),
                            ),
                            onPick:
                                notifier.updateSalesControlBarBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Fondo interno de la barra de ventas',
                            color:
                                settings.salesControlBarContentBackgroundColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesControlBarContentBackgroundColor: color,
                              ),
                            ),
                            onPick: notifier
                                .updateSalesControlBarContentBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Borde de la barra de ventas',
                            color: settings.salesControlBarBorderColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesControlBarBorderColor: color,
                              ),
                            ),
                            onPick: notifier.updateSalesControlBarBorderColor,
                          ),
                          _ColorRow(
                            label: 'Texto e iconos de la barra de ventas',
                            color: settings.salesControlBarTextColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesControlBarTextColor: color,
                              ),
                            ),
                            onPick: notifier.updateSalesControlBarTextColor,
                          ),
                          _ColorRow(
                            label: 'Fondo del dropdown de categoría',
                            color:
                                settings.salesControlBarDropdownBackgroundColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesControlBarDropdownBackgroundColor: color,
                              ),
                            ),
                            onPick: notifier
                                .updateSalesControlBarDropdownBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Borde del dropdown de categoría',
                            color: settings.salesControlBarDropdownBorderColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesControlBarDropdownBorderColor: color,
                              ),
                            ),
                            onPick: notifier
                                .updateSalesControlBarDropdownBorderColor,
                          ),
                          _ColorRow(
                            label: 'Texto del dropdown de categoría',
                            color: settings.salesControlBarDropdownTextColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesControlBarDropdownTextColor: color,
                              ),
                            ),
                            onPick: notifier
                                .updateSalesControlBarDropdownTextColor,
                          ),
                          _ColorRow(
                            label: 'Fondo del menú emergente',
                            color: settings.salesControlBarPopupBackgroundColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesControlBarPopupBackgroundColor: color,
                              ),
                            ),
                            onPick: notifier
                                .updateSalesControlBarPopupBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Texto del menú emergente',
                            color: settings.salesControlBarPopupTextColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesControlBarPopupTextColor: color,
                              ),
                            ),
                            onPick:
                                notifier.updateSalesControlBarPopupTextColor,
                          ),
                          _ColorRow(
                            label: 'Fondo del elemento seleccionado',
                            color: settings
                                .salesControlBarPopupSelectedBackgroundColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesControlBarPopupSelectedBackgroundColor:
                                    color,
                              ),
                            ),
                            onPick: notifier
                                .updateSalesControlBarPopupSelectedBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Texto del elemento seleccionado',
                            color:
                                settings.salesControlBarPopupSelectedTextColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesControlBarPopupSelectedTextColor: color,
                              ),
                            ),
                            onPick: notifier
                                .updateSalesControlBarPopupSelectedTextColor,
                          ),
                        ],
                      ),
                    ),

                    _SectionCard(
                      title: 'Ventas: botones del footer',
                      child: Column(
                        children: [
                          _ColorRow(
                            label: 'Fondo de botones del footer de ventas',
                            color: settings.salesFooterButtonsBackgroundColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesFooterButtonsBackgroundColor: color,
                              ),
                            ),
                            onPick:
                                notifier.updateSalesFooterButtonsBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Texto de botones del footer de ventas',
                            color: settings.salesFooterButtonsTextColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesFooterButtonsTextColor: color,
                              ),
                            ),
                            onPick:
                                notifier.updateSalesFooterButtonsTextColor,
                          ),
                          _ColorRow(
                            label: 'Borde de botones del footer de ventas',
                            color: settings.salesFooterButtonsBorderColor,
                            onPreview: (color) => notifier.previewSettings(
                              settings.copyWith(
                                salesFooterButtonsBorderColor: color,
                              ),
                            ),
                            onPick:
                                notifier.updateSalesFooterButtonsBorderColor,
                          ),
                        ],
                      ),
                    ),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: notifier.resetToDefault,
                            icon: const Icon(Icons.restart_alt),
                            label: const Text('Restablecer apariencia FULLPOS'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: settings.successColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Los cambios se aplican al momento y siempre puedes volver a la apariencia base de FULLPOS.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

String _fontScaleLabel(double fontSize) {
  if (fontSize <= 12) return 'Estilo tipográfico: compacto';
  if (fontSize >= 18) return 'Estilo tipográfico: amplio';
  return 'Estilo tipográfico: equilibrado';
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  final String label;
  final Color color;
  final ValueChanged<Color> onPick;
  final ValueChanged<Color>? onPreview;

  const _ColorRow({
    required this.label,
    required this.color,
    required this.onPick,
    this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: () async {
              final picked = await _pickColor(
                context,
                initial: color,
                onChanged: onPreview,
              );
              if (picked == null) {
                onPreview?.call(color);
                return;
              }
              onPick(picked);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 44,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: scheme.outlineVariant.withAlpha(120)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '#${color.value.toRadixString(16).toUpperCase().padLeft(8, '0')}',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Future<Color?> _pickColor(
    BuildContext context, {
    required Color initial,
    ValueChanged<Color>? onChanged,
  }) async {
    Color current = initial;
    int a = initial.alpha;
    int r = initial.red;
    int g = initial.green;
    int b = initial.blue;

    String toHex(Color c) =>
        c.value.toRadixString(16).toUpperCase().padLeft(8, '0');
    Color fromArgb(int aa, int rr, int gg, int bb) =>
        Color.fromARGB(aa, rr, gg, bb);

    final controller = TextEditingController(text: toHex(initial));

    var closing = false;
    void requestClose([Color? value]) {
      if (closing) return;
      closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final nav = Navigator.of(context, rootNavigator: true);
        if (nav.canPop()) nav.pop(value);
      });
    }

    final result = await showDialog<Color>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Seleccionar color'),
          content: StatefulBuilder(
            builder: (ctx, setState) {
              final theme = Theme.of(ctx);
              final scheme = theme.colorScheme;
              final swatches = <Color>[
                const Color(0xFF000000),
                const Color(0xFFFFFFFF),
                const Color(0xFF1F2937),
                const Color(0xFF00796B),
                const Color(0xFFD4AF37),
                const Color(0xFF1976D2),
                const Color(0xFF7B1FA2),
                const Color(0xFFE65100),
                const Color(0xFF2E7D32),
                const Color(0xFFEF4444),
                const Color(0xFFF59E0B),
              ];

              void syncThemeFromCurrent() {
                a = current.alpha;
                r = current.red;
                g = current.green;
                b = current.blue;
              }

              void setCurrent(Color c) {
                setState(() {
                  current = c;
                  syncThemeFromCurrent();
                  controller.text = toHex(current);
                });
                onChanged?.call(c);
              }

              void setFromSliders() {
                setCurrent(fromArgb(a, r, g, b));
              }

              return SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 34,
                          decoration: BoxDecoration(
                            color: current,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: scheme.outlineVariant.withAlpha(140),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            decoration: const InputDecoration(
                              labelText: 'ARGB Hex (8 chars) ej: FF00796B',
                            ),
                            onChanged: (v) {
                              final parsed = _tryParseHexColor(v);
                              if (parsed != null) {
                                setState(() {
                                  current = parsed;
                                  syncThemeFromCurrent();
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Text(
                      'Selector (A/R/G/B)',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),

                    _SliderRow(
                      label: 'A',
                      value: a.toDouble(),
                      activeColor: scheme.primary,
                      onChanged: (v) {
                        a = v.round().clamp(0, 255);
                        setFromSliders();
                      },
                    ),
                    _SliderRow(
                      label: 'R',
                      value: r.toDouble(),
                      activeColor: Colors.red,
                      onChanged: (v) {
                        r = v.round().clamp(0, 255);
                        setFromSliders();
                      },
                    ),
                    _SliderRow(
                      label: 'G',
                      value: g.toDouble(),
                      activeColor: Colors.green,
                      onChanged: (v) {
                        g = v.round().clamp(0, 255);
                        setFromSliders();
                      },
                    ),
                    _SliderRow(
                      label: 'B',
                      value: b.toDouble(),
                      activeColor: Colors.blue,
                      onChanged: (v) {
                        b = v.round().clamp(0, 255);
                        setFromSliders();
                      },
                    ),

                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final c in swatches)
                          InkWell(
                            onTap: () {
                              setCurrent(c);
                            },
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: c,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: scheme.outlineVariant.withAlpha(120),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(onPressed: requestClose, child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => requestClose(current),
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );

    return result;
  }

  Color? _tryParseHexColor(String input) {
    final v = input.trim().replaceAll('#', '').toUpperCase();
    final hex = v.length == 6 ? 'FF$v' : v;
    final ok = RegExp(r'^[0-9A-F]{8}$').hasMatch(hex);
    if (!ok) return null;
    return Color(int.parse(hex, radix: 16));
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final Color activeColor;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 18,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Slider(
            min: 0,
            max: 255,
            divisions: 255,
            value: value.clamp(0, 255),
            activeColor: activeColor,
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            value.round().toString(),
            textAlign: TextAlign.end,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
          ),
        ),
      ],
    );
  }
}
