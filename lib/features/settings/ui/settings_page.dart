import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/app_configuration_service.dart';
import 'package:printing/printing.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../data/printer_settings_model.dart';
import '../data/printer_settings_repository.dart';
import 'backup_database_page.dart';
import 'database_settings_page.dart';
import 'users_page.dart';
import 'theme_settings_page.dart' as theme_page;
import 'business_settings_page.dart';
import 'logs_page.dart';
import 'security_settings_page.dart';
import 'cloud_settings_page.dart';
import '../../license/data/license_models.dart';
import '../../license/services/license_file_storage.dart';
import '../../license/services/license_storage.dart';
import '../../registration/services/business_identity_storage.dart';
import '../../registration/services/business_registration_service.dart';
import '../../registration/services/pending_registration_queue.dart';
import '../../../theme/app_colors.dart';

/// Pantalla de configuración con diseño de tarjetas
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final cardColors = <Color>[
      AppColors.primaryBlue,
      AppColors.primaryBlue,
      AppColors.primaryBlue,
      AppColors.primaryBlue,
      AppColors.primaryBlue,
      AppColors.primaryBlue,
      AppColors.primaryBlue,
      AppColors.primaryBlue,
      AppColors.primaryBlue,
      AppColors.primaryBlue,
    ];

    return LayoutBuilder(
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
        } else if (width < 1480) {
          crossAxisCount = 5;
        } else {
          crossAxisCount = 6;
        }

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    verticalPadding,
                    horizontalPadding,
                    8,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppColors.borderSoft,
                      ),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.shadow.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.lightBlueHover,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: AppColors.borderSoft,
                            ),
                          ),
                          child: Icon(
                            Icons.settings,
                            size: 22,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Configuración',
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Personaliza tu sistema POS',
                                style: textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      8,
                      horizontalPadding,
                      verticalPadding,
                    ),
                    child: GridView.count(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: gridSpacing,
                      crossAxisSpacing: gridSpacing,
                      childAspectRatio: 2.55,
                      children: [
                        _buildSettingsCard(
                          icon: Icons.print,
                          title: 'Impresora',
                          subtitle: 'Tickets',
                          description:
                              'Configura impresoras y prueba de impresión.',
                          color: cardColors[0],
                          onTap: () => _showPrinterDialog(),
                        ),
                        _buildSettingsCard(
                          icon: Icons.people,
                          title: 'Usuarios',
                          subtitle: 'Accesos',
                          description: 'Roles, permisos y gestión de cuentas.',
                          color: cardColors[1],
                          onTap: () => _openUsersPage(),
                        ),
                        _buildSettingsCard(
                          icon: Icons.shield,
                          title: 'Seguridad',
                          subtitle: 'Overrides',
                          description: 'PIN, códigos locales y autorizaciones.',
                          color: cardColors[2],
                          onTap: () => _openSecuritySettingsPage(),
                        ),
                        _buildSettingsCard(
                          icon: Icons.cloud,
                          title: 'Nube',
                          subtitle: 'Accesos & Owner',
                          description:
                              'Sincronización y acceso del propietario.',
                          color: cardColors[3],
                          onTap: () => _openCloudSettingsPage(),
                        ),
                        _buildSettingsCard(
                          icon: Icons.store,
                          title: 'Negocio',
                          subtitle: 'Empresa',
                          description: 'Datos fiscales, contacto y monedas.',
                          color: cardColors[4],
                          onTap: () => _openBusinessSettingsPage(),
                        ),
                        _buildSettingsCard(
                          icon: Icons.storage,
                          title: 'Backup',
                          subtitle: 'Datos',
                          description: 'Respaldos y restauración del sistema.',
                          color: cardColors[5],
                          onTap: () => _openBackupPage(),
                        ),
                        _buildSettingsCard(
                          icon: Icons.storage_outlined,
                          title: 'Database',
                          subtitle: 'Mantenimiento',
                          description:
                              'Ver estado, errores y opciones de limpieza local.',
                          color: cardColors[9],
                          onTap: () => _openDatabaseSettingsPage(),
                        ),
                        _buildSettingsCard(
                          icon: Icons.palette,
                          title: 'Tema',
                          subtitle: 'Apariencia',
                          description:
                              'Personaliza colores y estilos visuales.',
                          color: cardColors[6],
                          onTap: () => _openThemeSettings(),
                        ),
                        _buildSettingsCard(
                          icon: Icons.info,
                          title: 'Acerca de',
                          subtitle: 'v1.0.0',
                          description: 'Información del sistema y atajos.',
                          color: cardColors[7],
                          onTap: () => _showAboutDialog(),
                        ),
                        _buildSettingsCard(
                          icon: Icons.support_agent,
                          title: 'Soporte',
                          subtitle: 'Logs',
                          description: 'Diagnósticos y registro de eventos.',
                          color: cardColors[8],
                          onTap: () => _openLogsPage(),
                        ),
                        _buildSettingsCard(
                          icon: Icons.vpn_key,
                          title: 'Licencia',
                          subtitle: 'Solo lectura',
                          description:
                              'Ver licencia actual, tiempo restante y ubicación.',
                          color: cardColors[0],
                          onTap: () => _showLicenseSummaryDialog(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openUsersPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UsersPage()),
    );
  }

  void _openSecuritySettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SecuritySettingsPage()),
    );
  }

  void _openCloudSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CloudSettingsPage()),
    );
  }

  void _openThemeSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const theme_page.ThemeSettingsPage()),
    );
  }

  void _openBusinessSettingsPage({int tabIndex = 0}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessSettingsPage(initialTabIndex: tabIndex),
      ),
    );
  }

  void _openLogsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LogsPage()),
    );
  }

  void _openBackupPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BackupDatabasePage()),
    );
  }

  void _openDatabaseSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DatabaseSettingsPage()),
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String description,
    required Color color,
    String? badge,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;

    final cardBg = Color.alphaBlend(
      color.withOpacity(isDark ? 0.12 : 0.07),
      scheme.surface,
    );
    final iconBg = Color.alphaBlend(
      color.withOpacity(isDark ? 0.22 : 0.12),
      scheme.surface,
    );
    final borderColor = AppColors.borderSoft;
    final shadowColor = scheme.shadow.withOpacity(isDark ? 0.14 : 0.06);

    return Card(
      color: cardBg,
      elevation: 1,
      shadowColor: shadowColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned(
              right: -14,
              bottom: -18,
              child: Icon(
                icon,
                size: 56,
                color: scheme.onSurface.withOpacity(isDark ? 0.06 : 0.04),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor.withOpacity(0.75)),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isTight = constraints.maxHeight < 60;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                                color: scheme.onSurface,
                              ),
                            ),
                            SizedBox(height: isTight ? 0 : 1),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelSmall?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (!isTight) ...[
                              const SizedBox(height: 3),
                              Text(
                                description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant.withOpacity(0.7),
                  ),
                ],
              ),
            ),
            if (badge != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.tertiary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onTertiary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutSection(String title, List<String> shortcuts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        ...shortcuts.map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(s, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }

  void _showAboutDialog() {
    final businessName = appConfigService.getBusinessName().trim().isNotEmpty
        ? appConfigService.getBusinessName().trim()
        : 'FULLPOS';
    final year = DateTime.now().year;

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
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
              const SizedBox(height: 20),
              Text(
                businessName,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              Text(
                'SISTEMA POS',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(height: 24),
              Container(
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
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outlineVariant.withOpacity(0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ATAJOS',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildShortcutSection('GLOBALES', [
                      'Ctrl+Shift+F - Pantalla completa',
                      'Ctrl+Q - Cerrar app',
                      'ESC - Cerrar diálogos',
                    ]),
                    const SizedBox(height: 12),
                    _buildShortcutSection('VENTAS', [
                      'F2 - Enfocar búsqueda',
                      'F3 - Seleccionar cliente',
                      'F4 - Nuevo cliente',
                      'F7 - Aplicar descuento',
                      'F9 - Abrir pago',
                      'F12 - Finalizar venta',
                      '+ / - - Cambiar cantidad',
                      'Ctrl+Backspace - Eliminar item',
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '© $year $businessName',
                style: TextStyle(
                  color: scheme.onSurfaceVariant.withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('CERRAR'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPrinterDialog() {
    showDialog(
      context: context,
      builder: (context) => _PrinterDialogContent(
        onConfigurePressed: () {
          Navigator.pop(context);
          context.push('/settings/printer');
        },
      ),
    );
  }

  void _showLicenseSummaryDialog() {
    showDialog(
      context: context,
      builder: (context) => const _LicenseSummaryDialogContent(),
    );
  }
}

class _LicenseSummaryDialogContent extends StatefulWidget {
  const _LicenseSummaryDialogContent();

  @override
  State<_LicenseSummaryDialogContent> createState() =>
      _LicenseSummaryDialogContentState();
}

class _LicenseSummaryDialogContentState
    extends State<_LicenseSummaryDialogContent> {
  final LicenseStorage _licenseStorage = LicenseStorage();
  final LicenseFileStorage _licenseFileStorage = LicenseFileStorage();
  final BusinessIdentityStorage _identityStorage = BusinessIdentityStorage();
  final BusinessRegistrationService _registrationService =
      BusinessRegistrationService();

  bool _isLoading = true;
  LicenseInfo? _info;
  String? _source;
  String? _licenseFilePath;

  @override
  void initState() {
    super.initState();
    _loadLicenseInfo();
  }

  Future<void> _loadLicenseInfo() async {
    try {
      final info = await _licenseStorage.getLastInfo();
      final source = await _licenseStorage.getLastInfoSource();
      final file = await _licenseFileStorage.file();

      if (!mounted) return;
      setState(() {
        _info = info;
        _source = source;
        _licenseFilePath = file.path;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _debugResetLicense() async {
    if (!kDebugMode) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset licencia (debug)'),
        content: const Text(
          'Esto borrará la licencia y el estado de prueba local en esta PC.\n\nSolo disponible en debug.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resetear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _licenseFileStorage.delete();
    } catch (_) {}
    try {
      await _licenseStorage.clearAll();
    } catch (_) {}
    try {
      await BusinessIdentityStorage().clearAll();
    } catch (_) {}
    try {
      await PendingRegistrationQueue().clear();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _info = null;
      _source = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Licencia reseteada (debug).')),
    );
  }

  Future<void> _debugResendRegistrationToCloud() async {
    if (!kDebugMode) return;

    final identity = await _identityStorage.getIdentity();
    if (identity == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay identidad local para reenviar a nube.'),
        ),
      );
      return;
    }

    const appVersion = String.fromEnvironment(
      'FULLPOS_APP_VERSION',
      defaultValue: '1.0.0+1',
    );

    final payload = await _registrationService.buildPayload(
      businessName: identity.businessName,
      role: identity.role,
      ownerName: identity.ownerName,
      phone: identity.phone,
      email: identity.email,
      trialStart: identity.trialStart,
      appVersion: appVersion,
    );

    await _registrationService.registerNowOrQueue(payload);
    await _registrationService.retryPendingOnce();

    final pending = await PendingRegistrationQueue().load();
    if (!mounted) return;
    if (pending.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro reenviado a nube (debug).')),
      );
    } else {
      final lastError = (pending.last.lastError ?? '').trim();
      final msg = lastError.isEmpty
          ? 'No se pudo enviar ahora. Quedó en cola para reintento (debug).'
          : 'No se pudo enviar ahora. Motivo: $lastError';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
        ),
      );
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'No disponible';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day/$month/$year';
  }

  String _maskLicenseKey(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return 'No disponible';
    if (trimmed.length <= 8) return '****';
    return '${trimmed.substring(0, 4)}...${trimmed.substring(trimmed.length - 4)}';
  }

  String _humanizeDays(int totalDays) {
    if (totalDays <= 0) return '0 días';

    final years = totalDays ~/ 365;
    final remainingAfterYears = totalDays % 365;
    final months = remainingAfterYears ~/ 30;
    final days = remainingAfterYears % 30;

    final parts = <String>[];
    if (years > 0) {
      parts.add('$years ${years == 1 ? 'año' : 'años'}');
    }
    if (months > 0) {
      parts.add('$months ${months == 1 ? 'mes' : 'meses'}');
    }
    if (days > 0 && years == 0) {
      parts.add('$days ${days == 1 ? 'día' : 'días'}');
    }

    if (parts.isEmpty) {
      return '$totalDays ${totalDays == 1 ? 'día' : 'días'}';
    }
    return parts.join(' ');
  }

  String _remainingTimeText(LicenseInfo? info) {
    if (info == null) return 'No disponible';
    final end = info.fechaFin;
    if (end == null) return 'Sin fecha de vencimiento';

    final now = DateTime.now();
    final daysDiff = end.difference(now).inDays;

    if (daysDiff < 0) {
      return 'Vencida';
    }
    if (daysDiff == 0) {
      return 'Vence hoy';
    }
    return _humanizeDays(daysDiff);
  }

  String _statusText(LicenseInfo? info) {
    if (info == null) return 'Sin licencia registrada';
    if (info.isExpired) return 'Vencida';
    if (info.isBlocked) return 'Bloqueada';
    if (info.isActive) return 'Activa';
    return 'Pendiente';
  }

  String _sourceText(String? source) {
    switch ((source ?? '').trim().toLowerCase()) {
      case 'cloud':
        return 'Servidor';
      case 'offline':
        return 'Archivo local';
      default:
        return 'No disponible';
    }
  }

  String _devicesText(LicenseInfo? info) {
    if (info == null) return 'No disponible';

    final usados = info.usados;
    final max = info.maxDispositivos;

    if (usados == null && max == null) {
      return 'No reportado por servidor';
    }
    if (usados == null && max != null) {
      return 'No reportado de $max';
    }
    if (usados != null && max == null) {
      return '$usados en uso';
    }

    return '$usados de $max';
  }

  Widget _infoRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(20),
        child: _isLoading
            ? const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.verified_user,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Resumen de licencia',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceVariant.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: const Text(
                      'Esta información es solo para consulta. No se puede editar ni eliminar desde aquí.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _infoRow(label: 'Estado', value: _statusText(_info)),
                  _infoRow(
                    label: 'Tiempo restante',
                    value: _remainingTimeText(_info),
                  ),
                  _infoRow(
                    label: 'Tipo de licencia',
                    value: (_info?.tipo?.trim().isNotEmpty ?? false)
                        ? _info!.tipo!.trim()
                        : 'No disponible',
                  ),
                  _infoRow(
                    label: 'Código',
                    value: (_info?.code?.trim().isNotEmpty ?? false)
                        ? _info!.code!.trim()
                        : 'No disponible',
                  ),
                  _infoRow(
                    label: 'Clave',
                    value: _maskLicenseKey(_info?.licenseKey ?? ''),
                  ),
                  _infoRow(
                    label: 'Inicio',
                    value: _formatDate(_info?.fechaInicio),
                  ),
                  _infoRow(
                    label: 'Vence',
                    value: _formatDate(_info?.fechaFin),
                  ),
                  _infoRow(
                    label: 'Dispositivos',
                    value: _devicesText(_info),
                  ),
                  _infoRow(
                    label: 'Origen',
                    value: _sourceText(_source),
                  ),
                  _infoRow(
                    label: 'Ubicación archivo',
                    value: _licenseFilePath ?? 'No disponible',
                  ),
                  _infoRow(
                    label: 'Última revisión',
                    value: _formatDate(_info?.lastCheckedAt),
                  ),
                  if (kDebugMode) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _debugResendRegistrationToCloud,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text('Reenviar registro nube (debug)'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _debugResetLicense,
                      icon: const Icon(Icons.restart_alt),
                      label: const Text('Reset licencia (debug)'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Diálogo de impresora con StatefulBuilder para manejar estado interno
class _PrinterDialogContent extends StatefulWidget {
  final VoidCallback onConfigurePressed;

  const _PrinterDialogContent({required this.onConfigurePressed});

  @override
  State<_PrinterDialogContent> createState() => _PrinterDialogContentState();
}

class _PrinterDialogContentState extends State<_PrinterDialogContent> {
  List<Printer> _printers = [];
  PrinterSettingsModel? _settings;
  bool _loading = true;
  bool _printing = false;
  String? _selectedPrinter;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final printers = await UnifiedTicketPrinter.getAvailablePrinters();
      final settings = await PrinterSettingsRepository.getOrCreate();

      if (!mounted) return;
      setState(() {
        _printers = printers;
        _settings = settings;
        _selectedPrinter = settings.selectedPrinterName;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Error loading printers: $e\\n$st');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No se pudo cargar la configuraci\u00f3n de impresoras',
          ),
        ),
      );
    }
  }

  Future<void> _printTest() async {
    final scheme = Theme.of(context).colorScheme;
    if (_selectedPrinter == null || _selectedPrinter!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Seleccione una impresora primero'),
          backgroundColor: scheme.secondary,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _printing = true);

    // Actualizar impresora seleccionada antes de imprimir
    final updatedSettings = _settings!.copyWith(
      selectedPrinterName: _selectedPrinter,
    );
    try {
      await PrinterSettingsRepository.updateSettings(updatedSettings);
      if (!mounted) return;

      final result = await UnifiedTicketPrinter.printTestTicket();
      if (!mounted) return;
      final success = result.success;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: success ? scheme.onTertiary : scheme.onError,
              ),
              const SizedBox(width: 8),
              Text(
                success
                    ? '✅ Ticket de prueba enviado a la impresora'
                    : '❌ Error al imprimir - Verifique la impresora',
              ),
            ],
          ),
          backgroundColor: success ? scheme.tertiary : scheme.error,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, st) {
      debugPrint('Error printing test ticket: $e\\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error imprimiendo: $e'),
            backgroundColor: scheme.error,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.print, color: scheme.secondary, size: 40),
            ),
            const SizedBox(height: 16),
            const Text(
              'IMPRESORA Y TICKET',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Impresión térmica de tickets',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 24),

            if (_loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              )
            else ...[
              // Selector de impresora
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.print,
                          color: scheme.onSurfaceVariant,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'IMPRESORA SELECCIONADA',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        // Botón refrescar
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: _loadData,
                          tooltip: 'Actualizar lista',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_printers.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning,
                              color: scheme.onErrorContainer,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'No se detectaron impresoras.\nConecte una impresora e intente de nuevo.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<String>(
                        initialValue:
                            _printers.any((p) => p.name == _selectedPrinter)
                            ? _selectedPrinter
                            : null,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          hintText: 'Seleccione impresora',
                        ),
                        items: _printers
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.name,
                                child: Text(
                                  p.name,
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setState(() => _selectedPrinter = value);
                        },
                      ),

                    const SizedBox(height: 8),
                    Text(
                      '${_printers.length} impresora(s) disponible(s)',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Botón imprimir prueba
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _printing ? null : _printTest,
                  icon: _printing
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.print),
                  label: Text(
                    _printing ? 'IMPRIMIENDO...' : 'IMPRIMIR PÁGINA DE PRUEBA',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Botón configuración completa
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.onConfigurePressed,
                  icon: const Icon(Icons.settings),
                  label: const Text('CONFIGURACIÓN COMPLETA'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.secondary,
                    side: BorderSide(color: scheme.secondary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CERRAR'),
            ),
          ],
        ),
      ),
    );
  }
}
