import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/security/app_actions.dart';
import '../core/security/authorization_service.dart';
import '../core/security/scanner_input_controller.dart';
import '../core/security/security_config.dart';
import '../core/services/app_configuration_service.dart';
import '../core/theme/app_status_theme.dart';
import '../core/theme/color_utils.dart';
import '../core/errors/error_handler.dart';

enum _AuthEntryMethod { code, token }

class AuthorizationModal extends StatefulWidget {
  final AppAction action;
  final String resourceType;
  final String? resourceId;
  final int companyId;
  final int requestedByUserId;
  final String terminalId;
  final SecurityConfig config;
  final bool isOnline;

  const AuthorizationModal({
    super.key,
    required this.action,
    required this.resourceType,
    required this.resourceId,
    required this.companyId,
    required this.requestedByUserId,
    required this.terminalId,
    required this.config,
    required this.isOnline,
  });

  static Future<bool>? _pending;

  static Future<bool> show({
    required BuildContext context,
    required AppAction action,
    required String resourceType,
    String? resourceId,
    required int companyId,
    required int requestedByUserId,
    required String terminalId,
    required SecurityConfig config,
    required bool isOnline,
  }) async {
    if (_pending != null) return _pending!;

    // Preferir un context global estable (navigator overlay) para evitar
    // "BuildContext is no longer valid" cuando el caller se disposea.
    final dialogContext = context.mounted
        ? context
        : (ErrorHandler.navigatorKey.currentState?.overlay?.context ??
              ErrorHandler.navigatorKey.currentContext);
    if (dialogContext == null) {
      return false;
    }

    final future =
        showDialog<bool>(
              context: dialogContext,
              barrierDismissible: false,
              builder: (_) => AuthorizationModal(
                action: action,
                resourceType: resourceType,
                resourceId: resourceId,
                companyId: companyId,
                requestedByUserId: requestedByUserId,
                terminalId: terminalId,
                config: config,
                isOnline: isOnline,
              ),
            )
            .then((value) => value ?? false)
            .catchError((e, st) {
              debugPrint('AuthorizationModal.show error: $e\\n$st');
              return false;
            })
            .whenComplete(() => _pending = null);
    _pending = future;
    return future;
  }

  @override
  State<AuthorizationModal> createState() => _AuthorizationModalState();
}

class _AuthorizationModalState extends State<AuthorizationModal> {
  ColorScheme get scheme => Theme.of(context).colorScheme;
  AppStatusTheme get status =>
      Theme.of(context).extension<AppStatusTheme>() ??
      AppStatusTheme(
        success: scheme.tertiary,
        warning: scheme.tertiary,
        error: scheme.error,
        info: scheme.primary,
      );
  Color readableOn(Color bg) => ColorUtils.readableTextColor(bg);

  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _tokenFocus = FocusNode();
  final FocusNode _codeFocus = FocusNode();
  final FocusNode _scannerFocus = FocusNode();
  ScannerInputController? _scanner;
  bool _isProcessing = false;
  _AuthEntryMethod _entryMethod = _AuthEntryMethod.code;
  String? _lastGeneratedToken;
  DateTime? _lastGeneratedExpiry;
  bool _remoteRequesting = false;
  int? _remoteRequestId;
  String? _remoteStatus;
  String? _remoteError;
  int _tokenValidateSeq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.config.scannerEnabled) {
      _scanner = ScannerInputController(
        enabled: true,
        suffix: widget.config.scannerSuffix,
        prefix: widget.config.scannerPrefix,
        timeout: Duration(milliseconds: widget.config.scannerTimeoutMs),
        // Importante: al escribir manualmente, el timeout del scanner puede
        // disparar un "scan" parcial y llamar _validateToken() con un token incompleto.
        // Para typing/paste: solo emitir cuando llegue el sufijo (ej. ENTER).
        emitOnTimeout: false,
        onScan: (data) {
          if (!mounted) return;
          if (_entryMethod != _AuthEntryMethod.token) return;
          _tokenController.text = data.trim();
          _validateToken();
        },
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _codeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _scanner?.dispose();
    _tokenController.dispose();
    _pinController.dispose();
    _tokenFocus.dispose();
    _codeFocus.dispose();
    _scannerFocus.dispose();
    super.dispose();
  }

  String? _resolveRemoteBaseUrl() {
    const fallback = String.fromEnvironment(
      'BACKEND_BASE_URL',
      defaultValue:
          'https://fullpos-proyecto-producion-fullpos-bakend.gcdndd.easypanel.host',
    );
    try {
      final settings = appConfigService.settings;
      final endpoint = settings.cloudEndpoint?.trim();
      if (endpoint != null && endpoint.isNotEmpty) return endpoint;
    } catch (_) {
      // Ignored: fallback will handle missing settings.
    }
    return fallback.isNotEmpty ? fallback : null;
  }

  String? _resolveRemoteApiKey() {
    try {
      final settings = appConfigService.settings;
      final key = settings.cloudApiKey?.trim();
      if (key == null || key.isEmpty) return null;
      return key;
    } catch (_) {
      return null;
    }
  }

  Future<void> _copyText(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _showMessage('$label copiado.');
  }

  Future<void> _requestRemoteApproval() async {
    final baseUrl = _resolveRemoteBaseUrl();
    if (baseUrl == null) {
      _showMessage('Configura la URL de nube para solicitudes remotas.');
      return;
    }

    setState(() {
      _remoteRequesting = true;
      _remoteError = null;
    });
    try {
      final result = await AuthorizationService.createRemoteOverrideRequest(
        baseUrl: baseUrl,
        apiKey: _resolveRemoteApiKey(),
        actionCode: widget.action.code,
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
        companyId: widget.companyId,
        requestedByUserId: widget.requestedByUserId,
        terminalId: widget.terminalId,
        meta: {
          'action_name': widget.action.name,
          'action_desc': widget.action.description,
          'terminal_id': widget.terminalId,
        },
      );
      if (!mounted) return;
      setState(() {
        _remoteRequestId = result.requestId;
        _remoteStatus = result.status;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _remoteError = 'No se pudo crear la solicitud remota.');
    } finally {
      if (mounted) {
        setState(() => _remoteRequesting = false);
      }
    }
  }

  Future<void> _authorizeWithPin() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) return;
    setState(() => _isProcessing = true);
    try {
      final generated = await AuthorizationService.generateOfflinePinToken(
        pin: pin,
        actionCode: widget.action.code,
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
        companyId: widget.companyId,
        requestedByUserId: widget.requestedByUserId,
        terminalId: widget.terminalId,
      );
      final result = await AuthorizationService.validateAndConsumeToken(
        token: generated.token,
        actionCode: widget.action.code,
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
        companyId: widget.companyId,
        usedByUserId: widget.requestedByUserId,
        terminalId: widget.terminalId,
      );
      if (!mounted) return;
      _handleResult(result);
    } catch (e) {
      _showMessage('Error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _generateBarcodeToken() async {
    if (!mounted) return;
    setState(() => _isProcessing = true);
    try {
      final generated = await AuthorizationService.generateLocalBarcodeToken(
        actionCode: widget.action.code,
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
        companyId: widget.companyId,
        requestedByUserId: widget.requestedByUserId,
        terminalId: widget.terminalId,
      );
      if (!mounted) return;
      setState(() {
        _lastGeneratedToken = generated.token;
        _lastGeneratedExpiry = generated.expiresAt;
      });
    } catch (e) {
      _showMessage('No se pudo generar el token: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _validateToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) return;
    if (!mounted) return;
    final seq = ++_tokenValidateSeq;
    setState(() => _isProcessing = true);
    try {
      final allowRemote =
          widget.isOnline &&
          (widget.config.remoteEnabled || widget.config.virtualTokenEnabled);
      final baseUrl = _resolveRemoteBaseUrl();
      if (allowRemote && (baseUrl == null || baseUrl.trim().isEmpty)) {
        _showMessage(
          'Token inválido localmente. Configura la URL/API Key de la nube para validar token virtual.',
        );
        return;
      }

      final result = await AuthorizationService.validateAndConsumeToken(
        token: token,
        actionCode: widget.action.code,
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
        companyId: widget.companyId,
        usedByUserId: widget.requestedByUserId,
        terminalId: widget.terminalId,
        allowRemote: allowRemote,
        remoteBaseUrl: baseUrl,
        remoteApiKey: _resolveRemoteApiKey(),
        remoteRequestId: _remoteRequestId,
      );
      if (!mounted) return;
      if (seq != _tokenValidateSeq) return;
      _handleResult(result);
    } catch (e) {
      _showMessage('Error validando token: $e');
    } finally {
      if (mounted && seq == _tokenValidateSeq) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _handleResult(AuthorizationResult result) {
    if (result.success) {
      Navigator.of(context).pop(true);
    } else {
      _showMessage(result.message);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildHeader(String riskLabel) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: status.warning.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.verified_user, color: status.warning, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Autorización requerida',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Acción: ${widget.action.name}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.action.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Riesgo: $riskLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.65),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rawRisk = widget.action.risk.toString().split('.').last;
    final riskLabel = rawRisk.isEmpty
        ? rawRisk
        : rawRisk[0].toUpperCase() + rawRisk.substring(1);
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    final availableHeight = (media.size.height - media.viewInsets.vertical)
        .clamp(0.0, double.infinity);
    final dialogWidth = math.min(360.0, screenWidth * 0.85);
    final dialogMaxHeight = math.min(520.0, availableHeight * 0.82);
    final contentMaxHeight = math.max(220.0, dialogMaxHeight - 150.0);
    final insetPadding = const EdgeInsets.symmetric(
      horizontal: 18,
      vertical: 20,
    );

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(riskLabel),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: contentMaxHeight),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildAuthorizeEntry(),
                if (widget.config.offlineBarcodeEnabled ||
                    widget.config.remoteEnabled ||
                    widget.config.virtualTokenEnabled) ...[
                  const SizedBox(height: 16),
                  _buildMoreOptions(),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    if (_scanner != null) {
      // Escuchar teclas del scanner sin pelear con el FocusNode del TextField.
      // Esto evita el freeze por FocusNode usado dos veces.
      content = Focus(
        focusNode: _scannerFocus,
        skipTraversal: true,
        onKey: (node, event) {
          if (_entryMethod != _AuthEntryMethod.token) {
            return KeyEventResult.ignored;
          }
          _scanner!.handleKeyEvent(event);
          return KeyEventResult.ignored;
        },
        child: content,
      );
    }

    return Dialog(
      insetPadding: insetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogWidth,
          maxHeight: dialogMaxHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                content,
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isProcessing
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthorizeEntry() {
    final isCode = _entryMethod == _AuthEntryMethod.code;
    final borderColor = scheme.outlineVariant.withOpacity(0.6);

    InputDecoration authDecoration({
      required String label,
      required String hint,
      required IconData icon,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.2),
        ),
        filled: true,
        fillColor: scheme.surfaceVariant.withOpacity(0.2),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
      );
    }

    final entryCardColor = scheme.surfaceVariant.withOpacity(0.3);
    final field = isCode
        ? TextField(
            controller: _pinController,
            focusNode: _codeFocus,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: authDecoration(
              label: 'Código de administración',
              hint: 'Ingresa el PIN del administrador',
              icon: Icons.lock_outline,
            ),
            onSubmitted: (_) => _authorizeWithPin(),
          )
        : TextField(
            controller: _tokenController,
            focusNode: _tokenFocus,
            decoration: authDecoration(
              label: 'Token',
              hint: 'Pega o escanea el token',
              icon: Icons.qr_code_scanner,
            ),
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace'),
            onSubmitted: (_) => _validateToken(),
          );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: entryCardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Autorizar',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                      fontSize: 16,
                    ),
                  ),
                ),
                SegmentedButton<_AuthEntryMethod>(
                  segments: const [
                    ButtonSegment(
                      value: _AuthEntryMethod.code,
                      label: Text('Código'),
                      icon: Icon(Icons.lock_outline, size: 18),
                    ),
                    ButtonSegment(
                      value: _AuthEntryMethod.token,
                      label: Text('Token'),
                      icon: Icon(Icons.qr_code_scanner, size: 18),
                    ),
                  ],
                  selected: {_entryMethod},
                  onSelectionChanged: _isProcessing
                      ? null
                      : (set) {
                          final next = set.first;
                          setState(() => _entryMethod = next);
                          if (next == _AuthEntryMethod.code) {
                            _codeFocus.requestFocus();
                          } else {
                            _tokenFocus.requestFocus();
                          }
                        },
                ),
              ],
            ),
            const SizedBox(height: 16),
            field,
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isProcessing
                    ? null
                    : (isCode ? _authorizeWithPin : _validateToken),
                icon: _isProcessing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_user),
                label: Text(isCode ? 'Autorizar con código' : 'Validar token'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreOptions() {
    final options = <Widget>[];
    if (widget.config.offlineBarcodeEnabled) {
      options.add(_buildBarcodeSection());
    }
    if (widget.config.remoteEnabled || widget.config.virtualTokenEnabled) {
      options.add(_buildRemoteSection());
    }

    if (options.isEmpty) return const SizedBox.shrink();

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Más opciones'),
      children: options,
    );
  }

  // ignore: unused_element
  Widget _buildPinSection() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Método offline: PIN (OTP de un solo uso)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _pinController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'PIN de administrador',
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _authorizeWithPin,
              icon: const Icon(Icons.shield),
              label: const Text('Autorizar con PIN'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarcodeSection() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Método offline: Código local (QR/Barcode)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _generateBarcodeToken,
              icon: const Icon(Icons.qr_code),
              label: const Text('Generar token local'),
            ),
            if (_lastGeneratedToken != null) ...[
              const SizedBox(height: 8),
              const Text('Token generado (escanee con el lector):'),
              SelectableText(
                _lastGeneratedToken!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final qrBaseBg = scheme.surface;
                  final qrBg = qrBaseBg.computeLuminance() < 0.5
                      ? scheme.onSurface
                      : qrBaseBg;
                  final qrFg = readableOn(qrBg);
                  return Center(
                    child: Container(
                      color: qrBg,
                      padding: const EdgeInsets.all(6),
                      child: QrImageView(
                        data: _lastGeneratedToken!,
                        size: 160,
                        backgroundColor: qrBg,
                        foregroundColor: qrFg,
                      ),
                    ),
                  );
                },
              ),
              if (_lastGeneratedExpiry != null)
                Text(
                  'Vence: ${_lastGeneratedExpiry!}',
                  style: TextStyle(color: scheme.onSurface.withOpacity(0.6)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildTokenInputSection() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresar o escanear código',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Token de autorización',
              ),
              onSubmitted: (_) => _validateToken(),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _validateToken,
              icon: const Icon(Icons.verified_user),
              label: const Text('Validar token'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemoteSection() {
    if (!widget.config.remoteEnabled) return const SizedBox.shrink();

    if (!widget.isOnline) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Método remoto requiere internet.',
          style: TextStyle(color: status.warning),
        ),
      );
    }

    final baseUrl = _resolveRemoteBaseUrl();
    if (baseUrl == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Configura la nube para solicitudes remotas.',
          style: TextStyle(color: status.warning),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Método remoto (nube)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Envía una solicitud al dueño para aprobar a distancia.',
            ),
            if (_remoteRequestId != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Solicitud: #${_remoteRequestId!} (${_remoteStatus ?? 'pending'})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _copyText(
                      'ID de solicitud',
                      _remoteRequestId!.toString(),
                    ),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copiar'),
                  ),
                ],
              ),
            ],
            if (_remoteError != null) ...[
              const SizedBox(height: 6),
              Text(_remoteError!, style: TextStyle(color: status.error)),
            ],
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _remoteRequesting ? null : _requestRemoteApproval,
              icon: _remoteRequesting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_done),
              label: const Text('Solicitar permiso remoto'),
            ),
          ],
        ),
      ),
    );
  }
}
