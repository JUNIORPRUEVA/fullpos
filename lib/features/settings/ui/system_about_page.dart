import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/services/app_configuration_service.dart';
import '../../../core/update/app_update_coordinator.dart';
import 'settings_layout.dart';

class SystemAboutPage extends StatefulWidget {
  const SystemAboutPage({super.key});

  @override
  State<SystemAboutPage> createState() => _SystemAboutPageState();
}

class _SystemAboutPageState extends State<SystemAboutPage> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();
  bool _checking = false;

  Future<void> _checkUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    await AppUpdateCoordinator.instance.check(manual: true);
    if (!mounted) return;
    setState(() => _checking = false);
    final state = AppUpdateCoordinator.instance.state;
    if (state.phase == AppUpdatePhase.current && state.message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(state.message!)));
    } else if (state.phase == AppUpdatePhase.offline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            state.message ??
                'No se pudo consultar actualizaciones. Verifica tu conexión.',
          ),
        ),
      );
    }
  }

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
                      child: FutureBuilder<PackageInfo>(
                        future: _packageInfo,
                        builder: (context, snapshot) {
                          final info = snapshot.data;
                          return Text(
                            info == null
                                ? 'Consultando versión…'
                                : 'v${info.version}+${info.buildNumber}',
                            style: textTheme.labelMedium?.copyWith(
                              color: scheme.onSecondaryContainer,
                              fontWeight: FontWeight.w800,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: FilledButton.icon(
                      onPressed: _checking ? null : _checkUpdates,
                      icon: _checking
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.system_update_alt_rounded),
                      label: Text(
                        _checking
                            ? 'Buscando actualizaciones…'
                            : 'Buscar actualizaciones',
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
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
