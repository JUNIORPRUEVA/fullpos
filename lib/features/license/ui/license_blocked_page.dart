import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/brand/fullpos_brand_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/window/window_service.dart';
import '../../registration/services/business_identity_storage.dart';
import '../license_config.dart';
import '../services/business_license_sync.dart';
import '../services/license_controller.dart';
import '../services/license_storage.dart';
import '../services/license_gate_refresh.dart';

class LicenseBlockedPage extends ConsumerStatefulWidget {
  const LicenseBlockedPage({super.key});

  @override
  ConsumerState<LicenseBlockedPage> createState() => _LicenseBlockedPageState();
}

class _LicenseBlockedPageState extends ConsumerState<LicenseBlockedPage> {
  StreamSubscription<String>? _sseSub;
  HttpClient? _httpClient;
  bool _disposed = false;
  String? _licenseFileStatus;

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopListening();
    super.dispose();
  }

  void _stopListening() {
    try {
      _sseSub?.cancel();
    } catch (_) {}
    _sseSub = null;

    try {
      _httpClient?.close(force: true);
    } catch (_) {}
    _httpClient = null;
  }

  Future<void> _startListening() async {
    final businessId = (await BusinessIdentityStorage().getBusinessId())
        ?.trim();
    if (businessId == null || businessId.isEmpty) return;

    // Reintentos simples: mientras la pantalla esté montada.
    Future<void> loop() async {
      while (!_disposed && mounted) {
        try {
          await _connectAndListen(businessId);
        } catch (_) {
          // ignore and retry
        }
        if (_disposed || !mounted) return;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }

    unawaited(loop());
  }

  Future<void> _connectAndListen(String businessId) async {
    _stopListening();
    _httpClient = HttpClient();
    _httpClient!.idleTimeout = const Duration(seconds: 15);

    final base = AppConfig.normalizeBaseUrl(kLicenseBackendBaseUrl);

    // Try new route first, fallback to legacy /api prefix.
    final paths = <String>[
      '/businesses/$businessId/license/stream',
      '/api/businesses/$businessId/license/stream',
    ];

    HttpClientResponse? response;
    for (final path in paths) {
      try {
        final uri = Uri.parse(base).replace(path: path);
        final req = await _httpClient!.getUrl(uri);
        req.headers.set('accept', 'text/event-stream');
        req.headers.set('cache-control', 'no-cache');
        response = await req.close();
        if (response.statusCode >= 200 && response.statusCode < 300) {
          break;
        }
      } catch (_) {
        // try next
      }
    }

    if (response == null ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw Exception('SSE connect failed');
    }

    String? currentEvent;
    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    _sseSub = lines.listen(
      (line) async {
        final trimmed = line.trimRight();
        if (trimmed.isEmpty) {
          currentEvent = null;
          return;
        }
        if (trimmed.startsWith('event:')) {
          currentEvent = trimmed.substring('event:'.length).trim();
          return;
        }
        if (trimmed.startsWith('data:')) {
          final ev = (currentEvent ?? '').trim();
          if (ev == 'license_changed') {
            await _onLicenseChanged();
          }
          return;
        }
      },
      onError: (_) {},
      onDone: () {},
      cancelOnError: true,
    );
  }

  Future<void> _onLicenseChanged() async {
    // Al recibir el push, refrescar de inmediato desde la nube.
    final sync = BusinessLicenseSync();
    final changed = await sync.tryPollFromCloudIfDue(
      minInterval: Duration.zero,
      ignoreMinInterval: true,
      networkTimeout: const Duration(seconds: 2),
    );
    if (changed) {
      bumpLicenseGateRefresh();
      if (mounted) setState(() {}); // para refrescar el motivo en pantalla
    }
  }

  Future<void> _verifyNow() async {
    final controller = ref.read(licenseControllerProvider.notifier);
    await controller.syncBusinessLicenseNow();
    if (!mounted) return;
    final state = ref.read(licenseControllerProvider);
    if (state.info?.isActive == true && state.info?.isExpired == false) {
      context.go('/login');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'La licencia aún no está activa. Intenta de nuevo en unos momentos.',
        ),
      ),
    );
  }

  Future<void> _pickAndApplyLicenseFile() async {
    final controller = ref.read(licenseControllerProvider.notifier);
    final result = await WindowService.runWithSystemDialog(
      () => FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'dat', 'fulllicense'],
        withData: true,
        lockParentWindow: true,
      ),
    );
    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    String raw;
    if (file.bytes != null) {
      raw = utf8.decode(file.bytes!, allowMalformed: true);
    } else if (file.path != null && file.path!.trim().isNotEmpty) {
      raw = await File(file.path!).readAsString();
    } else {
      setState(() {
        _licenseFileStatus = 'No se pudo leer el archivo seleccionado.';
      });
      return;
    }

    raw = raw.trimLeft();
    if (raw.startsWith('\uFEFF')) {
      raw = raw.substring(1);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      setState(() {
        _licenseFileStatus = 'El archivo no tiene formato JSON válido.';
      });
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      setState(() {
        _licenseFileStatus = 'Formato inválido: se esperaba un objeto JSON.';
      });
      return;
    }

    final normalized = _normalizeUploadedLicenseFile(decoded);
    if (normalized == null) {
      setState(() {
        _licenseFileStatus = 'Formato inválido: faltan payload y signature.';
      });
      return;
    }

    await controller.applyOfflineLicenseFile(normalized);
    final state = ref.read(licenseControllerProvider);
    if (!mounted) return;
    setState(() {
      _licenseFileStatus = state.error?.trim().isNotEmpty == true
          ? state.error
          : (state.info?.isActive == true && state.info?.isExpired == false)
          ? 'Licencia aplicada correctamente.'
          : 'Archivo validado. Verifica el estado.';
    });
    if (state.info?.isActive == true &&
        state.info?.isExpired == false &&
        mounted) {
      context.go('/login');
    }
  }

  Map<String, dynamic>? _normalizeUploadedLicenseFile(
    Map<String, dynamic> input,
  ) {
    final payload = input['payload'];
    final signature = (input['signature'] ?? '').toString().trim();
    if (payload is Map && signature.isNotEmpty) {
      return {
        'payload': payload.cast<String, dynamic>(),
        'signature': signature,
        'alg': (input['alg'] ?? 'Ed25519').toString().trim(),
      };
    }
    final nested = input['license'];
    if (nested is Map<String, dynamic>) {
      final nestedPayload = nested['payload'];
      final nestedSignature = (nested['signature'] ?? '').toString().trim();
      if (nestedPayload is Map && nestedSignature.isNotEmpty) {
        return {
          'payload': nestedPayload.cast<String, dynamic>(),
          'signature': nestedSignature,
          'alg': (nested['alg'] ?? 'Ed25519').toString().trim(),
        };
      }
    }
    return null;
  }

  static const String _supportPhoneDisplay = '8295319442';
  static const String _supportPhoneWhatsapp = '18295319442';

  Future<void> _openWhatsapp(
    BuildContext context, {
    required String message,
  }) async {
    final uri = Uri.parse(
      '${AppConfig.whatsappBaseUrl}/$_supportPhoneWhatsapp',
    ).replace(queryParameters: {'text': message});
    final url = uri.toString();

    await WindowService.runWithExternalApplication(() async {
      await WindowService.minimize();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final ok = await launchUrlString(
        url,
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gradient = FullposBrandTheme.backgroundGradient;

    final onSurface = scheme.onSurface;
    final mutedText = onSurface.withOpacity(0.72);
    final cardBorder = scheme.primary.withOpacity(0.18);

    return Scaffold(
      backgroundColor: scheme.background,
      body: Container(
        decoration: BoxDecoration(gradient: gradient),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.paddingL),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                color: scheme.surface,
                elevation: 14,
                shadowColor: Colors.black.withOpacity(0.24),
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: cardBorder),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 28,
                  ),
                  child: FutureBuilder(
                    future: LicenseStorage().getLastInfo(),
                    builder: (context, snapshot) {
                      final info = snapshot.data;
                      final motivo = (info?.motivo ?? '').trim();
                      final deviceId = (info?.deviceId ?? '').trim();
                      final licenseKey = (info?.licenseKey ?? '').trim();
                      final projectCode = (info?.projectCode ?? '').trim();

                      final messageLines = <String>[
                        'Hola soporte, mi FULLPOS está BLOQUEADO y necesito ayuda.',
                        '',
                        'Device ID: ${deviceId.isNotEmpty ? deviceId : '-'}',
                        'Proyecto: ${projectCode.isNotEmpty ? projectCode : '-'}',
                        'Licencia: ${licenseKey.isNotEmpty ? licenseKey : '-'}',
                        if (motivo.isNotEmpty) 'Motivo: $motivo',
                      ];
                      final whatsappMessage = messageLines.join('\n');

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  color: scheme.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: cardBorder),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Image.asset(
                                  FullposBrandTheme.logoAsset,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Center(
                                        child: Icon(
                                          Icons.lock_rounded,
                                          size: 38,
                                          color: scheme.primary,
                                        ),
                                      ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      FullposBrandTheme.appName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                            color: onSurface,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Acceso restringido',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(color: mutedText),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Minimizar',
                                onPressed: WindowService.minimize,
                                icon: const Icon(Icons.minimize),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: WindowService.close,
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Tu licencia FullPOS requiere renovación',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Compra más tiempo, verifica una activación ya pagada o carga un archivo de licencia válido para continuar.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: mutedText,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: scheme.surfaceVariant.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: cardBorder),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.info_outline, color: scheme.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Motivo',
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              color: onSurface,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        motivo.isNotEmpty
                                            ? motivo
                                            : 'No especificado por el administrador.',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: onSurface.withOpacity(
                                                0.90,
                                              ),
                                              height: 1.30,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () => context.go('/license/purchase'),
                            icon: const Icon(Icons.shopping_cart_checkout),
                            label: const Text('Comprar ahora'),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _verifyNow,
                                icon: const Icon(Icons.verified_outlined),
                                label: const Text(
                                  'Ya pagué, verificar licencia',
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _pickAndApplyLicenseFile,
                                icon: const Icon(Icons.upload_file_outlined),
                                label: const Text('Subir archivo de licencia'),
                              ),
                            ],
                          ),
                          if (_licenseFileStatus != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _licenseFileStatus!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: mutedText,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: scheme.surfaceVariant.withOpacity(0.28),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: cardBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Soporte',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: onSurface,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'WhatsApp: $_supportPhoneDisplay',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: mutedText,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                FilledButton.icon(
                                  onPressed: () => _openWhatsapp(
                                    context,
                                    message: whatsappMessage,
                                  ),
                                  icon: const Icon(Icons.chat_bubble_outline),
                                  label: const Text('Abrir WhatsApp'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
