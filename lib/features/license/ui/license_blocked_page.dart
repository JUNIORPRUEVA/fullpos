import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/brand/fullpos_brand_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/window/window_service.dart';
import '../../registration/services/business_identity_storage.dart';
import '../license_config.dart';
import '../services/business_license_sync.dart';
import '../services/license_storage.dart';
import '../services/license_gate_refresh.dart';

class LicenseBlockedPage extends StatefulWidget {
  const LicenseBlockedPage({super.key});

  @override
  State<LicenseBlockedPage> createState() => _LicenseBlockedPageState();
}

class _LicenseBlockedPageState extends State<LicenseBlockedPage> {
  StreamSubscription<String>? _sseSub;
  HttpClient? _httpClient;
  bool _disposed = false;

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
    final businessId = (await BusinessIdentityStorage().getBusinessId())?.trim();
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

    if (response == null || response.statusCode < 200 || response.statusCode >= 300) {
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
                            'Su cuenta ha sido detenida temporalmente',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Por el momento no es posible utilizar el sistema.\n'
                            'Si cree que se trata de un error, contacte con soporte.',
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
