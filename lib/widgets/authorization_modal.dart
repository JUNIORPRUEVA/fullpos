import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/errors/error_handler.dart';
import '../core/security/app_actions.dart';
import '../core/security/authorization_service.dart';
import '../core/security/security_config.dart';
import '../core/theme/app_status_theme.dart';

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
              debugPrint('AuthorizationModal.show error: $e\n$st');
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
  final TextEditingController _codeController = TextEditingController();
  final FocusNode _codeFocus = FocusNode();
  bool _isProcessing = false;

  ColorScheme get scheme => Theme.of(context).colorScheme;
  AppStatusTheme get status =>
      Theme.of(context).extension<AppStatusTheme>() ??
      AppStatusTheme(
        success: scheme.tertiary,
        warning: scheme.tertiary,
        error: scheme.error,
        info: scheme.primary,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  Future<void> _authorizeWithAdminCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _isProcessing) return;

    setState(() => _isProcessing = true);
    try {
      final result = await AuthorizationService.authorizeWithAdminCode(
        code: code,
        actionCode: widget.action.code,
        resourceType: widget.resourceType,
        resourceId: widget.resourceId,
        companyId: widget.companyId,
        requestedByUserId: widget.requestedByUserId,
        terminalId: widget.terminalId,
      );
      if (!mounted) return;
      if (result.success) {
        Navigator.of(context).pop(true);
      } else {
        _showMessage(result.message);
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('Error autorizando: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted || message.trim().isEmpty) return;
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
    final dialogMaxHeight = math.min(440.0, availableHeight * 0.82);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
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
                _buildHeader(riskLabel),
                const SizedBox(height: 16),
                _buildAuthorizeEntry(),
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
    final borderColor = scheme.outlineVariant.withOpacity(0.6);
    final entryCardColor = scheme.surfaceVariant.withOpacity(0.3);

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
            Text(
              'Código de administración',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Solo un usuario administrador activo puede autorizar esta acción ingresando su código.',
              style: TextStyle(
                color: scheme.onSurface.withOpacity(0.68),
                fontSize: 12,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _codeController,
              focusNode: _codeFocus,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                labelText: 'Código de administración',
                hintText: 'Ingresa el código del administrador',
                prefixIcon: const Icon(Icons.lock_outline),
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
              ),
              onSubmitted: (_) => _authorizeWithAdminCode(),
            ),
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
                onPressed: _isProcessing ? null : _authorizeWithAdminCode,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified_user),
                label: const Text('Autorizar con código'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
