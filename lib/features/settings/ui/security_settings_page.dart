import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/security_config.dart';
import '../../../core/session/session_manager.dart';
import '../providers/business_settings_provider.dart';
import 'settings_layout.dart';

class SecuritySettingsPage extends ConsumerStatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  ConsumerState<SecuritySettingsPage> createState() =>
      _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends ConsumerState<SecuritySettingsPage> {
  SecurityConfig? _config;
  bool _loading = true;
  int _companyId = 1;
  String _terminalId = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final companyId = await SessionManager.companyId() ?? 1;
    final terminalId =
        await SessionManager.terminalId() ??
        await SessionManager.ensureTerminalId();
    final config = await SecurityConfigRepository.load(
      companyId: companyId,
      terminalId: terminalId,
    );

    if (!mounted) return;
    setState(() {
      _config = config;
      _companyId = companyId;
      _terminalId = terminalId;
      _loading = false;
    });
  }

  Future<void> _save(SecurityConfig newConfig) async {
    if (!mounted) return;
    setState(() {
      _config = newConfig;
    });
    await SecurityConfigRepository.save(
      config: newConfig,
      companyId: _companyId,
      terminalId: _terminalId,
    );
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copiado')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _config == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final businessSettings = ref.watch(businessSettingsProvider);
    final cloudEnabled = businessSettings.cloudEnabled;
    final config = _config!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Seguridad y permisos')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = SettingsLayout.contentPadding(constraints);
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: SettingsLayout.maxWidth(constraints),
              child: ListView(
                padding: padding,
                children: [
                  Text(
                    'Aquí configuras cómo se aprueban acciones restringidas (sin manejar permisos por módulos aquí).',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.75),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'PIN de administrador (offline)',
                    subtitle:
                        'Aprobaciones locales usando el PIN de cualquier usuario Administrador.',
                    trailing: Switch.adaptive(
                      value: config.offlinePinEnabled,
                      onChanged: (v) =>
                          _save(config.copyWith(offlinePinEnabled: v)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    icon: Icons.cloud_outlined,
                    title: 'Token en la nube (remote)',
                    subtitle: cloudEnabled
                        ? 'El dueño puede aprobar remotamente vía token/online. Puede usarse junto con PIN local.'
                        : 'Requiere activar Cloud para usar aprobaciones remotas.',
                    trailing: Switch.adaptive(
                      value: (config.remoteEnabled || config.virtualTokenEnabled),
                      onChanged: cloudEnabled
                          ? (v) => _save(
                                config.copyWith(
                                  remoteEnabled: v,
                                  virtualTokenEnabled: v,
                                ),
                              )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsCard(
                    icon: Icons.confirmation_number_outlined,
                    title: 'ID de Terminal/Caja',
                    subtitle:
                        'Usa este ID para activar aprobaciones remotas por token en Owner/nube.',
                    trailing: FilledButton.tonalIcon(
                      onPressed: _terminalId.isEmpty
                          ? null
                          : () => _copy('ID de Terminal', _terminalId),
                      icon: const Icon(Icons.copy),
                      label: const Text('Copiar'),
                    ),
                    content: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant
                              .withOpacity(0.55),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.4),
                          ),
                        ),
                        child: SelectableText(
                          _terminalId,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Widget? content;

  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.content,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurface.withOpacity(0.7),
      height: 1.25,
    );

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: titleStyle),
                        const SizedBox(height: 4),
                        Text(subtitle, style: subtitleStyle),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: trailing,
                ),
              ],
            ),
            if (content != null) content!,
          ],
        ),
      ),
    );
  }
}
