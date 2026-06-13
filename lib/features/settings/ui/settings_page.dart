import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'backup_database_page.dart';
import 'business_sections_settings_page.dart';
import 'database_settings_page.dart';
import 'device_hardware_settings_page.dart';
import 'permissions_page.dart';
import 'printer_settings_page.dart';
import 'settings_layout.dart';
import 'system_about_page.dart';
import 'users_page.dart' as users_ui;

import '../../license/data/license_models.dart';
import '../../license/services/license_file_storage.dart';
import '../../license/services/license_storage.dart';
import '../../registration/services/business_identity_storage.dart';
import '../../registration/services/business_registration_service.dart';
import '../../registration/services/pending_registration_queue.dart';
import '../../tools/ui/cash_drawer_settings_page.dart';
import '../../tools/ui/scanner_settings_page.dart';
import '../../../theme/app_colors.dart';

/// Pantalla de configuración con diseño de tarjetas
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    final textTheme = theme.textTheme;

    final sections = <_SettingsSectionData>[
      _SettingsSectionData(
        title: 'Negocio',
        description: 'Empresa y ajustes comerciales base del negocio.',
        icon: Icons.storefront_outlined,
        items: [
          _SettingsItemData(
            title: 'Empresa',
            subtitle: 'Datos del negocio, contacto, branding y moneda.',
            icon: Icons.business_outlined,
            onTap: _openCompanySettingsPage,
          ),
          _SettingsItemData(
            title: 'Configuración general',
            subtitle: 'Comportamiento comercial y ajustes base.',
            icon: Icons.tune_outlined,
            onTap: _openPosGeneralSettingsPage,
          ),
        ],
      ),
      _SettingsSectionData(
        title: 'Usuarios y permisos',
        description: 'Cuentas, roles y acceso por módulo.',
        icon: Icons.admin_panel_settings_outlined,
        items: [
          _SettingsItemData(
            title: 'Usuarios',
            subtitle: 'Cuentas, credenciales y estado operativo.',
            icon: Icons.people_outline,
            onTap: _openUsersPage,
          ),
          _SettingsItemData(
            title: 'Roles y permisos',
            subtitle: 'Perfiles por usuario y acceso por módulo.',
            icon: Icons.badge_outlined,
            onTap: _openUserPermissionsPage,
          ),
        ],
      ),
      _SettingsSectionData(
        title: 'Respaldo y base de datos',
        description: 'Copias, restauración, diagnóstico y mantenimiento.',
        icon: Icons.storage_outlined,
        items: [
          _SettingsItemData(
            title: 'Respaldo',
            subtitle: 'Copias, restauración y resguardo local.',
            icon: Icons.backup_outlined,
            onTap: _openBackupPage,
          ),
          _SettingsItemData(
            title: 'Base de datos',
            subtitle: 'Estado, diagnóstico y mantenimiento.',
            icon: Icons.storage_outlined,
            onTap: _openDatabaseSettingsPage,
          ),
        ],
      ),
      _SettingsSectionData(
        title: 'Dispositivos',
        description: 'Impresión, caja y periféricos del terminal.',
        icon: Icons.devices_outlined,
        items: [
          _SettingsItemData(
            title: 'Impresoras',
            subtitle: 'Ticket, pruebas y preferencias de impresión.',
            icon: Icons.print_outlined,
            onTap: _openPrinterSettingsPage,
          ),
          _SettingsItemData(
            title: 'Caja registradora',
            subtitle: 'Apertura automática y prueba de pulso.',
            icon: Icons.point_of_sale_outlined,
            onTap: _openCashDrawerSettingsPage,
          ),
          _SettingsItemData(
            title: 'Lector / scanner',
            subtitle: 'Prefijo, sufijo y tiempo de lectura.',
            icon: Icons.qr_code_scanner_rounded,
            onTap: _openScannerSettingsPage,
          ),
          _SettingsItemData(
            title: 'Hardware y terminal',
            subtitle: 'Accesos técnicos y utilidades del equipo.',
            icon: Icons.memory_outlined,
            onTap: _openHardwareSettingsPage,
          ),
          _SettingsItemData(
            title: 'Acerca de FullPOS',
            subtitle: 'Versión instalada y búsqueda de actualizaciones.',
            icon: Icons.info_outline_rounded,
            onTap: _openSystemAboutPage,
          ),
        ],
      ),
    ];

    final negocioSection = _filterSection(sections[0]);
    final usuariosSection = _filterSection(sections[1]);
    final respaldoSection = _filterSection(sections[2]);
    final dispositivosSection = _filterSection(sections[3]);

    final visibleSections = [
      negocioSection,
      usuariosSection,
      respaldoSection,
      dispositivosSection,
    ].whereType<_SettingsSectionData>().toList(growable: false);

    return Theme(
      data: SettingsLayout.brandedTheme(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final gridSpacing = width >= 1280 ? 20.0 : 16.0;
          final columns = width >= 1360
              ? 3
              : width >= 920
              ? 2
              : 1;

          return SettingsLayout.pageFrame(
            constraints,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSettingsHeader(textTheme),
                const SizedBox(height: 16),
                if (visibleSections.isEmpty)
                  _buildEmptySearchState()
                else
                  LayoutBuilder(
                    builder: (context, gridConstraints) {
                      final sectionWidth = columns == 1
                          ? gridConstraints.maxWidth
                          : (gridConstraints.maxWidth -
                                    ((columns - 1) * gridSpacing)) /
                                columns;

                      final gridSections = [
                        negocioSection,
                        usuariosSection,
                        respaldoSection,
                        dispositivosSection,
                      ].whereType<_SettingsSectionData>();

                      return Wrap(
                        spacing: gridSpacing,
                        runSpacing: 14,
                        children: [
                          for (final section in gridSections)
                            SizedBox(
                              width: sectionWidth,
                              child: _buildSettingsSection(section),
                            ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  _SettingsSectionData? _filterSection(_SettingsSectionData section) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return section;

    final filteredItems = section.items
        .where((item) {
          final haystack =
              '${section.title} ${section.description} ${item.title} ${item.subtitle}'
                  .toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);

    if (filteredItems.isEmpty) return null;
    return section.copyWith(items: filteredItems);
  }

  void _openUsersPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const users_ui.UsersPage()),
    );
  }

  void _openSystemAboutPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SystemAboutPage()),
    );
  }

  void _openUserPermissionsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PermissionsPage()),
    );
  }

  void _openScannerSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScannerSettingsPage()),
    );
  }

  void _openCashDrawerSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CashDrawerSettingsPage()),
    );
  }

  void _openHardwareSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const DeviceHardwareSettingsPage()),
    );
  }

  void _openCompanySettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CompanyProfileSettingsPage()),
    );
  }

  void _openPosGeneralSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PosGeneralSettingsPage()),
    );
  }

  void _openPrinterSettingsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrinterSettingsPage()),
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

  Widget _buildSettingsHeader(TextTheme textTheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useHorizontalLayout = constraints.maxWidth >= 860;

        final titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuración',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Accesos agrupados para escritorio.',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        );

        final searchField = SizedBox(
          width: useHorizontalLayout ? 320 : double.infinity,
          height: 48,
          child: _buildSearchField(),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (useHorizontalLayout)
              Row(
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: 16),
                  searchField,
                ],
              )
            else ...[
              titleBlock,
              const SizedBox(height: 12),
              searchField,
            ],
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.borderSoft),
          ],
        );
      },
    );
  }

  Widget _buildSearchField() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Buscar configuración...',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searchQuery.trim().isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Limpiar',
              ),
        filled: true,
        fillColor: scheme.surfaceVariant.withOpacity(0.28),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderSoft.withOpacity(0.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary.withOpacity(0.42)),
        ),
      ),
    );
  }

  Widget _buildEmptySearchState() {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No se encontraron configuraciones',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Prueba con otro término o limpia la búsqueda.',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(_SettingsSectionData section) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          section.title,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          section.description,
          style: textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < section.items.length; index++) ...[
          _buildSettingsItem(section.items[index]),
          if (index != section.items.length - 1)
            const Divider(height: 1, color: AppColors.borderSoft),
        ],
      ],
    );
  }

  Widget _buildSettingsItem(_SettingsItemData item) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 50, maxHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Icon(
                    item.icon,
                    size: 18,
                    color: AppColors.primaryBlue.withOpacity(0.92),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      if (item.subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.textSecondary,
                            height: 1.1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionData {
  final String title;
  final String description;
  final IconData icon;
  final List<_SettingsItemData> items;

  const _SettingsSectionData({
    required this.title,
    required this.description,
    required this.icon,
    required this.items,
  });

  _SettingsSectionData copyWith({List<_SettingsItemData>? items}) {
    return _SettingsSectionData(
      title: title,
      description: description,
      icon: icon,
      items: items ?? this.items,
    );
  }
}

class _SettingsItemData {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SettingsItemData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
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
  String? _businessId;

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
      final businessId = await _identityStorage.getBusinessId();

      if (!mounted) return;

      setState(() {
        _info = info;
        _source = source;
        _licenseFilePath = file.path;

        final normalized = (businessId ?? '').trim();
        _businessId = normalized.isEmpty ? null : normalized;

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
      await BusinessIdentityStorage().clearProfile();
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

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

    if (daysDiff < 0) return 'Vencida';
    if (daysDiff == 0) return 'Vence hoy';

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
          Expanded(child: Text(value)),
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
                    label: 'Business ID',
                    value: _businessId ?? 'No disponible',
                  ),
                  _infoRow(
                    label: 'Tiempo restante',
                    value: _remainingTimeText(_info),
                  ),
                  _infoRow(
                    label: 'Tipo de licencia',
                    value: (_info?.tipo?.trim().isNotEmpty ?? false)
                        ? _info!.tipo!.trim().toUpperCase()
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
                  _infoRow(label: 'Vence', value: _formatDate(_info?.fechaFin)),
                  _infoRow(label: 'Dispositivos', value: _devicesText(_info)),
                  _infoRow(label: 'Origen', value: _sourceText(_source)),
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
