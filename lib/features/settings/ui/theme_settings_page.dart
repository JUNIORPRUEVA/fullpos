import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/theme_provider.dart';
import 'settings_layout.dart';

/// Página de configuración simplificada del tema.
class ThemeSettingsPage extends ConsumerWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(themeProvider);
    final notifier = ref.read(themeProvider.notifier);

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
                          _ColorRow(
                            label: 'Color de AppBar principal, sidebar y footer',
                            color: settings.topbarColor,
                            onPick: notifier.updateChromeBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Texto e iconos del chrome principal',
                            color: settings.topbarTextColor,
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
                            onPick: notifier.updateSidebarColor,
                          ),
                          _ColorRow(
                            label: 'Texto e iconos del sidebar',
                            color: settings.sidebarTextColor,
                            onPick: notifier.updateSidebarTextColor,
                          ),
                          _ColorRow(
                            label: 'Color activo del sidebar',
                            color: settings.sidebarActiveColor,
                            onPick: notifier.updateSidebarActiveColor,
                          ),
                          _ColorRow(
                            label: 'Hover del sidebar',
                            color: settings.hoverColor,
                            onPick: notifier.updateHoverColor,
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
                            onPick: notifier.updateBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Paneles y superficies',
                            color: settings.surfaceColor,
                            onPick: notifier.updateSurfaceColor,
                          ),
                          _ColorRow(
                            label: 'Tarjetas',
                            color: settings.cardColor,
                            onPick: notifier.updateCardColor,
                          ),
                          _ColorRow(
                            label: 'Texto general',
                            color: settings.textColor,
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
                            onPick: notifier.updateSalesGridBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Fondo de la tarjeta de producto',
                            color: settings.salesProductCardBackgroundColor,
                            onPick:
                                notifier.updateSalesProductCardBackgroundColor,
                          ),
                          _ColorRow(
                            label: 'Borde de la tarjeta de producto',
                            color: settings.salesProductCardBorderColor,
                            onPick: notifier.updateSalesProductCardBorderColor,
                          ),
                          _ColorRow(
                            label: 'Texto de la tarjeta de producto',
                            color: settings.salesProductCardTextColor,
                            onPick: notifier.updateSalesProductCardTextColor,
                          ),
                          _ColorRow(
                            label: 'Precio de producto',
                            color: settings.salesProductPriceColor,
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
                            onPick: notifier.updateSalesDetailGradientStart,
                          ),
                          _ColorRow(
                            label: 'Gradiente medio',
                            color: settings.salesDetailGradientMid,
                            onPick: notifier.updateSalesDetailGradientMid,
                          ),
                          _ColorRow(
                            label: 'Gradiente final',
                            color: settings.salesDetailGradientEnd,
                            onPick: notifier.updateSalesDetailGradientEnd,
                          ),
                          _ColorRow(
                            label: 'Texto de la columna de detalle',
                            color: settings.salesDetailTextColor,
                            onPick: notifier.updateSalesDetailTextColor,
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

  const _ColorRow({
    required this.label,
    required this.color,
    required this.onPick,
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
              final picked = await _pickColor(context, initial: color);
              if (picked != null) onPick(picked);
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
