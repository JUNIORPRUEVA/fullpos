import 'package:flutter/material.dart';

import '../../../core/security/security_config.dart';
import '../../../core/session/session_manager.dart';
import 'settings_layout.dart';

class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key});

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  SecurityConfig? _config;
  bool _loading = true;

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
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _config == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: Scaffold(
        appBar: AppBar(title: const Text('Seguridad y aprobaciones')),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SettingsLayout.pageFrame(
              constraints,
              child: ListView(
                children: const [
                  _SecurityHeader(),
                  SizedBox(height: 12),
                  _SettingsCard(
                    icon: Icons.admin_panel_settings_outlined,
                    title: 'Código de administración',
                    subtitle:
                        'Las acciones restringidas se autorizan únicamente con el código/PIN de un usuario administrador activo. No hay QR ni aprobaciones remotas.',
                    trailing: _ActiveBadge(),
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

class _SecurityHeader extends StatelessWidget {
  const _SecurityHeader();

  @override
  Widget build(BuildContext context) {
    return SettingsLayout.sectionHeading(
      context,
      title: 'Seguridad operativa',
      subtitle:
          'La autorización del sistema está unificada: el administrador debe ingresar su código para aprobar acciones restringidas.',
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.primary.withOpacity(0.24)),
      ),
      child: Text(
        'Activo',
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Icon(icon, color: theme.colorScheme.primary, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: titleStyle),
                      const SizedBox(height: 2),
                      Text(subtitle, style: subtitleStyle),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(top: 2), child: trailing),
            ],
          ),
        ],
      ),
    );
  }
}
