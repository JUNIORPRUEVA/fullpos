import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

class NetworkStatusState {
  const NetworkStatusState._({
    required this.isOnline,
    required this.isOffline,
    required this.lastCheckedAt,
    required this.lastError,
    required this.lastStatusCode,
  });

  factory NetworkStatusState.unknown() => const NetworkStatusState._(
    isOnline: false,
    isOffline: false,
    lastCheckedAt: null,
    lastError: null,
    lastStatusCode: null,
  );

  factory NetworkStatusState.online({DateTime? checkedAt, int? statusCode}) =>
      NetworkStatusState._(
        isOnline: true,
        isOffline: false,
        lastCheckedAt: checkedAt,
        lastError: null,
        lastStatusCode: statusCode,
      );

  factory NetworkStatusState.offline({
    DateTime? checkedAt,
    String? error,
    int? statusCode,
  }) => NetworkStatusState._(
    isOnline: false,
    isOffline: true,
    lastCheckedAt: checkedAt,
    lastError: error,
    lastStatusCode: statusCode,
  );

  final bool isOnline;
  final bool isOffline;
  final DateTime? lastCheckedAt;
  final String? lastError;
  final int? lastStatusCode;
}

final networkStatusProvider =
    StateNotifierProvider<NetworkStatusController, NetworkStatusState>((ref) {
      return NetworkStatusController();
    });

class NetworkStatusController extends StateNotifier<NetworkStatusState> {
  NetworkStatusController({
    Duration onlineInterval = const Duration(seconds: 120),
    Duration offlineInterval = const Duration(seconds: 30),
  }) : _onlineInterval = onlineInterval,
       _offlineInterval = offlineInterval,
       super(NetworkStatusState.unknown()) {
    _scheduleNext(const Duration(milliseconds: 10));
  }

  static const String _healthPath = '/api/health';

  final Duration _onlineInterval;
  final Duration _offlineInterval;
  Timer? _timer;
  bool _inFlight = false;
  bool _recheckRequested = false;
  bool _disposed = false;

  Duration _intervalForState(NetworkStatusState s) {
    if (s.isOffline) return _offlineInterval;
    if (s.isOnline) return _onlineInterval;
    // Unknown: check more aggressively until we know.
    return _offlineInterval;
  }

  void _scheduleNext(Duration delay) {
    _timer?.cancel();
    if (_disposed) return;
    _timer = Timer(delay, () {
      unawaited(checkNow());
    });
  }

  Future<void> checkNow() async {
    if (_disposed) return;
    if (_inFlight) {
      _recheckRequested = true;
      return;
    }
    _inFlight = true;

    final now = DateTime.now();
    final api = ApiClient();

    try {
      final res = await api.get(
        _healthPath,
        timeout: const Duration(seconds: 4),
        retry: false,
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        state = NetworkStatusState.online(
          checkedAt: now,
          statusCode: res.statusCode,
        );
      } else {
        state = NetworkStatusState.offline(
          checkedAt: now,
          statusCode: res.statusCode,
          error: 'Health check falló (HTTP ${res.statusCode}).',
        );
      }
    } catch (e) {
      state = NetworkStatusState.offline(checkedAt: now, error: e.toString());
    } finally {
      _inFlight = false;

      if (_disposed) return;

      if (_recheckRequested) {
        _recheckRequested = false;
        _scheduleNext(Duration.zero);
        return;
      }

      _scheduleNext(_intervalForState(state));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
