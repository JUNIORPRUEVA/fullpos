import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/app_config.dart';

class ApiClientOptions {
  const ApiClientOptions({
    this.timeout = const Duration(seconds: 12),
    this.retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ],
  });

  final Duration timeout;

  /// Delays before each retry (total attempts = 1 + retryDelays.length).
  final List<Duration> retryDelays;
}

class ApiClient {
  ApiClient({
    String? baseUrl,
    http.Client? client,
    ApiClientOptions options = const ApiClientOptions(),
  }) : _baseUrl = baseUrl,
       _client = client ?? IOClient(HttpClient()),
       _options = options;

  final String? _baseUrl;
  final http.Client _client;
  final ApiClientOptions _options;

  String get baseUrl => AppConfig.normalizeBaseUrl(_baseUrl ?? AppConfig.apiBaseUrl);

  Uri uri(String path, {Map<String, String>? queryParameters}) {
    final base = Uri.parse(baseUrl);
    final normalized = path.startsWith('/') ? path : '/$path';

    final basePath = base.path.trim();
    final combinedPath = _joinPaths(basePath, normalized);

    final effectiveQuery =
      queryParameters ?? (base.hasQuery ? base.queryParameters : null);
    return base.replace(path: combinedPath, queryParameters: effectiveQuery);
  }

  Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Duration? timeout,
    bool retry = true,
  }) {
    return _request(
      method: 'GET',
      path: path,
      headers: headers,
      queryParameters: queryParameters,
      timeout: timeout,
      retry: retry,
      idempotent: true,
    );
  }

  /// Ejecuta un GET cancelable.
  ///
  /// Nota: la cancelación se implementa cerrando un client dedicado.
  CancelableApiCall<http.Response> getCancelable(
    String path, {
    Map<String, String>? headers,
    Duration? timeout,
    bool retry = true,
  }) {
    final httpClient = HttpClient();
    final client = IOClient(httpClient);
    void cancel() {
      try {
        client.close();
      } catch (_) {}
      try {
        httpClient.close(force: true);
      } catch (_) {}
    }

    final future = ApiClient(
      baseUrl: baseUrl,
      client: client,
      options: _options,
    ).get(
      path,
      headers: headers,
      timeout: timeout,
      retry: retry,
    );

    return CancelableApiCall._(future: future, cancel: cancel);
  }

  Future<http.Response> delete(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Duration? timeout,
    bool retry = true,
  }) {
    return _request(
      method: 'DELETE',
      path: path,
      headers: headers,
      queryParameters: queryParameters,
      timeout: timeout,
      retry: retry,
      idempotent: true,
    );
  }

  Future<http.Response> postJson(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Object? body,
    Duration? timeout,
    bool retry = false,
  }) {
    return _request(
      method: 'POST',
      path: path,
      headers: {
        'Content-Type': 'application/json',
        ...?headers,
      },
      queryParameters: queryParameters,
      body: jsonEncode(body ?? const {}),
      timeout: timeout,
      retry: retry,
      idempotent: false,
    );
  }

  Future<http.Response> putJson(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Object? body,
    Duration? timeout,
    bool retry = true,
  }) {
    return _request(
      method: 'PUT',
      path: path,
      headers: {
        'Content-Type': 'application/json',
        ...?headers,
      },
      queryParameters: queryParameters,
      body: jsonEncode(body ?? const {}),
      timeout: timeout,
      retry: retry,
      idempotent: true,
    );
  }

  Future<Map<String, dynamic>> getJsonMap(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Duration? timeout,
    bool retry = true,
  }) async {
    final res = await get(
      path,
      headers: headers,
      queryParameters: queryParameters,
      timeout: timeout,
      retry: retry,
    );
    return _decodeJsonMap(res);
  }

  Future<List<dynamic>> getJsonList(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Duration? timeout,
    bool retry = true,
  }) async {
    final res = await get(
      path,
      headers: headers,
      queryParameters: queryParameters,
      timeout: timeout,
      retry: retry,
    );
    final decoded = jsonDecode(res.body);
    if (decoded is List) return decoded;
    throw ApiException(
      message: 'Respuesta inválida del servidor.',
      statusCode: res.statusCode,
    );
  }

  /// Uploads a multipart request.
  ///
  /// Note: retries are disabled by default because multipart POST is non-idempotent.
  Future<http.StreamedResponse> sendMultipart(
    http.MultipartRequest request, {
    bool retry = false,
    Duration? timeout,
  }) async {
    // Ensure base headers.
    request.headers.putIfAbsent('User-Agent', () => AppConfig.userAgent);

    final effectiveTimeout = timeout ?? _options.timeout;
    if (!retry) {
      return request.send().timeout(effectiveTimeout);
    }

    // If caller explicitly enables retry, try to re-send by cloning.
    // Caller must ensure idempotency.
    http.MultipartRequest cloneRequest() {
      final cloned = http.MultipartRequest(request.method, request.url);
      cloned.headers.addAll(request.headers);
      cloned.fields.addAll(request.fields);
      cloned.files.addAll(request.files);
      return cloned;
    }

    ApiException? lastApiEx;
    Object? lastError;

    for (var attempt = 0; attempt <= _options.retryDelays.length; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_options.retryDelays[attempt - 1]);
      }

      try {
        final req = attempt == 0 ? request : cloneRequest();
        final streamed = await req.send().timeout(effectiveTimeout);
        if (streamed.statusCode >= 500 && streamed.statusCode <= 599) {
          lastApiEx = ApiException(
            message: 'Error del servidor.',
            statusCode: streamed.statusCode,
          );
          continue;
        }
        return streamed;
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on HandshakeException catch (e) {
        // SSL issues are not transient.
        throw ApiException(message: _sslMessage(e));
      } catch (e) {
        lastError = e;
      }
    }

    if (lastApiEx != null) throw lastApiEx;
    throw ApiException(message: _networkMessage(lastError));
  }

  Future<http.Response> _request({
    required String method,
    required String path,
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
    Object? body,
    Duration? timeout,
    required bool retry,
    required bool idempotent,
  }) async {
    final effectiveTimeout = timeout ?? _options.timeout;

    ApiException? lastApiEx;
    Object? lastError;

    final attempts = 1 + (retry ? _options.retryDelays.length : 0);

    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_options.retryDelays[attempt - 1]);
      }

      try {
        final req = http.Request(method, uri(path, queryParameters: queryParameters));

        req.headers.addAll({
          'Accept': 'application/json',
          'User-Agent': AppConfig.userAgent,
          ...?headers,
        });

        if (body != null) {
          if (body is String) {
            req.body = body;
          } else if (body is List<int>) {
            req.bodyBytes = body;
          } else {
            req.body = body.toString();
          }
        }

        final streamed = await _client.send(req).timeout(effectiveTimeout);
        final res = await http.Response.fromStream(streamed);

        if (res.statusCode >= 500 && res.statusCode <= 599) {
          lastApiEx = ApiException(
            message: 'Error del servidor (HTTP ${res.statusCode}).',
            statusCode: res.statusCode,
          );
          if (retry && idempotent) {
            continue;
          }
          throw lastApiEx;
        }

        return res;
      } on TimeoutException catch (e) {
        lastError = e;
        if (!(retry && idempotent)) break;
      } on SocketException catch (e) {
        lastError = e;
        if (!(retry && idempotent)) break;
      } on HandshakeException catch (e) {
        // SSL issues should be surfaced clearly.
        throw ApiException(message: _sslMessage(e));
      } on ApiException catch (e) {
        lastApiEx = e;
        break;
      } catch (e) {
        lastError = e;
        break;
      }
    }

    if (lastApiEx != null) throw lastApiEx;
    throw ApiException(message: _networkMessage(lastError));
  }

  Map<String, dynamic> _decodeJsonMap(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        message: 'Solicitud fallida (HTTP ${res.statusCode}).',
        statusCode: res.statusCode,
      );
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((k, v) => MapEntry(k.toString(), v));
    }
    throw ApiException(
      message: 'Respuesta inválida del servidor.',
      statusCode: res.statusCode,
    );
  }

  static String _joinPaths(String basePath, String newPath) {
    final b = basePath.trim();
    final n = newPath.trim();

    final left = b.isEmpty ? '' : (b.startsWith('/') ? b : '/$b');
    final right = n.startsWith('/') ? n : '/$n';

    if (left.isEmpty || left == '/') return right;
    if (right == '/') return left;

    return '${left.replaceAll(RegExp(r'/+$'), '')}/${right.replaceAll(RegExp(r'^/+'), '')}';
  }

  static String _sslMessage(Object? e) {
    return 'Error SSL/certificado. Verifica fecha/hora del equipo y el certificado del servidor.';
  }

  static String _networkMessage(Object? e) {
    if (e is TimeoutException) {
      return 'Tiempo de espera agotado. Verifica tu conexión a Internet o firewall.';
    }
    if (e is SocketException) {
      return 'No se pudo conectar al servidor. Verifica Internet/DNS/Proxy/Firewall.';
    }
    return 'Error de red. Verifica tu conexión.';
  }
}

class ApiException implements Exception {
  ApiException({required this.message, this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class CancelableApiCall<T> {
  CancelableApiCall._({required this.future, required void Function() cancel})
    : _cancel = cancel;

  final Future<T> future;
  final void Function() _cancel;

  void cancel() => _cancel();
}
