import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../settings/providers/business_settings_provider.dart';
import '../../settings/ui/training/training_page.dart';
import '../data/owner_app_links.dart';
import 'authorizations_page.dart';
import 'scanner_settings_page.dart';

/// Página de Herramientas
class ToolsPage extends ConsumerWidget {
  const ToolsPage({super.key});

  static Future<void> _showOwnerAppDialog(
    BuildContext context, {
    required Widget ownerLinksWidget,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.download_rounded, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Descargar FULLPOS Owner',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ownerLinksWidget,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<void> _openUrl(BuildContext context, String url) async {
    final ok = await launchUrlString(url, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el enlace')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final settings = ref.watch(businessSettingsProvider);

    final localLinks = OwnerAppLinks(
      androidUrl: (settings.cloudOwnerAppAndroidUrl?.trim().isEmpty ?? true)
          ? null
          : settings.cloudOwnerAppAndroidUrl!.trim(),
      iosUrl: (settings.cloudOwnerAppIosUrl?.trim().isEmpty ?? true)
          ? null
          : settings.cloudOwnerAppIosUrl!.trim(),
    );

    final hasLocalLinks =
        localLinks.androidUrl != null || localLinks.iosUrl != null;

    final ownerLinksWidget = hasLocalLinks
        ? _OwnerAppLinksCard(data: localLinks, sourceLabel: 'Configuración')
        : FutureBuilder<OwnerAppLinks>(
            future: OwnerAppLinks.fetch(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'No se pudieron cargar los enlaces de la app del Dueño',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                );
              }
              return _OwnerAppLinksCard(
                data: snapshot.data,
                sourceLabel: 'Servidor',
              );
            },
          );

    final tools = <_ToolItem>[
      _ToolItem(
        icon: Icons.menu_book,
        title: 'Manual y entrenamiento',
        subtitle: 'Guías completas, estreno y respaldo',
        color: scheme.secondary,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TrainingPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.verified_user_outlined,
        title: 'Autorizaciones',
        subtitle: 'Auditoria de permisos',
        color: scheme.primary,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AuthorizationsPage()),
        ),
      ),
      _ToolItem(
        icon: Icons.description_outlined,
        title: 'NCF',
        subtitle: 'Comprobantes fiscales',
        color: scheme.tertiary,
        onTap: () => context.go('/ncf'),
      ),
      _ToolItem(
        icon: Icons.qr_code_scanner_rounded,
        title: 'Lector',
        subtitle: 'Configurar escáner',
        color: scheme.primary,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const ScannerSettingsPage())),
      ),
      _ToolItem(
        icon: Icons.download_rounded,
        title: 'Descargas',
        subtitle: 'FULLPOS Owner',
        color: scheme.secondary,
        onTap: () => ToolsPage._showOwnerAppDialog(
          context,
          ownerLinksWidget: ownerLinksWidget,
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Herramientas',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        surfaceTintColor: scheme.surface,
        elevation: 0,
        toolbarHeight: 48,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final horizontalPadding = (width * 0.04).clamp(12.0, 28.0);
          final verticalPadding = (width * 0.02).clamp(10.0, 20.0);
          final gridSpacing = (width * 0.012).clamp(10.0, 16.0);

          int crossAxisCount;
          if (width < 520) {
            crossAxisCount = 1;
          } else if (width < 760) {
            crossAxisCount = 2;
          } else if (width < 980) {
            crossAxisCount = 3;
          } else if (width < 1240) {
            crossAxisCount = 4;
          } else {
            crossAxisCount = 5;
          }

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  verticalPadding,
                  horizontalPadding,
                  verticalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: scheme.outlineVariant.withOpacity(0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: scheme.primaryContainer.withOpacity(0.65),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: scheme.outlineVariant.withOpacity(0.30),
                              ),
                            ),
                            child: Icon(
                              Icons.apps_rounded,
                              size: 20,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Accesos rápidos',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Herramientas del sistema y utilidades',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: gridSpacing,
                        crossAxisSpacing: gridSpacing,
                        childAspectRatio: 1.25,
                        children: [
                          for (final tool in tools) _ToolCard(tool: tool),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OwnerAppLinksCard extends StatelessWidget {
  final OwnerAppLinks? data;
  final String sourceLabel;

  const _OwnerAppLinksCard({required this.data, required this.sourceLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'App del Dueño (FULLPOS Owner)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(sourceLabel),
                        backgroundColor: scheme.secondaryContainer.withOpacity(
                          0.75,
                        ),
                        labelStyle: TextStyle(
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.android),
                        label: const Text('Descargar Android'),
                        onPressed: data?.androidUrl != null
                            ? () =>
                                  ToolsPage._openUrl(context, data!.androidUrl!)
                            : null,
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.phone_iphone),
                        label: const Text('Descargar iPhone'),
                        onPressed: data?.iosUrl != null
                            ? () => ToolsPage._openUrl(context, data!.iosUrl!)
                            : null,
                      ),
                      if (data?.version != null)
                        Chip(
                          label: Text('Versión ${data!.version}'),
                          backgroundColor: scheme.tertiaryContainer.withOpacity(
                            0.75,
                          ),
                          labelStyle: TextStyle(
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (data?.androidUrl != null)
              QrImageView(
                data: data!.androidUrl!,
                size: 120,
                backgroundColor: scheme.surface,
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ToolItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
}

class _ToolCard extends StatefulWidget {
  final _ToolItem tool;

  const _ToolCard({required this.tool});

  @override
  State<_ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<_ToolCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = Color.alphaBlend(
      widget.tool.color.withOpacity(isDark ? 0.16 : 0.10),
      scheme.surface,
    );
    final borderColor = scheme.outlineVariant.withOpacity(isDark ? 0.42 : 0.28);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        transform: Matrix4.identity()..scale(_isHovered ? 1.02 : 1.0),
        transformAlignment: Alignment.center,
        child: Card(
          color: cardBg,
          elevation: 0,
          shadowColor: scheme.shadow.withOpacity(isDark ? 0.20 : 0.12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: _isHovered
                  ? widget.tool.color.withOpacity(isDark ? 0.45 : 0.35)
                  : borderColor,
              width: _isHovered ? 1.4 : 1.0,
            ),
          ),
          child: InkWell(
            onTap: widget.tool.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        widget.tool.color.withOpacity(isDark ? 0.20 : 0.12),
                        scheme.surface,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor.withOpacity(0.9)),
                    ),
                    child: Icon(
                      widget.tool.icon,
                      size: 24,
                      color: widget.tool.color,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.tool.title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.tool.subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
