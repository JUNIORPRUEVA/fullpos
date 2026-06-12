import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/services/logout_flow_service.dart';
import '../../features/license/data/license_models.dart';
import '../../features/license/services/license_file_storage.dart';
import '../../features/license/services/license_storage.dart';
import '../../features/registration/services/business_identity_storage.dart';
import '../../features/registration/services/business_registration_service.dart';
import '../../features/registration/services/pending_registration_queue.dart';
import '../../features/settings/data/business_settings_model.dart';
import '../../features/settings/data/business_settings_repository.dart';
import '../../features/settings/data/user_model.dart';
import '../../features/settings/data/users_repository.dart';
import '../config/app_config.dart';
import '../services/cloud_sync_service.dart';
import '../session/session_manager.dart';
import '../session/ui_preferences.dart';
import '../sync/product_sync_service.dart';
import '../ui/app_toast.dart';
import '../window/window_service.dart';
import 'app_side_sheet.dart';

class TopbarUtilityPanels {
  TopbarUtilityPanels._();

  static Future<void> showProfile(BuildContext context) {
    return AppSideSheet.show<void>(
      context,
      icon: Icons.person_outline_rounded,
      title: 'Mi perfil',
      subtitle: 'Cuenta actual, preferencias y accesos personales.',
      child: const _ProfileUtilityPanel(),
      footer: const _PanelFooterHint(
        text: 'Los cambios se aplican a tu sesión actual.',
      ),
    );
  }

  static Future<void> showSupport(BuildContext context) {
    return AppSideSheet.show<void>(
      context,
      icon: Icons.support_agent_rounded,
      title: 'Soporte',
      subtitle: 'Ayuda rápida, contacto y capacitación para el equipo.',
      child: const _SupportUtilityPanel(),
    );
  }

  static Future<void> showLicense(BuildContext context) {
    return AppSideSheet.show<void>(
      context,
      icon: Icons.workspace_premium_outlined,
      title: 'Licencias',
      subtitle: 'Estado comercial y vigencia del sistema.',
      child: const _LicenseUtilityPanel(),
    );
  }

  static Future<void> showCloud(BuildContext context) {
    return AppSideSheet.show<void>(
      context,
      icon: Icons.cloud_outlined,
      title: 'Nube',
      subtitle: 'Resumen simple del estado de sincronización y conexión.',
      child: const _CloudUtilityPanel(),
    );
  }
}

class _PanelFooterHint extends StatelessWidget {
  const _PanelFooterHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
    );
  }
}

class _ProfileUtilityPanel extends StatefulWidget {
  const _ProfileUtilityPanel();

  @override
  State<_ProfileUtilityPanel> createState() => _ProfileUtilityPanelState();
}

class _ProfileUtilityPanelState extends State<_ProfileUtilityPanel> {
  bool _loading = true;
  bool _updatingAvatar = false;
  UserModel? _user;
  String? _username;
  String? _displayName;
  String? _role;
  String? _profileImagePath;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final username = await SessionManager.username();
    final displayName = await SessionManager.displayName();
    final role = await SessionManager.role();
    final user = await AuthRepository.getCurrentUser();

    final userKey = _buildUserKey(user: user, username: username);
    String? profileImagePath;
    if (userKey != null) {
      profileImagePath = await UiPreferences.getProfileImagePath(userKey);
      if (profileImagePath != null && !await File(profileImagePath).exists()) {
        await UiPreferences.setProfileImagePath(userKey, null);
        profileImagePath = null;
      }
    }

    if (!mounted) return;
    setState(() {
      _username = username;
      _displayName = displayName;
      _role = role;
      _user = user;
      _profileImagePath = profileImagePath;
      _loading = false;
    });
  }

  String? _buildUserKey({required UserModel? user, required String? username}) {
    final id = user?.id;
    if (id != null) return 'id:$id';
    final value = username?.trim();
    if (value == null || value.isEmpty) return null;
    return 'u:$value';
  }

  String _sanitizeForFileName(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
    return cleaned.isEmpty ? 'user' : cleaned;
  }

  Future<Directory> _ensureProfileImagesDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docsDir.path, 'profile_images'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<String> _copyProfileImageToAppDir({
    required String userKey,
    required String sourcePath,
  }) async {
    final imagesDir = await _ensureProfileImagesDir();
    final ext = p.extension(sourcePath);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final safeKey = _sanitizeForFileName(userKey);
    final fileName =
        'avatar_${safeKey}_$ts${ext.isEmpty ? '.png' : ext.toLowerCase()}';
    final destPath = p.join(imagesDir.path, fileName);
    final copied = await File(sourcePath).copy(destPath);
    return copied.path;
  }

  Future<void> _pickAndSaveProfileImage() async {
    final user = _user;
    final userKey = _buildUserKey(user: user, username: _username);
    if (user == null || userKey == null || !user.isActiveUser) return;

    final result = await WindowService.runWithSystemDialog(
      () => FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      ),
    );

    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;

    setState(() => _updatingAvatar = true);
    try {
      final copiedPath = await _copyProfileImageToAppDir(
        userKey: userKey,
        sourcePath: path,
      );
      await UiPreferences.setProfileImagePath(userKey, copiedPath);
      if (!mounted) return;
      setState(() => _profileImagePath = copiedPath);
    } finally {
      if (mounted) {
        setState(() => _updatingAvatar = false);
      }
    }
  }

  Future<void> _openEditProfile() async {
    final user = _user;
    if (user == null) return;

    final displayNameCtrl = TextEditingController(text: user.displayName ?? '');
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Editar perfil'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: user.username,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Usuario',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: displayNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre para mostrar',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isNotEmpty && text.length < 2) {
                        return 'Debe tener al menos 2 caracteres.';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() != true) return;
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final updated = user.copyWith(
      displayName: displayNameCtrl.text.trim().isEmpty
          ? null
          : displayNameCtrl.text.trim(),
    );
    await UsersRepository.update(updated);
    await SessionManager.setDisplayName(updated.displayLabel);
    if (!mounted) return;
    setState(() {
      _user = updated;
      _displayName = updated.displayLabel;
    });
    _showSnack('Perfil actualizado correctamente.');
  }

  Future<void> _openChangePassword() async {
    final user = _user;
    if (user == null || user.id == null) return;

    final formKey = GlobalKey<FormState>();
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var showCurrent = false;
    var showNew = false;
    var showConfirm = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocal) {
            return AlertDialog(
              title: const Text('Cambiar contraseña'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (user.hasPassword) ...[
                        TextFormField(
                          controller: currentCtrl,
                          obscureText: !showCurrent,
                          decoration: InputDecoration(
                            labelText: 'Contraseña actual',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () =>
                                  setLocal(() => showCurrent = !showCurrent),
                              icon: Icon(
                                showCurrent
                                    ? Icons.visibility_off_rounded
                                    : Icons.visibility_rounded,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (!user.hasPassword) return null;
                            if ((value ?? '').trim().isEmpty) {
                              return 'Ingresa tu contraseña actual.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: newCtrl,
                        obscureText: !showNew,
                        decoration: InputDecoration(
                          labelText: 'Nueva contraseña',
                          prefixIcon: const Icon(Icons.lock_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setLocal(() => showNew = !showNew),
                            icon: Icon(
                              showNew
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                          ),
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) {
                            return 'Ingresa una contraseña nueva.';
                          }
                          if (text.length < 4) {
                            return 'Debe tener al menos 4 caracteres.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: confirmCtrl,
                        obscureText: !showConfirm,
                        decoration: InputDecoration(
                          labelText: 'Confirmar contraseña',
                          prefixIcon: const Icon(Icons.lock_reset_rounded),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setLocal(() => showConfirm = !showConfirm),
                            icon: Icon(
                              showConfirm
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Confirma la contraseña.';
                          }
                          if (value != newCtrl.text) {
                            return 'Las contraseñas no coinciden.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    if (user.hasPassword) {
      final valid = await UsersRepository.verifyCredentials(
        user.username,
        currentCtrl.text,
      );
      if (valid == null) {
        _showSnack('La contraseña actual no coincide.', isError: true);
        return;
      }
    }

    await UsersRepository.changePassword(user.id!, newCtrl.text);
    if (!mounted) return;
    _showSnack('Contraseña actualizada correctamente.');
    await _loadData();
  }

  Future<void> _openPreferences() async {
    final current = await UiPreferences.isSidebarCollapsed();
    if (!mounted) return;

    var collapsed = current;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setLocal) {
            return AlertDialog(
              title: const Text('Preferencias'),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: SwitchListTile(
                  value: collapsed,
                  onChanged: (value) async {
                    setLocal(() => collapsed = value);
                    await UiPreferences.setSidebarCollapsed(value);
                  },
                  title: const Text('Menú lateral compacto'),
                  subtitle: const Text(
                    'Mantiene el menú colapsado como preferencia por defecto.',
                  ),
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _requestLogout() async {
    await LogoutFlowService.requestLogout(
      context,
      performLogout: () => LogoutFlowService.defaultPerformLogout(context),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? null : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final scheme = Theme.of(context).colorScheme;
    final user = _user;
    final name = (_displayName?.trim().isNotEmpty ?? false)
        ? _displayName!.trim()
        : (_username ?? 'Usuario');
    final roleLabel =
        user?.roleLabel ?? (_role == 'admin' ? 'Administrador' : 'Cajero');
    final statusLabel = user?.isActiveUser == false ? 'Inactivo' : 'Activo';

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: _cardDecoration(),
                  child: Row(
                    children: [
                      _AvatarPreview(
                        imagePath: _profileImagePath,
                        isBusy: _updatingAvatar,
                        onTap: _pickAndSaveProfileImage,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '@${_username ?? 'usuario'}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: const Color(0xFF64748B)),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _PillChip(
                                  icon: Icons.badge_outlined,
                                  label: roleLabel,
                                  color: scheme.primary,
                                ),
                                _PillChip(
                                  icon: Icons.verified_user_outlined,
                                  label: statusLabel,
                                  color: user?.isActiveUser == false
                                      ? const Color(0xFFB45309)
                                      : const Color(0xFF15803D),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionTitle('Resumen de cuenta'),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: _cardDecoration(),
                  child: Column(
                    children: [
                      _InfoLine(label: 'Usuario', value: _username ?? 'N/D'),
                      _InfoLine(label: 'Rol', value: roleLabel),
                      _InfoLine(label: 'Estado', value: statusLabel),
                      _InfoLine(
                        label: 'Empresa',
                        value: user?.companyId.toString() ?? 'N/D',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _SectionTitle('Acciones rápidas'),
                const SizedBox(height: 10),
                _ActionTile(
                  icon: Icons.edit_outlined,
                  title: 'Editar perfil',
                  subtitle: 'Actualiza el nombre mostrado en la sesión.',
                  onTap: _openEditProfile,
                ),
                _ActionTile(
                  icon: Icons.lock_reset_outlined,
                  title: 'Cambiar contraseña',
                  subtitle: 'Mantén segura la cuenta del operador.',
                  onTap: _openChangePassword,
                ),
                _ActionTile(
                  icon: Icons.tune_outlined,
                  title: 'Preferencias',
                  subtitle: 'Ajusta el comportamiento visual personal.',
                  onTap: _openPreferences,
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE7EEF5))),
          ),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _requestLogout,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Cerrar sesión'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFB91C1C),
                side: const BorderSide(color: Color(0xFFF3D0D0)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SupportUtilityPanel extends StatefulWidget {
  const _SupportUtilityPanel();

  @override
  State<_SupportUtilityPanel> createState() => _SupportUtilityPanelState();
}

class _SupportUtilityPanelState extends State<_SupportUtilityPanel> {
  bool _loading = true;
  BusinessSettings? _settings;

  static const List<({IconData icon, String title, String subtitle})> _topics =
      [
        (
          icon: Icons.point_of_sale_outlined,
          title: 'Cómo vender',
          subtitle: 'Abrir un ticket, agregar productos y confirmar la venta.',
        ),
        (
          icon: Icons.payments_outlined,
          title: 'Cómo cobrar',
          subtitle: 'Seleccionar método de pago y finalizar correctamente.',
        ),
        (
          icon: Icons.inventory_2_outlined,
          title: 'Cómo crear productos',
          subtitle: 'Registrar artículos con precio, código y existencias.',
        ),
        (
          icon: Icons.people_outline_rounded,
          title: 'Cómo usar clientes',
          subtitle: 'Asociar clientes, consultar historial y datos básicos.',
        ),
        (
          icon: Icons.backup_outlined,
          title: 'Cómo hacer respaldo',
          subtitle:
              'Proteger la información y mantener copias locales seguras.',
        ),
      ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await BusinessSettingsRepository().loadSettings();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _loading = false;
    });
  }

  String _supportWhatsappLabel() {
    final digits = AppConfig.supportWhatsappNumber;
    if (digits.length < 8) return 'WhatsApp disponible';
    if (digits.length == 12 && digits.startsWith('1')) {
      return '+1 (${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7)}';
    }
    return '+$digits';
  }

  String _sanitizeWhatsappNumber(String raw) {
    return raw.replaceAll(RegExp(r'[^0-9]'), '');
  }

  Future<void> _contactSupport() async {
    final settings = _settings;
    final phone = _sanitizeWhatsappNumber(AppConfig.supportWhatsappNumber);
    if (phone.isEmpty) return;

    final businessName = settings?.businessName.trim().isNotEmpty == true
        ? settings!.businessName.trim()
        : 'mi negocio';
    final message = Uri.encodeComponent(
      'Hola, necesito ayuda con FULLPOS en $businessName.',
    );
    final uri = Uri.parse('${AppConfig.whatsappBaseUrl}/$phone?text=$message');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final settings = _settings;
    final companyEmail = (settings?.email ?? '').trim();
    final companyPhone = (settings?.phone ?? '').trim();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Atención y acompañamiento',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Este espacio está pensado para el cliente final. Aquí verás ayuda útil y canales de contacto, sin logs ni diagnósticos técnicos.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _contactSupport,
                    icon: const Icon(Icons.support_agent_rounded),
                    label: const Text('Contactar soporte'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle('Canales disponibles'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Column(
              children: [
                _InfoLine(label: 'WhatsApp', value: _supportWhatsappLabel()),
                _InfoLine(
                  label: 'Correo del negocio',
                  value: companyEmail.isEmpty ? 'No configurado' : companyEmail,
                ),
                _InfoLine(
                  label: 'Teléfono del negocio',
                  value: companyPhone.isEmpty ? 'No configurado' : companyPhone,
                ),
                const _InfoLine(
                  label: 'Horario',
                  value: 'Atención en horario comercial.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle('Capacitación rápida'),
          const SizedBox(height: 10),
          for (final topic in _topics)
            _ActionTile(
              icon: topic.icon,
              title: topic.title,
              subtitle: topic.subtitle,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${topic.title}: este bloque resume la guía básica para el equipo.',
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Si necesitas una capacitación más completa, usa el botón de contacto y solicita apoyo guiado para tu equipo.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseUtilityPanel extends StatefulWidget {
  const _LicenseUtilityPanel();

  @override
  State<_LicenseUtilityPanel> createState() => _LicenseUtilityPanelState();
}

class _LicenseUtilityPanelState extends State<_LicenseUtilityPanel> {
  final LicenseStorage _licenseStorage = LicenseStorage();
  final LicenseFileStorage _licenseFileStorage = LicenseFileStorage();
  final BusinessIdentityStorage _identityStorage = BusinessIdentityStorage();
  final BusinessRegistrationService _registrationService =
      BusinessRegistrationService();

  bool _loading = true;
  LicenseInfo? _info;
  String? _source;
  String? _licenseFilePath;
  String? _businessId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
        _businessId = (businessId ?? '').trim().isEmpty ? null : businessId;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'No disponible';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  String _remainingTimeText(LicenseInfo? info) {
    final end = info?.fechaFin;
    if (info == null) return 'No disponible';
    if (end == null) return 'Sin vencimiento visible';
    final days = end.difference(DateTime.now()).inDays;
    if (days < 0) return 'Vencida';
    if (days == 0) return 'Vence hoy';
    if (days == 1) return '1 día restante';
    return '$days días restantes';
  }

  String _statusText(LicenseInfo? info) {
    if (info == null) return 'Sin licencia registrada';
    if (info.isBlocked) return 'Bloqueada';
    if (info.isExpired) return 'Vencida';
    if (info.isActive) return 'Activa';
    return (info.estado ?? 'Pendiente').trim();
  }

  Color _statusColor(LicenseInfo? info) {
    if (info == null) return const Color(0xFF94A3B8);
    if (info.isBlocked || info.isExpired) return const Color(0xFFB91C1C);
    if (info.isActive) return const Color(0xFF15803D);
    return const Color(0xFFB45309);
  }

  String _sourceText() {
    switch ((_source ?? '').trim().toLowerCase()) {
      case 'cloud':
        return 'Servidor';
      case 'offline':
        return 'Archivo local';
      default:
        return 'No disponible';
    }
  }

  String _maskLicenseKey(String value) {
    final text = value.trim();
    if (text.isEmpty) return 'No disponible';
    if (text.length <= 8) return '****';
    return '${text.substring(0, 4)}...${text.substring(text.length - 4)}';
  }

  Future<void> _debugResetLicense() async {
    if (!kDebugMode) return;
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Licencia reseteada (debug).')),
    );
    await _load();
  }

  Future<void> _debugResendRegistrationToCloud() async {
    if (!kDebugMode) return;
    final identity = await _identityStorage.getIdentity();
    if (identity == null) return;

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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Registro reenviado a nube (debug).')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final info = _info;
    final statusColor = _statusColor(info);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _PillChip(
                      icon: Icons.verified_outlined,
                      label: _statusText(info),
                      color: statusColor,
                    ),
                    _PillChip(
                      icon: Icons.schedule_outlined,
                      label: _remainingTimeText(info),
                      color: const Color(0xFF2563EB),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'La licencia controla vigencia, estado comercial y validación del negocio.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle('Resumen comercial'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Column(
              children: [
                _InfoLine(label: 'Estado', value: _statusText(info)),
                _InfoLine(
                  label: 'Tipo de licencia',
                  value: (info?.tipo ?? 'No disponible').trim().isEmpty
                      ? 'No disponible'
                      : info!.tipo!.trim().toUpperCase(),
                ),
                _InfoLine(
                  label: 'Tiempo restante',
                  value: _remainingTimeText(info),
                ),
                _InfoLine(
                  label: 'Inicio',
                  value: _formatDate(info?.fechaInicio),
                ),
                _InfoLine(
                  label: 'Vencimiento',
                  value: _formatDate(info?.fechaFin),
                ),
                _InfoLine(
                  label: 'Business ID',
                  value: _businessId ?? 'No disponible',
                ),
                _InfoLine(label: 'Origen', value: _sourceText()),
                _InfoLine(
                  label: 'Última revisión',
                  value: _formatDate(info?.lastCheckedAt),
                ),
                _InfoLine(
                  label: 'Licencia',
                  value: _maskLicenseKey(info?.licenseKey ?? ''),
                ),
              ],
            ),
          ),
          if ((_licenseFilePath ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Ubicación local: ${_licenseFilePath!.trim()}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
            ),
          ],
          if (kDebugMode) ...[
            const SizedBox(height: 16),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Herramientas internas'),
              subtitle: const Text('Solo visible en modo debug.'),
              children: [
                _ActionTile(
                  icon: Icons.refresh_rounded,
                  title: 'Reset licencia (debug)',
                  subtitle: 'Limpia la licencia local y el estado de prueba.',
                  onTap: _debugResetLicense,
                ),
                _ActionTile(
                  icon: Icons.cloud_upload_outlined,
                  title: 'Reenviar registro a nube (debug)',
                  subtitle: 'Reintenta el registro del negocio en la nube.',
                  onTap: _debugResendRegistrationToCloud,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CloudUtilityPanel extends StatefulWidget {
  const _CloudUtilityPanel();

  @override
  State<_CloudUtilityPanel> createState() => _CloudUtilityPanelState();
}

class _CloudUtilityPanelState extends State<_CloudUtilityPanel> {
  bool _loading = true;
  bool _changingCloudState = false;
  bool _syncingNow = false;
  bool _reconnecting = false;
  bool _refreshing = false;
  Map<String, dynamic>? _summary;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload({bool showLoading = false}) async {
    if (showLoading && mounted) {
      setState(() => _loading = true);
    }
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      final companyId = await SessionManager.companyId();
      final syncRows = await CloudSyncService.instance.readSyncStatusRows();
      final productRows = await ProductSyncService.instance.readStatusRows();
      final productPendingCount = await ProductSyncService.instance
          .pendingCount();
      final lastProductSuccess = await ProductSyncService.instance
          .lastSuccessAtMs();
      final wsState = ProductSyncService.instance.connectionState.value;

      Map<String, dynamic>? findTarget(String target) {
        for (final row in syncRows) {
          if ((row['target'] as String?) == target) return row;
        }
        return null;
      }

      DateTime? parseMs(dynamic value) {
        if (value is! int) return null;
        return DateTime.fromMillisecondsSinceEpoch(value);
      }

      DateTime? latest(DateTime? current, DateTime? candidate) {
        if (candidate == null) return current;
        if (current == null || candidate.isAfter(current)) return candidate;
        return current;
      }

      String aggregateProductStatus() {
        final statuses = productRows
            .map((row) => (row['status'] as String?)?.toLowerCase() ?? '')
            .toSet();
        if (statuses.any(
          const {'failed', 'error', 'rejected', 'conflict'}.contains,
        )) {
          return 'failed';
        }
        if (statuses.contains('syncing')) return 'syncing';
        if (statuses.any(const {'pending', 'queued'}.contains)) {
          return 'pending';
        }
        if (lastProductSuccess != null) return 'synced';
        return (findTarget('products')?['status'] as String?) ?? 'idle';
      }

      final targets = <Map<String, dynamic>>[];
      DateTime? latestSync;
      var targetPendingCount = 0;
      for (final row in syncRows) {
        final target = (row['target'] as String?)?.trim() ?? '';
        if (target.isEmpty) continue;
        var status = (row['status'] as String?)?.toLowerCase() ?? 'idle';
        var lastSuccess = parseMs(row['last_success_at_ms']);
        if (target == 'products') {
          status = aggregateProductStatus();
          lastSuccess = latest(lastSuccess, parseMs(lastProductSuccess));
        }
        if (const {
          'pending',
          'queued',
          'syncing',
          'failed',
          'error',
        }.contains(status)) {
          targetPendingCount++;
        }
        latestSync = latest(latestSync, lastSuccess);
        targets.add({
          'target': target,
          'status': status,
          'lastSuccess': lastSuccess,
        });
      }

      void ensureTarget(String target, String status, DateTime? lastSuccess) {
        if (targets.any((row) => row['target'] == target)) return;
        targets.add({
          'target': target,
          'status': status,
          'lastSuccess': lastSuccess,
        });
        latestSync = latest(latestSync, lastSuccess);
      }

      final productStatus = aggregateProductStatus();
      final productLastSuccess = parseMs(lastProductSuccess);
      final salesRow = findTarget('sales');
      final salesStatus =
          (salesRow?['status'] as String?)?.toLowerCase() ?? 'idle';
      final salesLastSuccess = parseMs(salesRow?['last_success_at_ms']);
      ensureTarget('products', productStatus, productLastSuccess);
      ensureTarget('sales', salesStatus, salesLastSuccess);

      final pendingCount = productPendingCount + targetPendingCount;
      final hasFailedStatus = targets.any(
        (row) => const {
          'failed',
          'error',
          'rejected',
          'conflict',
        }.contains(row['status']),
      );

      if (!mounted) return;
      setState(() {
        _summary = {
          'settings': settings,
          'companyId': companyId,
          'pendingCount': pendingCount,
          'wsState': wsState,
          'latestSync': latestSync,
          'productStatus': productStatus,
          'salesStatus': salesStatus,
          'targets': targets,
          'hasFailedStatus': hasFailedStatus,
        };
        _loadError = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Revisa tu conexión e intenta actualizar el estado.';
        _loading = false;
      });
    }
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return 'Sin sincronización reciente';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/${local.year} · $hour:$minute';
  }

  String _statusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'connected':
        return 'Conectado';
      case 'disconnected':
        return 'Desconectado';
      case 'connecting':
        return 'Conectando';
      case 'synced':
        return 'Sincronizado';
      case 'syncing':
        return 'Sincronizando';
      case 'pending':
      case 'queued':
        return 'Pendiente';
      case 'idle':
        return 'Sin actividad todavía';
      case 'disabled':
        return 'Desactivado';
      case 'failed':
      case 'error':
      case 'rejected':
      case 'conflict':
        return 'Con incidencias';
      default:
        return 'Sin actividad todavía';
    }
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'connected':
      case 'synced':
        return const Color(0xFF15803D);
      case 'connecting':
      case 'syncing':
        return const Color(0xFF2563EB);
      case 'pending':
      case 'queued':
        return const Color(0xFFB45309);
      case 'failed':
      case 'error':
      case 'rejected':
      case 'conflict':
        return const Color(0xFFB91C1C);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _targetLabel(String target) {
    return switch (target) {
      'users' => 'Usuarios',
      'company_config' => 'Configuración del negocio',
      'clients' => 'Clientes',
      'categories' => 'Categorías',
      'suppliers' => 'Proveedores',
      'products' => 'Productos',
      'sales' => 'Ventas',
      'payments' => 'Pagos',
      'returns' => 'Devoluciones',
      'cash' => 'Caja',
      'quotes' => 'Cotizaciones',
      _ => 'Datos de la nube',
    };
  }

  IconData _targetIcon(String target) {
    return switch (target) {
      'products' => Icons.inventory_2_outlined,
      'sales' => Icons.receipt_long_outlined,
      'clients' => Icons.people_outline_rounded,
      'categories' => Icons.category_outlined,
      'suppliers' => Icons.local_shipping_outlined,
      'payments' => Icons.payments_outlined,
      'returns' => Icons.assignment_return_outlined,
      'cash' => Icons.point_of_sale_outlined,
      'quotes' => Icons.request_quote_outlined,
      'users' => Icons.manage_accounts_outlined,
      'company_config' => Icons.tune_rounded,
      _ => Icons.cloud_sync_outlined,
    };
  }

  void _showFeedback(String message, {AppToastType type = AppToastType.info}) {
    if (!mounted) return;
    AppToast.show(context, message, type: type);
  }

  Future<bool> _confirmDisable() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desactivar sincronización'),
        content: const Text(
          'Los datos seguirán disponibles localmente, pero los nuevos cambios '
          'no se enviarán a la nube hasta que vuelvas a activarla.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _changeCloudState(bool enabled) async {
    if (_changingCloudState) return;
    if (!enabled && !await _confirmDisable()) return;
    if (!mounted) return;
    setState(() => _changingCloudState = true);
    try {
      final current =
          (_summary?['settings'] as BusinessSettings?) ??
          await BusinessSettingsRepository().loadSettings();
      final updated = current.copyWith(cloudEnabled: enabled);
      await BusinessSettingsRepository().saveSettings(updated);

      if (enabled) {
        CloudSyncService.instance.startRealtimeSyncEngine();
        ProductSyncService.instance.start();
        await Future.wait([
          CloudSyncService.instance.syncProductsIfEnabled(),
          CloudSyncService.instance.syncSalesIfEnabled(),
        ]);
        await CloudSyncService.instance.retryAllFailedSyncNow();
        await ProductSyncService.instance.retryFailedNow();
        await ProductSyncService.instance.flushNow();
      } else {
        CloudSyncService.instance.stopRealtimeSyncEngine();
        ProductSyncService.instance.stop();
      }
      await _reload();
      _showFeedback(
        enabled
            ? 'Sincronización en la nube activada.'
            : 'Sincronización en la nube desactivada.',
        type: AppToastType.success,
      );
    } catch (_) {
      _showFeedback(
        'No pudimos cambiar la configuración de la nube. Intenta nuevamente.',
        type: AppToastType.error,
      );
      await _reload();
    } finally {
      if (mounted) setState(() => _changingCloudState = false);
    }
  }

  Future<void> _syncNow() async {
    final settings = _summary?['settings'] as BusinessSettings?;
    if (settings == null || !settings.cloudEnabled || _syncingNow) return;
    setState(() => _syncingNow = true);
    try {
      CloudSyncService.instance.startRealtimeSyncEngine();
      ProductSyncService.instance.start();
      final results = await Future.wait([
        CloudSyncService.instance.syncProductsIfEnabled(),
        CloudSyncService.instance.syncSalesIfEnabled(),
      ]);
      await CloudSyncService.instance.retryAllFailedSyncNow();
      await ProductSyncService.instance.retryFailedNow();
      await ProductSyncService.instance.flushNow();
      if (results.any((ok) => !ok)) {
        throw StateError('cloud_sync_incomplete');
      }
      await _reload();
      _showFeedback(
        'Sincronización completada correctamente.',
        type: AppToastType.success,
      );
    } catch (_) {
      _showFeedback(
        'No se pudo completar la sincronización. Revisa la conexión e inténtalo de nuevo.',
        type: AppToastType.error,
      );
      await _reload();
    } finally {
      if (mounted) setState(() => _syncingNow = false);
    }
  }

  Future<void> _reconnect() async {
    final settings = _summary?['settings'] as BusinessSettings?;
    if (settings == null || !settings.cloudEnabled || _reconnecting) return;
    setState(() => _reconnecting = true);
    try {
      ProductSyncService.instance.stop();
      CloudSyncService.instance.stopRealtimeSyncEngine();
      CloudSyncService.instance.startRealtimeSyncEngine();
      ProductSyncService.instance.start();
      await ProductSyncService.instance.flushNow();
      await _reload();
      _showFeedback(
        'Conexión con la nube reiniciada.',
        type: AppToastType.success,
      );
    } catch (_) {
      _showFeedback(
        'No se pudo restablecer la conexión con la nube.',
        type: AppToastType.error,
      );
      await _reload();
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  Future<void> _refreshStatus() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await _reload();
    if (!mounted) return;
    setState(() => _refreshing = false);
  }

  Widget _buildSyncTargetsSection(List<Map<String, dynamic>> targets) {
    final theme = Theme.of(context);
    return Container(
      decoration: _cardDecoration(),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          Icons.sync_rounded,
          size: 20,
          color: const Color(0xFF2563EB),
        ),
        title: Text(
          'Datos sincronizados',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F172A),
          ),
        ),
        subtitle: Text(
          '${targets.length} elementos · Toca para ver detalle',
          style: theme.textTheme.bodySmall?.copyWith(
            color: const Color(0xFF64748B),
          ),
        ),
        children: [
          for (var index = 0; index < targets.length; index++) ...[
            _CloudTargetRow(
              icon: _targetIcon(targets[index]['target'] as String),
              name: _targetLabel(targets[index]['target'] as String),
              status: _statusLabel(targets[index]['status'] as String),
              statusColor: _statusColor(
                targets[index]['status'] as String,
              ),
              lastSync: _formatDateTime(
                targets[index]['lastSuccess'] as DateTime?,
              ),
            ),
            if (index != targets.length - 1)
              const Divider(height: 1, color: Color(0xFFE7EEF5)),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_loadError != null || _summary == null) {
      return _CloudErrorState(
        description:
            _loadError ?? 'Revisa tu conexión e intenta actualizar el estado.',
        onRetry: () => _reload(showLoading: true),
      );
    }

    final summary = _summary!;
    final settings = summary['settings'] as BusinessSettings;
    final wsState = summary['wsState'] as String;
    final latestSync = summary['latestSync'] as DateTime?;
    final productStatus = summary['productStatus'] as String;
    final salesStatus = summary['salesStatus'] as String;
    final pendingCount = summary['pendingCount'] as int;
    final targets = (summary['targets'] as List).cast<Map<String, dynamic>>();
    final hasFailedStatus = summary['hasFailedStatus'] as bool;
    final isCloudEnabled = settings.cloudEnabled;
    final busy =
        _changingCloudState || _syncingNow || _reconnecting || _refreshing;

    late final String overallTitle;
    late final String overallDescription;
    late final Color overallColor;
    late final IconData overallIcon;
    if (!isCloudEnabled) {
      overallTitle = 'Nube desactivada';
      overallDescription =
          'La aplicación está trabajando únicamente con los datos guardados en este equipo.';
      overallColor = const Color(0xFFB45309);
      overallIcon = Icons.cloud_off_outlined;
    } else if (wsState == 'connecting') {
      overallTitle = 'Conectando con la nube';
      overallDescription =
          'Estamos intentando establecer la conexión en tiempo real.';
      overallColor = const Color(0xFF2563EB);
      overallIcon = Icons.cloud_sync_outlined;
    } else if (wsState != 'connected' || hasFailedStatus) {
      overallTitle = 'Conexión interrumpida';
      overallDescription =
          'No se pudo mantener la conexión con la nube. Puedes intentar reconectar.';
      overallColor = const Color(0xFFB91C1C);
      overallIcon = Icons.cloud_off_outlined;
    } else if (pendingCount > 0 ||
        const {'syncing', 'pending', 'queued'}.contains(productStatus) ||
        const {'syncing', 'pending', 'queued'}.contains(salesStatus)) {
      overallTitle = 'Sincronización pendiente';
      overallDescription = pendingCount == 1
          ? 'Hay 1 elemento pendiente de envío.'
          : 'Hay $pendingCount elementos pendientes de envío.';
      overallColor = const Color(0xFFB45309);
      overallIcon = Icons.cloud_sync_outlined;
    } else {
      overallTitle = 'Todo sincronizado';
      overallDescription = 'Los datos locales y la nube están actualizados.';
      overallColor = const Color(0xFF15803D);
      overallIcon = Icons.cloud_done_outlined;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.cloud_sync_outlined,
                    color: Color(0xFF2563EB),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sincronización en la nube',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isCloudEnabled
                            ? 'Los cambios se envían y reciben automáticamente.'
                            : 'Actívala para mantener tus datos actualizados.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (_changingCloudState)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  Switch.adaptive(
                    value: isCloudEnabled,
                    onChanged: busy ? null : _changeCloudState,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: overallColor.withOpacity(0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: overallColor.withOpacity(0.20)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(overallIcon, color: overallColor, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        overallTitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: overallColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        overallDescription,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF475569),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionTitle('Estado actual'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Column(
              children: [
                _InfoLine(
                  label: 'Estado de la nube',
                  value: isCloudEnabled ? 'Activa' : 'Desactivada',
                ),
                _InfoLine(
                  label: 'Conexión en tiempo real',
                  value: isCloudEnabled ? _statusLabel(wsState) : 'Desactivada',
                ),
                _InfoLine(
                  label: 'Última sincronización',
                  value: _formatDateTime(latestSync),
                ),
                _InfoLine(
                  label: 'Empresa en sesión',
                  value: '${summary['companyId'] ?? 'No disponible'}',
                ),
                _InfoLine(
                  label: 'Productos',
                  value: _statusLabel(productStatus),
                ),
                _InfoLine(label: 'Ventas', value: _statusLabel(salesStatus)),
                _InfoLine(
                  label: 'Pendientes',
                  value: pendingCount == 1
                      ? '1 elemento'
                      : '$pendingCount elementos',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildSyncTargetsSection(targets),
          const SizedBox(height: 16),
          _SectionTitle('Acciones'),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.sync_rounded,
            title: 'Sincronizar ahora',
            subtitle: isCloudEnabled
                ? 'Envía pendientes y refresca el estado de la nube.'
                : 'Activa la nube para enviar cambios pendientes.',
            onTap: _syncNow,
            enabled: isCloudEnabled && !busy,
            isBusy: _syncingNow,
          ),
          _ActionTile(
            icon: Icons.monitor_heart_outlined,
            title: 'Actualizar estado',
            subtitle: 'Actualiza los datos visibles sin salir de este panel.',
            onTap: _refreshStatus,
            enabled: !busy,
            isBusy: _refreshing,
          ),
          _ActionTile(
            icon: Icons.wifi_protected_setup_rounded,
            title: 'Reconectar',
            subtitle:
                'Reinicia la conexión en tiempo real y vuelve a comprobar.',
            onTap: _reconnect,
            enabled: isCloudEnabled && !busy,
            isBusy: _reconnecting,
          ),
        ],
      ),
    );
  }
}

class _CloudTargetRow extends StatelessWidget {
  const _CloudTargetRow({
    required this.icon,
    required this.name,
    required this.status,
    required this.statusColor,
    required this.lastSync,
  });

  final IconData icon;
  final String name;
  final String status;
  final Color statusColor;
  final String lastSync;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF2563EB)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$status · $lastSync',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudErrorState extends StatelessWidget {
  const _CloudErrorState({required this.description, required this.onRetry});

  final String description;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 42,
              color: Color(0xFFB91C1C),
            ),
            const SizedBox(height: 14),
            Text(
              'No pudimos consultar la nube',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => unawaited(onRetry()),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({
    required this.imagePath,
    required this.isBusy,
    required this.onTap,
  });

  final String? imagePath;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 74,
      height: 74,
      child: ClipOval(
        child: Material(
          color: scheme.primary.withOpacity(0.10),
          child: InkWell(
            onTap: isBusy ? null : onTap,
            child: imagePath != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(
                        File(imagePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Icon(
                          Icons.person_rounded,
                          size: 34,
                          color: scheme.primary,
                        ),
                      ),
                      if (isBusy)
                        const ColoredBox(
                          color: Color(0xAAFFFFFF),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.person_rounded,
                        size: 34,
                        color: scheme.primary,
                      ),
                      if (isBusy)
                        const ColoredBox(
                          color: Color(0xAAFFFFFF),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        color: const Color(0xFF0F172A),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
    this.isBusy = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final FutureOr<void> Function() onTap;
  final bool enabled;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: _cardDecoration(),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? () => unawaited(Future.sync(onTap)) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color:
                      (enabled
                              ? const Color(0xFF2563EB)
                              : const Color(0xFF94A3B8))
                          .withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isBusy
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        icon,
                        color: enabled
                            ? const Color(0xFF2563EB)
                            : const Color(0xFF94A3B8),
                        size: 20,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: enabled
                            ? const Color(0xFF0F172A)
                            : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: const Color(0xFFE2EAF3)),
  );
}
