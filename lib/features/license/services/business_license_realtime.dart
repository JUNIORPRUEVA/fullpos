import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/network/api_client.dart';

enum BusinessLicenseRealtimeSignal { ready, licenseChanged, disconnected }

class BusinessLicenseRealtime {
  Stream<BusinessLicenseRealtimeSignal> watch({
    required String baseUrl,
    required String businessId,
  }) {
    final id = businessId.trim();
    if (id.isEmpty) return const Stream<BusinessLicenseRealtimeSignal>.empty();

    final controller =
        StreamController<BusinessLicenseRealtimeSignal>.broadcast();
    HttpClient? httpClient;
    bool cancelled = false;

    Future<void> closeClient() async {
      final c = httpClient;
      httpClient = null;
      if (c == null) return;
      try {
        c.close(force: true);
      } catch (_) {}
    }

    Future<void> run() async {
      var backoffSeconds = 1;
      while (!cancelled) {
        try {
          final api = ApiClient(baseUrl: baseUrl);
          final uri = api.uri('/businesses/$id/license/stream');

          httpClient = HttpClient()..idleTimeout = const Duration(seconds: 70);

          final req = await httpClient!.getUrl(uri);
          req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
          req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

          final res = await req.close();
          if (res.statusCode != 200) {
            await res.drain();
            throw Exception('SSE HTTP ${res.statusCode}');
          }

          // Reset backoff after successful connection.
          backoffSeconds = 1;

          String? event;
          final data = StringBuffer();

          void dispatch() {
            final e = (event ?? '').trim();
            // We don't currently need to parse data payload.
            if (e == 'ready') {
              controller.add(BusinessLicenseRealtimeSignal.ready);
            } else if (e == 'license_changed') {
              controller.add(BusinessLicenseRealtimeSignal.licenseChanged);
            }
            event = null;
            data.clear();
          }

          await for (final line
              in res.transform(utf8.decoder).transform(const LineSplitter())) {
            if (cancelled) break;

            final trimmed = line.trimRight();
            if (trimmed.isEmpty) {
              // End of SSE event block.
              if ((event ?? '').isNotEmpty || data.isNotEmpty) {
                dispatch();
              }
              continue;
            }

            if (trimmed.startsWith('event:')) {
              event = trimmed.substring('event:'.length).trim();
              continue;
            }

            if (trimmed.startsWith('data:')) {
              data.writeln(trimmed.substring('data:'.length).trim());
              continue;
            }
          }
        } catch (_) {
          // Silencioso: reconectar.
        } finally {
          await closeClient();
        }

        if (!cancelled) {
          // Let listeners know realtime channel is down; polling will cover.
          controller.add(BusinessLicenseRealtimeSignal.disconnected);
        }

        if (cancelled) break;

        // Exponential backoff with jitter.
        final jitterMs = (DateTime.now().microsecondsSinceEpoch % 250);
        await Future<void>.delayed(
          Duration(seconds: backoffSeconds) + Duration(milliseconds: jitterMs),
        );
        backoffSeconds = (backoffSeconds * 2).clamp(1, 15);
      }

      await closeClient();
      await controller.close();
    }

    controller.onListen = () {
      unawaited(run());
    };
    controller.onCancel = () {
      cancelled = true;
      unawaited(closeClient());
    };

    return controller.stream;
  }
}
