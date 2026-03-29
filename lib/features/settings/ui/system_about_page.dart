import 'package:flutter/material.dart';

import '../../../core/services/app_configuration_service.dart';
import 'settings_layout.dart';

class SystemAboutPage extends StatelessWidget {
  const SystemAboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final businessName = appConfigService.getBusinessName().trim().isNotEmpty
        ? appConfigService.getBusinessName().trim()
        : 'FULLPOS';
    final year = DateTime.now().year;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(title: const Text('Acerca de')),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SettingsLayout.pageFrame(
              constraints,
              child: ListView(
                children: [
                  SettingsLayout.sectionHeading(
                    context,
                    title: 'Informacion del sistema',
                    subtitle:
                        'Version local, atajos principales y referencia rapida de esta instalacion.',
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [scheme.primary, scheme.tertiary],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.point_of_sale,
                        color: scheme.onPrimary,
                        size: 48,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    businessName,
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'SISTEMA POS',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'v1.0.0 LOCAL',
                        style: textTheme.labelMedium?.copyWith(
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _InfoCard(
                    title: 'Atajos globales',
                    items: const [
                      'Ctrl+Shift+F - Pantalla completa',
                      'Ctrl+Q - Cerrar app',
                      'ESC - Cerrar dialogos',
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoCard(
                    title: 'Atajos de ventas',
                    items: const [
                      'F2 - Enfocar busqueda',
                      'F3 - Seleccionar cliente',
                      'F4 - Nuevo cliente',
                      'F7 - Aplicar descuento',
                      'F9 - Abrir pago',
                      'F12 - Finalizar venta',
                      '+ / - - Cambiar cantidad',
                      'Ctrl+Backspace - Eliminar item',
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '© $year $businessName',
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(item),
            ),
        ],
      ),
    );
  }
}