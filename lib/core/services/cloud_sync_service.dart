import 'dart:async';
import 'dart:convert';

import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_db.dart';
import '../db/tables.dart';
import '../network/api_client.dart';
import '../sync/sync_outbox_repository.dart';
import '../sync/product_sync_outbox_repository.dart';
import '../../features/settings/data/business_settings_model.dart';
import '../../features/settings/data/business_settings_repository.dart';
import '../../features/products/data/products_repository.dart';
import '../../features/products/models/product_model.dart';
import '../../features/facturacion_electronica/data/factura_electronica_repository.dart';
import '../../features/facturacion_electronica/data/models/factura_electronica_model.dart';
import '../../features/sales/data/sales_repository.dart';
import '../../features/sales/data/sales_model.dart';
import '../config/backend_config.dart';
import '../config/app_config.dart';
import '../logging/app_logger.dart';
import '../session/session_manager.dart';
import 'cloud_company_identity_service.dart';
import '../storage/prefs_safe.dart';
import '../theme/app_themes.dart';

enum CloudSyncTarget {
  users('users'),
  companyConfig('company_config'),
  clients('clients'),
  categories('categories'),
  suppliers('suppliers'),
  products('products'),
  sales('sales'),
  payments('payments'),
  returns('returns'),
  cash('cash'),
  quotes('quotes');

  const CloudSyncTarget(this.value);
  final String value;

  static CloudSyncTarget? tryParse(String value) {
    for (final target in CloudSyncTarget.values) {
      if (target.value == value) return target;
    }
    return null;
  }
}

class CloudSyncService {
  CloudSyncService._();

  static final CloudSyncService instance = CloudSyncService._();

  final SyncOutboxRepository _outbox = SyncOutboxRepository();
  Timer? _outboxDispatchDebounce;
  Timer? _outboxPollingTimer;
  bool _outboxRunning = false;
  bool _engineStarted = false;
  final Set<CloudSyncTarget> _criticalSyncTargetsInFlight = <CloudSyncTarget>{};
  final Map<String, ({bool ok, int checkedAtMs})> _imageHealthCache = {};

  /// Mensaje del último error de sincronización por target.
  /// Se usa para almacenar el detalle real en el outbox en lugar del genérico 'sync_failed'.
  String? _lastSyncFailureMessage;

  void _recordSyncFailure(String message) {
    _lastSyncFailureMessage = message;
  }

  bool _isCompanyLocatorConflict(int statusCode, String body) {
    if (statusCode != 404 && statusCode != 409) return false;
    final normalized = body.toUpperCase();
    return normalized.contains('COMPANY_TENANT_LOCATOR_CONFLICT') ||
        normalized.contains('COMPANY_TENANT_IDENTITY_CONFLICT') ||
        normalized.contains('COMPANY_TENANT_NOT_LINKED') ||
        normalized.contains('COMPANY_RNC_AMBIGUOUS');
  }

  Future<http.Response> _postByRncWithIdentityFallback({
    required String baseUrl,
    required String endpoint,
    required Map<String, String> headers,
    required Map<String, dynamic> payload,
    required Duration timeout,
    required String reason,
  }) async {
    final api = ApiClient(baseUrl: baseUrl);
    final response = await api.postJson(
      endpoint,
      headers: headers,
      body: payload,
      timeout: timeout,
    );

    final hasRnc =
        (payload['companyRnc']?.toString().trim().isNotEmpty ?? false);
    final hasCloudId =
        (payload['companyCloudId']?.toString().trim().isNotEmpty ?? false);
    if (!hasRnc || !hasCloudId) {
      return response;
    }

    final body = response.body;
    if (!_isCompanyLocatorConflict(response.statusCode, body)) {
      return response;
    }

    final retryPayload = Map<String, dynamic>.from(payload)
      ..remove('companyCloudId')
      ..remove('companyTenantKey');

    await AppLogger.instance.logWarn(
      'Cloud sync locator conflict, retrying without companyCloudId reason=$reason endpoint=$endpoint status=${response.statusCode} body=$body',
      module: 'cloud_sync',
    );

    return api.postJson(
      endpoint,
      headers: headers,
      body: retryPayload,
      timeout: timeout,
    );
  }

  /// Devuelve la URL efectiva usada para nube (considera `cloudEndpoint` si existe).
  ///
  /// Útil para diagnóstico en UI.
  String debugResolveCloudBaseUrl(BusinessSettings settings) {
    return _resolveBaseUrl(settings);
  }

  Future<Map<String, dynamic>> _companyIdentityPayload(
    BusinessSettings settings,
  ) async {
    final identity = await CloudCompanyIdentityService.resolve(settings);
    return identity.toPayload();
  }

  static const int _historyDaysToSync = 90;
  static const int _chunkSize = 50;

  static const Set<CloudSyncTarget> _enabledTargets = {
    CloudSyncTarget.users,
    CloudSyncTarget.companyConfig,
    CloudSyncTarget.clients,
    CloudSyncTarget.categories,
    CloudSyncTarget.products,
    CloudSyncTarget.sales,
  };

  static const Set<String> visibleTargetKeys = {
    'users',
    'company_config',
    'clients',
    'categories',
    'products',
    'sales',
  };

  void startRealtimeSyncEngine() {
    if (_engineStarted) return;
    _engineStarted = true;
    unawaited(_outbox.retainTargets(visibleTargetKeys));

    _outboxPollingTimer?.cancel();
    _outboxPollingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_drainOutbox());
    });

    const startupTargets = <(CloudSyncTarget, int, String)>[
      (
        CloudSyncTarget.companyConfig,
        120,
        'engine_start_initial_company_config',
      ),
      (CloudSyncTarget.users, 180, 'engine_start_initial_users'),
      (CloudSyncTarget.clients, 240, 'engine_start_initial_clients'),
      (CloudSyncTarget.categories, 300, 'engine_start_initial_categories'),
      (CloudSyncTarget.products, 360, 'engine_start_initial_products'),
      (CloudSyncTarget.sales, 460, 'engine_start_initial_sales'),
    ];
    for (final (target, delayMs, reason) in startupTargets) {
      unawaited(
        _enqueueTarget(
          target,
          delay: Duration(milliseconds: delayMs),
          reason: reason,
        ),
      );
    }
    unawaited(_drainOutbox());
  }

  void stopRealtimeSyncEngine() {
    _engineStarted = false;
    _outboxPollingTimer?.cancel();
    _outboxPollingTimer = null;
    _outboxDispatchDebounce?.cancel();
    _outboxDispatchDebounce = null;
  }

  Future<bool> _hasActiveSyncSession() async {
    if (!await SessionManager.isLoggedIn()) {
      return false;
    }
    return await SessionManager.companyId() != null;
  }

  void scheduleUsersSyncSoon({
    Duration delay = const Duration(milliseconds: 600),
    String reason = 'users_changed',
  }) {
    unawaited(
      _enqueueTarget(CloudSyncTarget.users, delay: delay, reason: reason),
    );
  }

  void scheduleCompanyConfigSyncSoon({
    Duration delay = const Duration(milliseconds: 600),
    String reason = 'company_config_changed',
  }) {
    unawaited(
      _enqueueTarget(
        CloudSyncTarget.companyConfig,
        delay: delay,
        reason: reason,
      ),
    );
  }

  void scheduleClientsSyncSoon({
    Duration delay = const Duration(milliseconds: 600),
    String reason = 'clients_changed',
  }) {
    unawaited(
      _enqueueTarget(CloudSyncTarget.clients, delay: delay, reason: reason),
    );
  }

  void scheduleCategoriesSyncSoon({
    Duration delay = const Duration(milliseconds: 600),
    String reason = 'categories_changed',
  }) {
    unawaited(
      _enqueueTarget(CloudSyncTarget.categories, delay: delay, reason: reason),
    );
  }

  void scheduleSuppliersSyncSoon({
    Duration delay = const Duration(milliseconds: 600),
    String reason = 'suppliers_changed',
  }) {
    unawaited(
      _enqueueTarget(CloudSyncTarget.suppliers, delay: delay, reason: reason),
    );
  }

  void scheduleProductsSyncSoon({
    Duration delay = const Duration(milliseconds: 150),
    String reason = 'products_changed',
  }) {
    unawaited(
      _enqueueTarget(CloudSyncTarget.products, delay: delay, reason: reason),
    );
  }

  void scheduleSalesSyncSoon({
    Duration delay = const Duration(milliseconds: 150),
    String reason = 'sales_changed',
  }) {
    unawaited(
      _enqueueTarget(CloudSyncTarget.sales, delay: delay, reason: reason),
    );
  }

  void schedulePaymentsSyncSoon({
    Duration delay = const Duration(milliseconds: 350),
    String reason = 'payments_changed',
  }) {
    unawaited(
      _enqueueTarget(CloudSyncTarget.payments, delay: delay, reason: reason),
    );
  }

  void scheduleReturnsSyncSoon({
    Duration delay = const Duration(milliseconds: 150),
    String reason = 'returns_changed',
  }) {
    unawaited(
      _enqueueTarget(CloudSyncTarget.returns, delay: delay, reason: reason),
    );
  }

  void scheduleCashSyncSoon({
    Duration delay = const Duration(milliseconds: 600),
    String reason = 'cash_changed',
  }) {
    unawaited(
      _enqueueTarget(CloudSyncTarget.cash, delay: delay, reason: reason),
    );
  }

  void scheduleQuotesSyncSoon({
    Duration delay = const Duration(milliseconds: 600),
    String reason = 'quotes_changed',
  }) {
    unawaited(
      _enqueueTarget(CloudSyncTarget.quotes, delay: delay, reason: reason),
    );
  }

  Future<void> syncSalesNow({String reason = 'sales_changed'}) {
    return _runCriticalTargetNow(
      CloudSyncTarget.sales,
      reason: reason,
      fallbackDelay: const Duration(milliseconds: 150),
    );
  }

  Future<void> syncReturnsNow({String reason = 'returns_changed'}) {
    return _runCriticalTargetNow(
      CloudSyncTarget.returns,
      reason: reason,
      fallbackDelay: const Duration(milliseconds: 150),
    );
  }

  Future<void> retryAllFailedSyncNow() async {
    await _outbox.retryAllFailedNow();
    _kickOutboxDispatcher();
  }

  Future<bool> syncRequiredTargetsNow({
    String reason = 'required_full_sync',
  }) async {
    if (!await _hasActiveSyncSession()) return false;
    final settings = await BusinessSettingsRepository().loadSettings();
    if (!settings.cloudEnabled) return false;

    await _outbox.retainTargets(visibleTargetKeys);
    for (final target in _enabledTargets) {
      await _outbox.enqueue(
        target: target.value,
        reason: reason,
        delay: Duration.zero,
      );
    }
    await _drainOutbox();

    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      final rows = await readSyncStatusRows();
      final statuses = <String, String>{
        for (final row in rows)
          if (row['target'] is String)
            row['target'] as String:
                (row['status'] as String?)?.toLowerCase() ?? 'unknown',
      };
      if (visibleTargetKeys.every((target) => statuses[target] == 'synced')) {
        return true;
      }
      if (visibleTargetKeys.any(
        (target) => const {
          'failed',
          'error',
          'rejected',
          'conflict',
        }.contains(statuses[target]),
      )) {
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _drainOutbox();
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> readSyncStatusRows() {
    return _outbox.listStatusRows().then(
      (rows) => rows
          .where((row) {
            final target = (row['target'] as String?)?.trim() ?? '';
            return visibleTargetKeys.contains(target);
          })
          .toList(growable: false),
    );
  }

  Future<void> _runCriticalTargetNow(
    CloudSyncTarget target, {
    required String reason,
    required Duration fallbackDelay,
  }) async {
    if (!_enabledTargets.contains(target)) return;
    if (_criticalSyncTargetsInFlight.contains(target)) return;

    _criticalSyncTargetsInFlight.add(target);
    try {
      if (!await _hasActiveSyncSession()) {
        await AppLogger.instance.logInfo(
          'Critical sync skipped target=${target.value} reason=$reason session=inactive',
          module: 'cloud_sync',
        );
        return;
      }

      await AppLogger.instance.logInfo(
        'Critical sync start target=${target.value} reason=$reason',
        module: 'cloud_sync',
      );

      final success = await _runTargetSync(target);
      if (success) {
        await AppLogger.instance.logInfo(
          'Critical sync success target=${target.value} reason=$reason',
          module: 'cloud_sync',
        );
        return;
      }

      await AppLogger.instance.logWarn(
        'Critical sync failed target=${target.value} reason=$reason fallbackQueued=true',
        module: 'cloud_sync',
      );
      await _enqueueTarget(target, delay: fallbackDelay, reason: reason);
    } finally {
      _criticalSyncTargetsInFlight.remove(target);
    }
  }

  Future<void> _enqueueTarget(
    CloudSyncTarget target, {
    required Duration delay,
    required String reason,
  }) async {
    if (!_enabledTargets.contains(target)) {
      await AppLogger.instance.logInfo(
        'Sync target skipped target=${target.value} reason=$reason',
        module: 'cloud_sync',
      );
      return;
    }

    final settings = await BusinessSettingsRepository().loadSettings();
    if (!settings.cloudEnabled) {
      await AppLogger.instance.logInfo(
        'Sync target skipped target=${target.value} reason=$reason cloud=disabled',
        module: 'cloud_sync',
      );
      return;
    }

    if (!await _hasActiveSyncSession()) {
      await AppLogger.instance.logInfo(
        'Sync target skipped target=${target.value} reason=$reason session=inactive',
        module: 'cloud_sync',
      );
      return;
    }

    await _outbox.enqueue(target: target.value, reason: reason, delay: delay);
    await AppLogger.instance.logInfo(
      'Sync job queued target=${target.value} reason=$reason delayMs=${delay.inMilliseconds}',
      module: 'cloud_sync',
    );
    _kickOutboxDispatcher();
  }

  void _kickOutboxDispatcher() {
    _outboxDispatchDebounce?.cancel();
    _outboxDispatchDebounce = Timer(const Duration(milliseconds: 75), () {
      _outboxDispatchDebounce = null;
      unawaited(_drainOutbox());
    });
  }

  Future<void> _drainOutbox() async {
    if (_outboxRunning) return;
    final settings = await BusinessSettingsRepository().loadSettings();
    if (!settings.cloudEnabled) return;
    if (!await _hasActiveSyncSession()) {
      await AppLogger.instance.logInfo(
        'Cloud sync outbox skipped: no authenticated session or companyId',
        module: 'cloud_sync',
      );
      return;
    }
    _outboxRunning = true;
    try {
      while (true) {
        final dueTargets = await _outbox.listDueTargets(limit: 8);
        if (dueTargets.isEmpty) break;

        for (final rawTarget in dueTargets) {
          final target = CloudSyncTarget.tryParse(rawTarget);
          if (target == null) continue;

          await _outbox.markSyncing(target.value);
          _lastSyncFailureMessage = null;
          final startedAt = DateTime.now().millisecondsSinceEpoch;
          await AppLogger.instance.logInfo(
            'Sync started target=${target.value}',
            module: 'cloud_sync',
          );

          final success = await _runTargetSync(target);
          final duration = DateTime.now().millisecondsSinceEpoch - startedAt;

          if (success) {
            final marked = await _outbox.markSuccess(
              target.value,
              durationMs: duration,
            );
            if (!marked) {
              await AppLogger.instance.logInfo(
                'Sync success target=${target.value} durationMs=$duration pending_queued_during_sync=true',
                module: 'cloud_sync',
              );
              _kickOutboxDispatcher();
              continue;
            }
            await AppLogger.instance.logInfo(
              'Sync success target=${target.value} durationMs=$duration',
              module: 'cloud_sync',
            );
            continue;
          }

          final attempts = (await _outbox.getAttemptCount(target.value)) + 1;
          final retryDelay = _retryDelayForAttempt(attempts);
          final markedFailure = await _outbox.markFailure(
            target.value,
            error: _lastSyncFailureMessage ?? 'sync_failed',
            attemptCount: attempts,
            retryDelay: retryDelay,
          );
          if (!markedFailure) {
            await AppLogger.instance.logInfo(
              'Sync failed target=${target.value} attempts=$attempts failure_deferred_because_pending=true',
              module: 'cloud_sync',
            );
            _kickOutboxDispatcher();
            continue;
          }
          await AppLogger.instance.logWarn(
            'Sync failed target=${target.value} attempts=$attempts retryInMs=${retryDelay.inMilliseconds}',
            // error detail already logged inside each syncX function
            module: 'cloud_sync',
          );
        }
      }
    } finally {
      _outboxRunning = false;
    }
  }

  Duration _retryDelayForAttempt(int attempts) {
    final safe = attempts < 1 ? 1 : attempts;
    final seconds = min(300, 1 << min(8, safe));
    return Duration(seconds: seconds);
  }

  Future<bool> _runTargetSync(CloudSyncTarget target) {
    if (!_enabledTargets.contains(target)) {
      return Future.value(true);
    }

    return _runTargetSyncGuarded(target);
  }

  Future<bool> _runTargetSyncGuarded(CloudSyncTarget target) async {
    if (!await _hasActiveSyncSession()) {
      await AppLogger.instance.logInfo(
        'Sync execution skipped target=${target.value} session=inactive',
        module: 'cloud_sync',
      );
      return true;
    }

    switch (target) {
      case CloudSyncTarget.users:
        return syncUsersIfEnabled(force: true);
      case CloudSyncTarget.companyConfig:
        return syncCompanyConfigIfEnabled();
      case CloudSyncTarget.clients:
        return syncClientsIfEnabled();
      case CloudSyncTarget.categories:
        return syncCategoriesIfEnabled();
      case CloudSyncTarget.suppliers:
        return syncSuppliersIfEnabled();
      case CloudSyncTarget.products:
        return syncProductsIfEnabled();
      case CloudSyncTarget.sales:
        return syncSalesIfEnabled();
      case CloudSyncTarget.payments:
        return syncPaymentsIfEnabled();
      case CloudSyncTarget.returns:
        return syncReturnsIfEnabled();
      case CloudSyncTarget.cash:
        return syncCashIfEnabled();
      case CloudSyncTarget.quotes:
        return syncQuotesIfEnabled();
    }
  }

  static const String _prefsKeyUsersLastSyncPrefix =
      'cloud_users_last_sync_at_ms_';

  String _syncKeyForCompany({
    required String rnc,
    required String? cloudCompanyId,
  }) {
    final raw = (cloudCompanyId != null && cloudCompanyId.trim().isNotEmpty)
        ? cloudCompanyId.trim()
        : rnc.trim();
    final safe = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return '$_prefsKeyUsersLastSyncPrefix$safe';
  }

  Future<Set<String>> _getTableColumns(
    DatabaseExecutor db,
    String table,
  ) async {
    try {
      final rows = await db.rawQuery('PRAGMA table_info($table)');
      return rows
          .map((r) => r['name'])
          .whereType<String>()
          .map((s) => s.toLowerCase())
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<int?> _resolveLocalCompanyId({
    required DatabaseExecutor db,
    required String rnc,
  }) async {
    final normalized = rnc.trim();
    if (normalized.isEmpty) return null;

    try {
      final cols = await _getTableColumns(db, DbTables.companies);
      if (!cols.contains('rnc')) return null;

      final rows = await db.query(
        DbTables.companies,
        columns: ['id'],
        where:
            'rnc = ?'
            '${cols.contains('deleted_at_ms') ? ' AND deleted_at_ms IS NULL' : ''}',
        whereArgs: [normalized],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return rows.first['id'] as int?;
    } catch (_) {
      return null;
    }
  }

  Future<bool> syncUsersIfEnabled({bool force = false}) async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) return true;

      final rnc = settings.rnc?.trim() ?? '';
      final cloudCompanyId = await _ensureCloudCompanyId(settings);
      if (rnc.isEmpty && (cloudCompanyId == null || cloudCompanyId.isEmpty)) {
        return false;
      }

      final prefs = await PrefsSafe.getInstance();
      if (prefs == null) return false;
      final key = _syncKeyForCompany(rnc: rnc, cloudCompanyId: cloudCompanyId);
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = prefs.getInt(key);
      if (!force &&
          last != null &&
          (now - last) < const Duration(minutes: 1).inMilliseconds) {
        return true;
      }

      final baseUrl = _resolveBaseUrl(settings);
      final headers = <String, String>{'Content-Type': 'application/json'};
      final cloudKey = settings.cloudApiKey?.trim();
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }

      final db = await AppDb.database;
      final userCols = await _getTableColumns(db, DbTables.users);

      final companyId = await _resolveLocalCompanyId(db: db, rnc: rnc);

      final whereParts = <String>[];
      final whereArgs = <Object?>[];
      if (companyId != null && userCols.contains('company_id')) {
        whereParts.add('company_id = ?');
        whereArgs.add(companyId);
      }
      if (userCols.contains('deleted_at_ms')) {
        whereParts.add('deleted_at_ms IS NULL');
      }

      final select = <String>['username'];
      if (userCols.contains('cloud_username')) select.add('cloud_username');
      if (userCols.contains('email')) select.add('email');
      if (userCols.contains('role')) select.add('role');
      if (userCols.contains('is_active')) select.add('is_active');
      if (userCols.contains('display_name')) select.add('display_name');
      if (!userCols.contains('display_name') && userCols.contains('name')) {
        select.add('name');
      }

      final rows = await db.query(
        DbTables.users,
        columns: select,
        where: whereParts.isNotEmpty ? whereParts.join(' AND ') : null,
        whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      );

      final users = <Map<String, dynamic>>[];
      for (final r in rows) {
        final localUsername = (r['username']?.toString() ?? '').trim();
        if (localUsername.isEmpty) continue;

        final isActive = userCols.contains('is_active')
            ? ((r['is_active'] as int?) ?? 1) == 1
            : true;
        if (!isActive) continue;

        final role = (r['role']?.toString() ?? 'cashier').trim();
        final cloudUsername = (r['cloud_username']?.toString() ?? '').trim();
        final username =
            (role.toLowerCase() == 'admin' && cloudUsername.isNotEmpty)
            ? cloudUsername
            : localUsername;
        final email = (r['email']?.toString() ?? '').trim();
        final displayName =
            (r['display_name']?.toString() ?? r['name']?.toString() ?? '')
                .trim();

        users.add({
          'username': username,
          if (email.isNotEmpty) 'email': email,
          if (displayName.isNotEmpty) 'displayName': displayName,
          if (role.isNotEmpty) 'role': role,
          'isActive': true,
        });
      }

      if (users.isEmpty) {
        await prefs.setInt(key, now);
        return true;
      }

      await AppLogger.instance.logInfo(
        'Cloud users sync start count=${users.length} baseUrl=$baseUrl',
        module: 'cloud_sync',
      );

      final payload = {
        ...await _companyIdentityPayload(settings),
        if (rnc.isNotEmpty) 'companyRnc': rnc,
        if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
          'companyCloudId': cloudCompanyId,
        'companyName': settings.businessName,
        'users': users,
      };

      final api = ApiClient(baseUrl: baseUrl);
      final response = await api.postJson(
        '/api/auth/sync-users',
        headers: headers,
        body: payload,
        timeout: const Duration(seconds: 10),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String body = '';
        try {
          body = response.body;
          if (body.length > 800) body = body.substring(0, 800);
        } catch (_) {}
        await AppLogger.instance.logWarn(
          'Cloud users sync failed status=${response.statusCode} body=$body',
          module: 'cloud_sync',
        );
        return false;
      }

      await prefs.setInt(key, now);
      await AppLogger.instance.logInfo(
        'Cloud users sync ok count=${users.length}',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
      _recordSyncFailure(e.toString());
      await AppLogger.instance.logWarn(
        'Cloud users sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<bool> checkCloudUsernameAvailable({
    required String cloudUsername,
  }) async {
    final result = await checkCloudUsernameAvailableDetailed(
      cloudUsername: cloudUsername,
    );
    return result.available;
  }

  Future<({bool available, String? error})>
  checkCloudUsernameAvailableDetailed({required String cloudUsername}) async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) {
        return (available: true, error: null);
      }

      final normalized = cloudUsername.trim().toLowerCase();
      if (normalized.length < 3) {
        return (
          available: false,
          error: 'Usuario de la nube requerido (mínimo 3 caracteres)',
        );
      }

      final rnc = settings.rnc?.trim() ?? '';
      final cloudCompanyId = await _ensureCloudCompanyId(settings);
      if (rnc.isEmpty && (cloudCompanyId == null || cloudCompanyId.isEmpty)) {
        return (
          available: false,
          error: 'Configura el RNC de la empresa para validar en la nube.',
        );
      }

      final baseUrl = _resolveBaseUrl(settings).trim();
      if (baseUrl.isEmpty) {
        return (
          available: false,
          error: 'Configura la URL de nube en Ajustes.',
        );
      }

      // La API key puede ser opcional si el backend permite nube pública.
      // Solo se requiere si el servidor responde 401/403.
      final cloudKey = settings.cloudApiKey?.trim();
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }

      final payload = {
        ...await _companyIdentityPayload(settings),
        if (rnc.isNotEmpty) 'companyRnc': rnc,
        if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
          'companyCloudId': cloudCompanyId,
        'username': normalized,
      };

      final api = ApiClient(baseUrl: baseUrl);
      final response = await api.postJson(
        '/api/auth/username-available',
        headers: headers,
        body: payload,
        timeout: const Duration(seconds: 6),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final isAvailable = decoded['available'] == true;
          return (
            available: isAvailable,
            error: isAvailable ? null : 'Ese usuario ya existe en la nube.',
          );
        }

        await AppLogger.instance.logWarn(
          'Cloud username-available invalid JSON baseUrl=$baseUrl',
          module: 'cloud_sync',
        );
        return (
          available: false,
          error: 'Respuesta inválida del servidor de nube.',
        );
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        return (
          available: false,
          error:
              'API Key requerida o inválida. Verifica la API Key en Ajustes > Nube.',
        );
      }

      if (response.statusCode == 404) {
        String hint = baseUrl;
        try {
          final uri = Uri.parse(baseUrl);
          final port = uri.hasPort ? ':${uri.port}' : '';
          hint = '${uri.scheme}://${uri.host}$port';
        } catch (_) {}
        return (
          available: false,
          error: 'Nube: endpoint no encontrado (404). URL: $hint',
        );
      }

      await AppLogger.instance.logWarn(
        'Cloud username-available failed status=${response.statusCode} baseUrl=$baseUrl',
        module: 'cloud_sync',
      );
      return (
        available: false,
        error: 'No se pudo validar en la nube (HTTP ${response.statusCode}).',
      );
    } on SocketException {
      return (
        available: false,
        error: 'No se pudo conectar a la nube. Verifica la URL de nube.',
      );
    } on HttpException {
      return (
        available: false,
        error: 'No se pudo conectar a la nube. Verifica la URL de nube.',
      );
    } catch (e) {
      await AppLogger.instance.logWarn(
        'Cloud username-available exception: ${e.toString()}',
        module: 'cloud_sync',
      );
      return (
        available: false,
        error: 'No se pudo validar en la nube. Revisa URL y API Key.',
      );
    }
  }

  Future<bool> syncCompanyConfigIfEnabled() async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) return true;
      final rnc = settings.rnc?.trim() ?? '';
      final cloudCompanyId = await _ensureCloudCompanyId(settings);
      if (rnc.isEmpty && (cloudCompanyId == null || cloudCompanyId.isEmpty)) {
        return false;
      }

      final baseUrl = _resolveBaseUrl(settings);
      final api = ApiClient(baseUrl: baseUrl);
      final headers = <String, String>{};
      final cloudKey = settings.cloudApiKey?.trim();
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }

      final payload = await _buildPayload(settings, rnc, cloudCompanyId);
      final response = await api.putJson(
        '/api/companies/config/by-rnc',
        headers: headers,
        body: payload,
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String body = '';
        try {
          body = response.body;
          if (body.length > 900) body = body.substring(0, 900);
        } catch (_) {}
        await AppLogger.instance.logWarn(
          'Cloud company config sync failed status=${response.statusCode} baseUrl=$baseUrl body=$body',
          module: 'cloud_sync',
        );
        _recordSyncFailure('HTTP ${response.statusCode}: $body');
        return false;
      }

      await AppLogger.instance.logInfo('Cloud sync ok', module: 'cloud_sync');
      return true;
    } catch (e) {
      _recordSyncFailure(e.toString());
      await AppLogger.instance.logWarn(
        'Cloud sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<bool> syncProductsIfEnabled() async {
    final snapshotStartedAtMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) return true;
      final rnc = settings.rnc?.trim() ?? '';
      final cloudCompanyId = await _ensureCloudCompanyId(settings);
      if (rnc.isEmpty && (cloudCompanyId == null || cloudCompanyId.isEmpty)) {
        return false;
      }

      final baseUrl = _resolveBaseUrl(settings);
      final headers = <String, String>{'Content-Type': 'application/json'};
      final cloudKey = settings.cloudApiKey?.trim();
      final companyIdentity = await CloudCompanyIdentityService.resolve(
        settings,
      );
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }

      final db = await AppDb.database;
      final categoryRows = await db.query(
        DbTables.categories,
        columns: ['id', 'name'],
      );
      final categoryNamesById = <int, String>{
        for (final row in categoryRows)
          if (row['id'] is int &&
              ((row['name'] as String?) ?? '').trim().isNotEmpty)
            row['id'] as int: (row['name'] as String).trim(),
      };

      final repo = ProductsRepository();
      final allProducts = await repo.getAll(includeDeleted: true);
      final deletedCodes = <String>{};
      final activeProducts = <ProductModel>[];
      for (final product in allProducts) {
        final code = product.code.trim();
        if (code.isEmpty) continue;
        if (product.isDeleted) {
          deletedCodes.add(code);
          continue;
        }
        if (!product.isActive) continue;
        activeProducts.add(product);
      }

      final payloadProducts = <Map<String, dynamic>>[];
      var processed = 0;
      for (final p in activeProducts) {
        processed++;
        if (processed % 25 == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        String? imageUrl = _normalizeUrl(p.imageUrl);

        String? localImageFilePath;
        if (p.hasImagePath) {
          localImageFilePath = p.imagePath;
        } else {
          final candidate = p.imageUrl?.trim();
          if (candidate != null &&
              candidate.isNotEmpty &&
              !candidate.startsWith('http')) {
            try {
              final exists = await File(candidate).exists();
              if (exists) localImageFilePath = candidate;
            } catch (_) {}
          }
        }

        if (p.prefersImage &&
            localImageFilePath != null &&
            localImageFilePath.isNotEmpty) {
          final uploadedUrl = await _uploadProductImage(
            baseUrl: baseUrl,
            filePath: localImageFilePath,
            cloudKey: cloudKey,
            oldImageUrl: imageUrl,
            companyIdentity: companyIdentity,
          );
          if (uploadedUrl != null) {
            imageUrl = uploadedUrl;
            if (p.id != null) {
              try {
                await repo.update(p.copyWith(imageUrl: uploadedUrl));
              } catch (_) {
                // No bloquear sync si falla el update local
              }
            }
          } else {
            await AppLogger.instance.logWarn(
              'Product image upload failed for code=${p.code}',
              module: 'cloud_sync',
            );
          }
        } else if (imageUrl != null && _isUploadsUrl(imageUrl, baseUrl)) {
          final imageAlive = await _isRemoteImageAlive(imageUrl);
          if (!imageAlive) {
            await AppLogger.instance.logWarn(
              'Broken remote product image detected code=${p.code} url=$imageUrl',
              module: 'cloud_sync',
            );
            if (p.id != null) {
              try {
                await repo.update(p.copyWith(imageUrl: null));
              } catch (_) {}
            }
            imageUrl = null;
          }

          if (!p.prefersImage) {
            if (imageUrl != null) {
              await _deleteProductImage(
                baseUrl: baseUrl,
                imageUrl: imageUrl,
                cloudKey: cloudKey,
                companyIdentity: companyIdentity,
              );
              if (p.id != null) {
                try {
                  await repo.update(p.copyWith(imageUrl: null));
                } catch (_) {}
              }
            }
            imageUrl = null;
          }
        }

        payloadProducts.add({
          'code': p.code.trim(),
          'name': p.name.trim(),
          if (p.categoryId != null &&
              categoryNamesById.containsKey(p.categoryId))
            'category': categoryNamesById[p.categoryId],
          'price': p.salePrice,
          'cost': p.purchasePrice,
          'stock': p.stock,
          // IMPORTANT: backend supports `imageUrl: null` to clear previous image.
          // If the product prefers a color placeholder, we should explicitly clear
          // any previously synced imageUrl.
          if (p.prefersImage) 'imageUrl': ?imageUrl,
          if (!p.prefersImage) 'imageUrl': null,
        });
      }

      final payload = {
        ...await _companyIdentityPayload(settings),
        if (rnc.isNotEmpty) 'companyRnc': rnc,
        if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
          'companyCloudId': cloudCompanyId,
        'products': payloadProducts,
        if (deletedCodes.isNotEmpty) 'deletedProducts': deletedCodes.toList(),
        'mirrorProducts': true,
      };

      final response = await _postByRncWithIdentityFallback(
        baseUrl: baseUrl,
        endpoint: '/api/products/sync/by-rnc',
        headers: headers,
        payload: payload,
        timeout: const Duration(seconds: 12),
        reason: 'products_sync',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        String body = '';
        try {
          body = response.body;
          if (body.length > 900) body = body.substring(0, 900);
        } catch (_) {}
        await AppLogger.instance.logWarn(
          'Cloud products sync failed status=${response.statusCode} baseUrl=$baseUrl body=$body',
          module: 'cloud_sync',
        );
        _recordSyncFailure('HTTP ${response.statusCode}: $body');
        return false;
      }

      await AppLogger.instance.logInfo(
        'Cloud products sync ok',
        module: 'cloud_sync',
      );
      final reconciled = await ProductSyncOutboxRepository()
          .reconcileVersionConflictsAfterFullSnapshot(
            snapshotStartedAtMs: snapshotStartedAtMs,
          );
      if (reconciled > 0) {
        await AppLogger.instance.logInfo(
          'Reconciled $reconciled stale product version conflicts after full snapshot',
          module: 'cloud_sync',
        );
      }
      return true;
    } catch (e) {
      _recordSyncFailure(e.toString());
      await AppLogger.instance.logWarn(
        'Cloud products sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<bool> syncClientsIfEnabled() async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) return true;
      final rnc = settings.rnc?.trim() ?? '';
      final cloudCompanyId = await _ensureCloudCompanyId(settings);
      if (rnc.isEmpty && (cloudCompanyId == null || cloudCompanyId.isEmpty)) {
        return false;
      }

      final baseUrl = _resolveBaseUrl(settings);
      final headers = <String, String>{'Content-Type': 'application/json'};
      final cloudKey = settings.cloudApiKey?.trim();
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }

      final db = await AppDb.database;
      final rows = await db.query(
        DbTables.clients,
        orderBy: 'updated_at_ms ASC',
      );
      final payloadClients = rows
          .map(
            (c) => {
              'localId': c['id'],
              'nombre': (c['nombre'] as String?) ?? '',
              'telefono': c['telefono'] as String?,
              'direccion': c['direccion'] as String?,
              'rnc': c['rnc'] as String?,
              'cedula': c['cedula'] as String?,
              'isActive': ((c['is_active'] as int?) ?? 1) == 1,
              'hasCredit': ((c['has_credit'] as int?) ?? 0) == 1,
              'updatedAt': DateTime.fromMillisecondsSinceEpoch(
                (c['updated_at_ms'] as int?) ??
                    DateTime.now().millisecondsSinceEpoch,
              ).toUtc().toIso8601String(),
              if ((c['created_at_ms'] as int?) != null)
                'createdAt': DateTime.fromMillisecondsSinceEpoch(
                  c['created_at_ms'] as int,
                ).toUtc().toIso8601String(),
              if ((c['deleted_at_ms'] as int?) != null)
                'deletedAt': DateTime.fromMillisecondsSinceEpoch(
                  c['deleted_at_ms'] as int,
                ).toUtc().toIso8601String(),
            },
          )
          .toList(growable: false);

      final payload = {
        ...await _companyIdentityPayload(settings),
        if (rnc.isNotEmpty) 'companyRnc': rnc,
        if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
          'companyCloudId': cloudCompanyId,
        'clients': payloadClients,
      };

      final response = await _postByRncWithIdentityFallback(
        baseUrl: baseUrl,
        endpoint: '/api/clients/sync/by-rnc',
        headers: headers,
        payload: payload,
        timeout: const Duration(seconds: 15),
        reason: 'clients_sync',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await AppLogger.instance.logWarn(
          'Cloud clients sync failed status=${response.statusCode}',
          module: 'cloud_sync',
        );
        _recordSyncFailure('HTTP ${response.statusCode}');
        return false;
      }

      await AppLogger.instance.logInfo(
        'Cloud clients sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
      _recordSyncFailure(e.toString());
      await AppLogger.instance.logWarn(
        'Cloud clients sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<bool> syncCategoriesIfEnabled() async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) return true;
      final rnc = settings.rnc?.trim() ?? '';
      final cloudCompanyId = await _ensureCloudCompanyId(settings);
      if (rnc.isEmpty && (cloudCompanyId == null || cloudCompanyId.isEmpty)) {
        return false;
      }

      final baseUrl = _resolveBaseUrl(settings);
      final headers = <String, String>{'Content-Type': 'application/json'};
      final cloudKey = settings.cloudApiKey?.trim();
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }

      final db = await AppDb.database;
      final rows = await db.query(
        DbTables.categories,
        orderBy: 'updated_at_ms ASC',
      );
      final payloadCategories = rows
          .map(
            (c) => {
              'localId': c['id'],
              'name': (c['name'] as String?) ?? '',
              'isActive': ((c['is_active'] as int?) ?? 1) == 1,
              'updatedAt': DateTime.fromMillisecondsSinceEpoch(
                (c['updated_at_ms'] as int?) ??
                    DateTime.now().millisecondsSinceEpoch,
              ).toUtc().toIso8601String(),
              if ((c['created_at_ms'] as int?) != null)
                'createdAt': DateTime.fromMillisecondsSinceEpoch(
                  c['created_at_ms'] as int,
                ).toUtc().toIso8601String(),
              if ((c['deleted_at_ms'] as int?) != null)
                'deletedAt': DateTime.fromMillisecondsSinceEpoch(
                  c['deleted_at_ms'] as int,
                ).toUtc().toIso8601String(),
            },
          )
          .toList(growable: false);

      final payload = {
        ...await _companyIdentityPayload(settings),
        if (rnc.isNotEmpty) 'companyRnc': rnc,
        if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
          'companyCloudId': cloudCompanyId,
        'categories': payloadCategories,
      };

      final response = await _postByRncWithIdentityFallback(
        baseUrl: baseUrl,
        endpoint: '/api/categories/sync/by-rnc',
        headers: headers,
        payload: payload,
        timeout: const Duration(seconds: 15),
        reason: 'categories_sync',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await AppLogger.instance.logWarn(
          'Cloud categories sync failed status=${response.statusCode}',
          module: 'cloud_sync',
        );
        _recordSyncFailure('HTTP ${response.statusCode}');
        return false;
      }

      await AppLogger.instance.logInfo(
        'Cloud categories sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
      _recordSyncFailure(e.toString());
      await AppLogger.instance.logWarn(
        'Cloud categories sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<bool> syncSuppliersIfEnabled() async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) return true;
      final rnc = settings.rnc?.trim() ?? '';
      final cloudCompanyId = await _ensureCloudCompanyId(settings);
      if (rnc.isEmpty && (cloudCompanyId == null || cloudCompanyId.isEmpty)) {
        return false;
      }

      final baseUrl = _resolveBaseUrl(settings);
      final headers = <String, String>{'Content-Type': 'application/json'};
      final cloudKey = settings.cloudApiKey?.trim();
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }

      final db = await AppDb.database;
      final rows = await db.query(
        DbTables.suppliers,
        orderBy: 'updated_at_ms ASC',
      );
      final payloadSuppliers = rows
          .map(
            (s) => {
              'localId': s['id'],
              'name': (s['name'] as String?) ?? '',
              'phone': s['phone'] as String?,
              'note': s['note'] as String?,
              'isActive': ((s['is_active'] as int?) ?? 1) == 1,
              'updatedAt': DateTime.fromMillisecondsSinceEpoch(
                (s['updated_at_ms'] as int?) ??
                    DateTime.now().millisecondsSinceEpoch,
              ).toUtc().toIso8601String(),
              if ((s['created_at_ms'] as int?) != null)
                'createdAt': DateTime.fromMillisecondsSinceEpoch(
                  s['created_at_ms'] as int,
                ).toUtc().toIso8601String(),
              if ((s['deleted_at_ms'] as int?) != null)
                'deletedAt': DateTime.fromMillisecondsSinceEpoch(
                  s['deleted_at_ms'] as int,
                ).toUtc().toIso8601String(),
            },
          )
          .toList(growable: false);

      final payload = {
        ...await _companyIdentityPayload(settings),
        if (rnc.isNotEmpty) 'companyRnc': rnc,
        if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
          'companyCloudId': cloudCompanyId,
        'suppliers': payloadSuppliers,
      };

      final response = await _postByRncWithIdentityFallback(
        baseUrl: baseUrl,
        endpoint: '/api/suppliers/sync/by-rnc',
        headers: headers,
        payload: payload,
        timeout: const Duration(seconds: 15),
        reason: 'suppliers_sync',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await AppLogger.instance.logWarn(
          'Cloud suppliers sync failed status=${response.statusCode}',
          module: 'cloud_sync',
        );
        _recordSyncFailure('HTTP ${response.statusCode}');
        return false;
      }

      await AppLogger.instance.logInfo(
        'Cloud suppliers sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
      _recordSyncFailure(e.toString());
      await AppLogger.instance.logWarn(
        'Cloud suppliers sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<bool> syncSalesIfEnabled() {
    return syncSalesIfEnabledDetailed();
  }

  Future<bool> syncSalesIfEnabledDetailed({
    String? traceSaleLocalCode,
    bool requireTraceLocalCode = false,
    String reason = 'sales_changed',
  }) async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) return true;
      final rnc = settings.rnc?.trim() ?? '';
      final cloudCompanyId = await _ensureCloudCompanyId(settings);
      if (rnc.isEmpty && (cloudCompanyId == null || cloudCompanyId.isEmpty)) {
        return false;
      }

      final baseUrl = _resolveBaseUrl(settings);
      final headers = <String, String>{'Content-Type': 'application/json'};
      final cloudKey = settings.cloudApiKey?.trim();
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }

      final backfilled = await SalesRepository.backfillMissingPurchasePrices();
      if (backfilled > 0) {
        await AppLogger.instance.logInfo(
          'Backfilled purchase price snapshots: $backfilled',
          module: 'cloud_sync',
        );
      }

      final now = DateTime.now();
      final from = now.subtract(const Duration(days: _historyDaysToSync));

      final localSales = await SalesRepository.listSales(
        dateFrom: from,
        dateTo: now,
      );
      final payloadSales = <Map<String, dynamic>>[];

      for (final s in localSales) {
        if (s.id == null) continue;
        // Excluir ventas eliminadas, EXCEPTO las que tienen status REFUNDED:
        // las ventas completamente reembolsadas se marcan como eliminadas (soft-delete)
        // en local, pero el backend necesita conocer su estado final REFUNDED.
        final statusForDeleteCheck = s.status.toString();
        if (s.deletedAtMs != null &&
            statusForDeleteCheck != 'REFUNDED' &&
            statusForDeleteCheck != 'PARTIAL_REFUND') {
          continue;
        }

        // Mantener consistencia con el reporte local (invoice + sale).
        if (s.kind != 'invoice' && s.kind != 'sale') continue;

        final saleWithItems = await SalesRepository.getSaleWithItems(s.id!);
        if (saleWithItems == null) continue;

        final sale = saleWithItems['sale'] as SaleModel;
        final items =
            (saleWithItems['items'] as List<SaleItemModel>?) ?? const [];

        // Mantener consistencia con el reporte local (solo ventas finalizadas).
        const allowedStatuses = {
          'completed',
          'LAYAWAY',
          'PAID',
          'PARTIAL_REFUND',
          'REFUNDED',
          'cancelled',
        };
        final status = (sale.status).toString();
        if (!allowedStatuses.contains(status)) continue;

        payloadSales.add({
          'localCode': sale.localCode,
          'kind': sale.kind,
          'status': status,
          'customerNameSnapshot': sale.customerNameSnapshot,
          'customerPhoneSnapshot': sale.customerPhoneSnapshot,
          'customerRncSnapshot': sale.customerRncSnapshot,
          'itbisEnabled': sale.itbisEnabled == 1,
          'itbisRate': sale.itbisRate,
          'discountTotal': sale.discountTotal,
          'subtotal': sale.subtotal,
          'itbisAmount': sale.itbisAmount,
          'total': sale.total,
          'paymentMethod': sale.paymentMethod,
          'paymentCashAmount': sale.paymentCashAmount,
          'paymentCardAmount': sale.paymentCardAmount,
          'paymentTransferAmount': sale.paymentTransferAmount,
          'paidAmount': sale.paidAmount,
          'changeAmount': sale.changeAmount,
          'creditInterestRate': sale.creditInterestRate,
          'creditTermDays': sale.creditTermDays,
          if (sale.creditDueDateMs != null)
            'creditDueDate': DateTime.fromMillisecondsSinceEpoch(
              sale.creditDueDateMs!,
            ).toUtc().toIso8601String(),
          'creditInstallments': sale.creditInstallments,
          'creditNote': sale.creditNote,
          'fiscalEnabled': sale.fiscalEnabled == 1,
          'fiscalReceiptTypeId': sale.fiscalReceiptTypeId,
          'fiscalReceiptName': sale.fiscalReceiptName,
          'fiscalReceiptPrefix': sale.fiscalReceiptPrefix,
          'ncfFull': sale.ncfFull,
          'ncfType': sale.ncfType,
          'fiscalSequenceNumber': sale.fiscalSequenceNumber,
          if (sale.fiscalReceiptExpirationDateMs != null)
            'fiscalReceiptExpirationDate': DateTime.fromMillisecondsSinceEpoch(
              sale.fiscalReceiptExpirationDateMs!,
            ).toUtc().toIso8601String(),
          'electronicInvoiceEnabled': sale.electronicInvoiceEnabled == 1,
          'electronicInvoiceCode': sale.electronicInvoiceCode,
          'electronicDocumentType': sale.electronicDocumentType,
          'sessionLocalId': sale.sessionId,
          'createdAt': DateTime.fromMillisecondsSinceEpoch(
            sale.createdAtMs,
          ).toUtc().toIso8601String(),
          'updatedAt': DateTime.fromMillisecondsSinceEpoch(
            sale.updatedAtMs,
          ).toUtc().toIso8601String(),
          if (sale.deletedAtMs != null)
            'deletedAt': DateTime.fromMillisecondsSinceEpoch(
              sale.deletedAtMs!,
            ).toUtc().toIso8601String(),
          'items': items
              .map(
                (i) => {
                  'productCodeSnapshot': i.productCodeSnapshot,
                  'localId': i.id,
                  'productNameSnapshot': i.productNameSnapshot,
                  'qty': i.qty,
                  'unitPrice': i.unitPrice,
                  'purchasePriceSnapshot': i.purchasePriceSnapshot,
                  'discountLine': i.discountLine,
                  'totalLine': i.totalLine,
                  'createdAt': DateTime.fromMillisecondsSinceEpoch(
                    i.createdAtMs,
                  ).toUtc().toIso8601String(),
                },
              )
              .toList(),
        });
      }

      final trimmedTraceLocalCode = traceSaleLocalCode?.trim();
      final traceIncludedInPayload = trimmedTraceLocalCode == null
          ? null
          : payloadSales.any(
              (row) =>
                  (row['localCode']?.toString() ?? '').trim() ==
                  trimmedTraceLocalCode,
            );

      var tracedRemoteSaleId = 'null';
      var tracedSaleConfirmed = trimmedTraceLocalCode == null;

      await AppLogger.instance.logInfo(
        'Cloud sales sync start reason=$reason traceSaleLocalCode=${trimmedTraceLocalCode ?? 'null'} requireTraceLocalCode=$requireTraceLocalCode traceIncludedInPayload=${traceIncludedInPayload?.toString() ?? 'null'} companyCloudId=${cloudCompanyId ?? 'null'} companyRnc=${rnc.isEmpty ? 'null' : rnc} count=${payloadSales.length}',
        module: 'cloud_sync',
      );

      for (var i = 0; i < payloadSales.length; i += _chunkSize) {
        final chunk = payloadSales.sublist(
          i,
          (i + _chunkSize) > payloadSales.length
              ? payloadSales.length
              : (i + _chunkSize),
        );

        final chunkHasTrace = trimmedTraceLocalCode == null
            ? null
            : chunk.any(
                (row) =>
                    (row['localCode']?.toString() ?? '').trim() ==
                    trimmedTraceLocalCode,
              );

        final payload = {
          ...await _companyIdentityPayload(settings),
          if (rnc.isNotEmpty) 'companyRnc': rnc,
          if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
            'companyCloudId': cloudCompanyId,
          'sales': chunk,
        };

        final response = await _postByRncWithIdentityFallback(
          baseUrl: baseUrl,
          endpoint: '/api/sales/sync/by-rnc',
          headers: headers,
          payload: payload,
          timeout: const Duration(seconds: 20),
          reason: 'sales_sync_$reason',
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          await AppLogger.instance.logWarn(
            'Cloud sales sync failed reason=$reason status=${response.statusCode} response=${response.body}',
            module: 'cloud_sync',
          );
          _recordSyncFailure('HTTP ${response.statusCode}');
          return false;
        }

        Map<String, dynamic> decoded;
        try {
          final parsed = jsonDecode(response.body);
          decoded = parsed is Map<String, dynamic>
              ? parsed
              : <String, dynamic>{};
        } catch (_) {
          decoded = <String, dynamic>{};
        }
        final results = decoded['results'];
        Map<String, dynamic>? tracedSale;
        if (trimmedTraceLocalCode != null && results is List) {
          for (final entry in results) {
            if (entry is! Map) continue;
            final row = Map<String, dynamic>.from(entry);
            if ((row['localCode']?.toString() ?? '').trim() ==
                trimmedTraceLocalCode) {
              tracedSale = row;
              break;
            }
          }
        }

        if (!tracedSaleConfirmed && tracedSale != null) {
          tracedRemoteSaleId = tracedSale['id']?.toString() ?? 'null';
          tracedSaleConfirmed = true;
        }

        await AppLogger.instance.logInfo(
          'Cloud sales sync response reason=$reason status=${response.statusCode} chunkOffset=$i chunkSize=${chunk.length} chunkHasTrace=${chunkHasTrace?.toString() ?? 'null'} traceSaleLocalCode=${trimmedTraceLocalCode ?? 'null'} tracedRemoteSaleId=${tracedSale?['id']?.toString() ?? 'null'} responseHasResults=${(results is List).toString()} response=${response.body}',
          module: 'cloud_sync',
        );
      }

      if (requireTraceLocalCode && trimmedTraceLocalCode != null) {
        if (!traceIncludedInPayload!) {
          await AppLogger.instance.logWarn(
            'Cloud sales sync trace not included in payload reason=$reason traceSaleLocalCode=$trimmedTraceLocalCode payloadCount=${payloadSales.length}',
            module: 'cloud_sync',
          );
          return false;
        }

        if (!tracedSaleConfirmed) {
          await AppLogger.instance.logWarn(
            'Cloud sales sync missing traced sale after all chunks reason=$reason traceSaleLocalCode=$trimmedTraceLocalCode',
            module: 'cloud_sync',
          );
          return false;
        }
      }

      await AppLogger.instance.logInfo(
        'Cloud sales sync ok reason=$reason traceSaleLocalCode=${trimmedTraceLocalCode ?? 'null'} tracedRemoteSaleId=$tracedRemoteSaleId',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
      _recordSyncFailure(e.toString());
      await AppLogger.instance.logWarn(
        'Cloud sales sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<bool> syncPaymentsIfEnabled() async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) return true;
      final rnc = settings.rnc?.trim() ?? '';
      final cloudCompanyId = await _ensureCloudCompanyId(settings);
      if (rnc.isEmpty && (cloudCompanyId == null || cloudCompanyId.isEmpty)) {
        return false;
      }

      final baseUrl = _resolveBaseUrl(settings);
      final headers = <String, String>{'Content-Type': 'application/json'};
      final cloudKey = settings.cloudApiKey?.trim();
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }

      final db = await AppDb.database;
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: _historyDaysToSync));
      final fromMs = from.millisecondsSinceEpoch;
      final toMs = now.millisecondsSinceEpoch;

      final creditRows = await db.rawQuery(
        '''
          SELECT
            cp.id as local_id,
            cp.amount,
            cp.method,
            cp.note,
            cp.created_at_ms,
            s.local_code as sale_local_code,
            s.session_id as session_local_id,
            s.total as sale_total,
            s.paid_amount as sale_paid_amount,
            s.status as sale_status,
            s.credit_interest_rate as credit_interest_rate
          FROM ${DbTables.creditPayments} cp
          INNER JOIN ${DbTables.sales} s ON s.id = cp.sale_id
          WHERE cp.created_at_ms >= ?
            AND cp.created_at_ms <= ?
            AND s.deleted_at_ms IS NULL
          ORDER BY cp.created_at_ms ASC
        ''',
        [fromMs, toMs],
      );

      final layawayRows = await db.rawQuery(
        '''
          SELECT
            lp.id as local_id,
            lp.amount,
            lp.method,
            lp.note,
            lp.created_at_ms,
            s.local_code as sale_local_code,
            s.session_id as session_local_id,
            s.total as sale_total,
            s.paid_amount as sale_paid_amount,
            s.status as sale_status
          FROM ${DbTables.layawayPayments} lp
          INNER JOIN ${DbTables.sales} s ON s.id = lp.sale_id
          WHERE lp.created_at_ms >= ?
            AND lp.created_at_ms <= ?
            AND s.deleted_at_ms IS NULL
          ORDER BY lp.created_at_ms ASC
        ''',
        [fromMs, toMs],
      );

      final payloadPayments = <Map<String, dynamic>>[];

      for (final row in creditRows) {
        final saleTotal = (row['sale_total'] as num?)?.toDouble() ?? 0.0;
        final interestRate =
            (row['credit_interest_rate'] as num?)?.toDouble() ?? 0.0;
        final totalDue = saleTotal + (saleTotal * interestRate / 100.0);
        final totalPaid = (row['sale_paid_amount'] as num?)?.toDouble() ?? 0.0;
        final pendingAmount = max(0.0, totalDue - totalPaid);
        payloadPayments.add({
          'localId': row['local_id'],
          'kind': 'credit',
          'saleLocalCode': row['sale_local_code'],
          'sessionLocalId': row['session_local_id'],
          'amount': (row['amount'] as num?)?.toDouble() ?? 0.0,
          'method': (row['method'] as String?) ?? 'cash',
          'note': row['note'] as String?,
          'createdAt': DateTime.fromMillisecondsSinceEpoch(
            (row['created_at_ms'] as int?) ?? now.millisecondsSinceEpoch,
          ).toUtc().toIso8601String(),
          'totalDueSnapshot': totalDue,
          'totalPaidSnapshot': totalPaid,
          'pendingAmountSnapshot': pendingAmount,
          'statusSnapshot': row['sale_status'],
        });
      }

      for (final row in layawayRows) {
        final totalDue = (row['sale_total'] as num?)?.toDouble() ?? 0.0;
        final totalPaid = (row['sale_paid_amount'] as num?)?.toDouble() ?? 0.0;
        final pendingAmount = max(0.0, totalDue - totalPaid);
        payloadPayments.add({
          'localId': row['local_id'],
          'kind': 'layaway',
          'saleLocalCode': row['sale_local_code'],
          'sessionLocalId': row['session_local_id'],
          'amount': (row['amount'] as num?)?.toDouble() ?? 0.0,
          'method': (row['method'] as String?) ?? 'cash',
          'note': row['note'] as String?,
          'createdAt': DateTime.fromMillisecondsSinceEpoch(
            (row['created_at_ms'] as int?) ?? now.millisecondsSinceEpoch,
          ).toUtc().toIso8601String(),
          'totalDueSnapshot': totalDue,
          'totalPaidSnapshot': totalPaid,
          'pendingAmountSnapshot': pendingAmount,
          'statusSnapshot': row['sale_status'],
        });
      }

      if (payloadPayments.isEmpty) {
        return true;
      }

      payloadPayments.sort((a, b) {
        final left = DateTime.parse(a['createdAt'] as String);
        final right = DateTime.parse(b['createdAt'] as String);
        return left.compareTo(right);
      });

      for (var i = 0; i < payloadPayments.length; i += _chunkSize) {
        final chunk = payloadPayments.sublist(
          i,
          (i + _chunkSize) > payloadPayments.length
              ? payloadPayments.length
              : (i + _chunkSize),
        );

        final payload = {
          ...await _companyIdentityPayload(settings),
          if (rnc.isNotEmpty) 'companyRnc': rnc,
          if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
            'companyCloudId': cloudCompanyId,
          'payments': chunk,
        };

        final response = await _postByRncWithIdentityFallback(
          baseUrl: baseUrl,
          endpoint: '/api/payments/sync/by-rnc',
          headers: headers,
          payload: payload,
          timeout: const Duration(seconds: 20),
          reason: 'payments_sync',
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          await AppLogger.instance.logWarn(
            'Cloud payments sync failed status=${response.statusCode}',
            module: 'cloud_sync',
          );
          _recordSyncFailure('HTTP ${response.statusCode}');
          return false;
        }
      }

      await AppLogger.instance.logInfo(
        'Cloud payments sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
      _recordSyncFailure(e.toString());
      await AppLogger.instance.logWarn(
        'Cloud payments sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<bool> syncReturnsIfEnabled() async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) return true;
      final rnc = settings.rnc?.trim() ?? '';
      final cloudCompanyId = await _ensureCloudCompanyId(settings);
      if (rnc.isEmpty && (cloudCompanyId == null || cloudCompanyId.isEmpty)) {
        return false;
      }

      final baseUrl = _resolveBaseUrl(settings);
      final headers = <String, String>{'Content-Type': 'application/json'};
      final cloudKey = settings.cloudApiKey?.trim();
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }

      final db = await AppDb.database;
      final now = DateTime.now();
      final from = now.subtract(const Duration(days: _historyDaysToSync));
      final fromMs = from.millisecondsSinceEpoch;
      final toMs = now.millisecondsSinceEpoch;

      final returnRows = await db.rawQuery(
        '''
          SELECT
            r.id as return_id,
            r.original_sale_id,
            r.return_sale_id,
            r.refund_type,
            r.reason,
            r.note,
            r.electronic_credit_note_requested,
            r.created_at_ms,
            os.local_code as original_sale_local_code,
            rs.local_code as return_sale_local_code,
            rs.session_id as session_local_id
          FROM ${DbTables.returns} r
          INNER JOIN ${DbTables.sales} os ON os.id = r.original_sale_id
          INNER JOIN ${DbTables.sales} rs ON rs.id = r.return_sale_id
          WHERE r.created_at_ms >= ?
            AND r.created_at_ms <= ?
          ORDER BY r.created_at_ms ASC
        ''',
        [fromMs, toMs],
      );

      if (returnRows.isEmpty) {
        return true;
      }

      final returnIds = returnRows
          .map((row) => row['return_id'] as int)
          .toList(growable: false);
      final placeholders = List.filled(returnIds.length, '?').join(',');
      final returnItemRows = await db.rawQuery('''
          SELECT
            ri.id as local_id,
            ri.return_id,
            ri.sale_item_id as sale_item_local_id,
            ri.product_id,
            ri.description,
            ri.qty,
            ri.price,
            ri.total,
            COALESCE(p.code, si.product_code_snapshot) as product_code_snapshot
          FROM ${DbTables.returnItems} ri
          LEFT JOIN ${DbTables.saleItems} si ON si.id = ri.sale_item_id
          LEFT JOIN ${DbTables.products} p ON p.id = COALESCE(ri.product_id, si.product_id)
          WHERE ri.return_id IN ($placeholders)
          ORDER BY ri.id ASC
        ''', returnIds);

      final itemsByReturnId = <int, List<Map<String, dynamic>>>{};
      for (final row in returnItemRows) {
        final returnId = row['return_id'] as int;
        itemsByReturnId
            .putIfAbsent(returnId, () => <Map<String, dynamic>>[])
            .add({
              'localId': row['local_id'],
              'saleItemLocalId': row['sale_item_local_id'],
              'productCodeSnapshot': row['product_code_snapshot'] as String?,
              'description': (row['description'] as String?) ?? 'Producto',
              'qty': (row['qty'] as num).toDouble(),
              'price': (row['price'] as num).toDouble(),
              'total': (row['total'] as num).toDouble(),
            });
      }

      final payloadReturns = returnRows
          .map((row) {
            final returnId = row['return_id'] as int;
            final originalSaleLocalCode =
                row['original_sale_local_code'] as String?;
            final returnSaleLocalCode =
                row['return_sale_local_code'] as String?;
            if (originalSaleLocalCode == null || returnSaleLocalCode == null) {
              return null;
            }

            return {
              'localId': returnId,
              'originalSaleLocalCode': originalSaleLocalCode,
              'returnSaleLocalCode': returnSaleLocalCode,
              'sessionLocalId': row['session_local_id'] as int?,
              'refundType': (row['refund_type'] as String?) ?? 'PARTIAL',
              'reason': row['reason'] as String? ?? row['note'] as String?,
              'note': row['note'] as String?,
              'electronicCreditNoteRequested':
                  (row['electronic_credit_note_requested'] as int? ?? 0) == 1,
              'createdAt': DateTime.fromMillisecondsSinceEpoch(
                row['created_at_ms'] as int,
              ).toUtc().toIso8601String(),
              'items':
                  itemsByReturnId[returnId] ?? const <Map<String, dynamic>>[],
            };
          })
          .whereType<Map<String, dynamic>>()
          .where((row) => (row['items'] as List).isNotEmpty)
          .toList(growable: false);

      for (var i = 0; i < payloadReturns.length; i += _chunkSize) {
        final chunk = payloadReturns.sublist(
          i,
          (i + _chunkSize) > payloadReturns.length
              ? payloadReturns.length
              : (i + _chunkSize),
        );

        final payload = {
          ...await _companyIdentityPayload(settings),
          if (rnc.isNotEmpty) 'companyRnc': rnc,
          if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
            'companyCloudId': cloudCompanyId,
          'returns': chunk,
        };

        final response = await _postByRncWithIdentityFallback(
          baseUrl: baseUrl,
          endpoint: '/api/returns/sync/by-rnc',
          headers: headers,
          payload: payload,
          timeout: const Duration(seconds: 20),
          reason: 'returns_sync',
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          await AppLogger.instance.logWarn(
            'Cloud returns sync failed status=${response.statusCode}',
            module: 'cloud_sync',
          );
          _recordSyncFailure('HTTP ${response.statusCode}');
          return false;
        }

        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final results = decoded['results'];
          if (results is List) {
            await _applySyncedReturnResults(results.cast<dynamic>());
          }
        }
      }

      await AppLogger.instance.logInfo(
        'Cloud returns sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
      _recordSyncFailure(e.toString());
      await AppLogger.instance.logWarn(
        'Cloud returns sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<void> _applySyncedReturnResults(List<dynamic> rows) async {
    if (rows.isEmpty) return;
    final db = await AppDb.database;

    for (final entry in rows) {
      if (entry is! Map) continue;
      final localId = entry['localId'];
      if (localId is! int) continue;

      final electronicCreditNote = entry['electronicCreditNote'];
      final ecf = electronicCreditNote is Map
          ? (electronicCreditNote['ecf'] as String?)?.trim()
          : null;
      final status = electronicCreditNote is Map
          ? (electronicCreditNote['status'] as String?)?.trim()
          : null;
      final trackId = electronicCreditNote is Map
          ? (electronicCreditNote['trackId'] as String?)?.trim()
          : null;
      final invoiceId = electronicCreditNote is Map
          ? electronicCreditNote['invoiceId'] as int?
          : null;
      final requested = electronicCreditNote is Map
          ? electronicCreditNote['requested'] == true
          : false;
      final returnSaleLocalCode = (entry['returnSaleLocalCode'] as String?)
          ?.trim();

      await db.update(
        DbTables.returns,
        {
          'refund_type': entry['refundType'] as String? ?? 'PARTIAL',
          'subtotal_amount':
              (entry['subtotalAmount'] as num?)?.toDouble() ?? 0.0,
          'tax_amount': (entry['taxAmount'] as num?)?.toDouble() ?? 0.0,
          'total_amount': (entry['totalAmount'] as num?)?.toDouble() ?? 0.0,
          'electronic_credit_note_requested': requested ? 1 : 0,
          'electronic_credit_note_invoice_id': invoiceId,
          'electronic_credit_note_ecf': ecf,
          'electronic_credit_note_status': status,
          'electronic_credit_note_track_id': trackId,
          'original_electronic_ecf': electronicCreditNote is Map
              ? electronicCreditNote['originalEcf'] as String?
              : null,
          'original_electronic_document_type': electronicCreditNote is Map
              ? electronicCreditNote['originalDocumentType'] as String?
              : null,
        },
        where: 'id = ?',
        whereArgs: [localId],
      );

      if (returnSaleLocalCode != null &&
          returnSaleLocalCode.isNotEmpty &&
          ecf != null &&
          ecf.isNotEmpty) {
        final saleRows = await db.query(
          DbTables.sales,
          columns: ['id'],
          where: 'local_code = ?',
          whereArgs: [returnSaleLocalCode],
          limit: 1,
        );
        if (saleRows.isNotEmpty) {
          final saleId = saleRows.first['id'] as int?;
          if (saleId != null) {
            await db.update(
              DbTables.sales,
              {
                'electronic_invoice_enabled': 1,
                'electronic_invoice_code': ecf,
                'electronic_document_type': '34',
              },
              where: 'id = ?',
              whereArgs: [saleId],
            );

            await FacturaElectronicaRepository.upsert(
              FacturaElectronicaModel(
                saleId: saleId,
                localCode: returnSaleLocalCode,
                ecf: ecf,
                tipoDocumento: '34',
                dgiiTrackId: trackId,
                estadoDgii: _mapBackendDgiiStatus(status),
                mensajeDgii: status,
                montoTotal: ((entry['totalAmount'] as num?)?.toDouble() ?? 0.0)
                    .abs(),
                createdAtMs: DateTime.now().millisecondsSinceEpoch,
                updatedAtMs: DateTime.now().millisecondsSinceEpoch,
              ),
            );
          }
        }
      }
    }
  }

  String _mapBackendDgiiStatus(String? status) {
    switch ((status ?? '').trim().toUpperCase()) {
      case 'ACCEPTED':
        return FacturaElectronicaModel.statusAccepted;
      case 'REJECTED':
        return FacturaElectronicaModel.statusRejected;
      case 'IN_PROCESS':
      case 'SUBMITTED':
      case 'NOT_SENT':
        return FacturaElectronicaModel.statusPending;
      default:
        return FacturaElectronicaModel.statusPending;
    }
  }

  Future<bool> syncCashIfEnabled() async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) return true;
      final rnc = settings.rnc?.trim() ?? '';
      final cloudCompanyId = await _ensureCloudCompanyId(settings);
      if (rnc.isEmpty && (cloudCompanyId == null || cloudCompanyId.isEmpty)) {
        return false;
      }

      final baseUrl = _resolveBaseUrl(settings);
      final headers = <String, String>{'Content-Type': 'application/json'};
      final cloudKey = settings.cloudApiKey?.trim();
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }

      final now = DateTime.now();
      final from = now.subtract(const Duration(days: _historyDaysToSync));
      final fromMs = from.millisecondsSinceEpoch;
      final db = await AppDb.database;

      final movementsRows = await db.query(
        DbTables.cashMovements,
        where: 'created_at_ms >= ?',
        whereArgs: [fromMs],
        orderBy: 'created_at_ms DESC',
        limit: 8000,
      );
      final movementSessionIds = movementsRows
          .map((row) => row['session_id'] as int?)
          .whereType<int>()
          .toSet()
          .toList(growable: false);

      final sessionsRows = movementSessionIds.isEmpty
          ? await db.query(
              DbTables.cashSessions,
              where: 'closed_at_ms IS NOT NULL AND closed_at_ms >= ?',
              whereArgs: [fromMs],
              orderBy: 'closed_at_ms DESC',
              limit: 3000,
            )
          : await db.query(
              DbTables.cashSessions,
              where:
                  '(closed_at_ms IS NOT NULL AND closed_at_ms >= ?) OR id IN (${List.filled(movementSessionIds.length, '?').join(', ')})',
              whereArgs: [fromMs, ...movementSessionIds],
              orderBy: 'opened_at_ms DESC',
              limit: 3000,
            );
      final sessions = sessionsRows.map((row) {
        final localId = row['id'] as int;
        final openedAtMs = row['opened_at_ms'] as int;
        final closedAtMs = row['closed_at_ms'] as int?;
        return {
          'localId': localId,
          'openedByUserName': (row['user_name'] as String?) ?? 'admin',
          'openedAt': DateTime.fromMillisecondsSinceEpoch(
            openedAtMs,
          ).toUtc().toIso8601String(),
          'closedAt': closedAtMs != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  closedAtMs,
                ).toUtc().toIso8601String()
              : null,
          'initialAmount': (row['initial_amount'] as num?)?.toDouble() ?? 0.0,
          'closingAmount': (row['closing_amount'] as num?)?.toDouble(),
          'expectedCash': (row['expected_cash'] as num?)?.toDouble(),
          'difference': (row['difference'] as num?)?.toDouble(),
          'status': (row['status'] as String?) ?? 'CLOSED',
          'note': row['note'] as String?,
        };
      }).toList();

      final movements = movementsRows.map((row) {
        final localId = row['id'] as int;
        final sessionLocalId = row['session_id'] as int;
        final createdAtMs = row['created_at_ms'] as int;
        return {
          'localId': localId,
          'sessionLocalId': sessionLocalId,
          'type': (row['type'] as String?) ?? 'IN',
          'movementType': (row['movement_type'] as String?) ?? 'expense',
          'affectsProfit': ((row['affects_profit'] as num?) ?? 1) == 1,
          'amount': (row['amount'] as num).toDouble(),
          'note': (row['reason'] as String?) ?? (row['note'] as String?),
          'createdAt': DateTime.fromMillisecondsSinceEpoch(
            createdAtMs,
          ).toUtc().toIso8601String(),
        };
      }).toList();

      final payload = {
        ...await _companyIdentityPayload(settings),
        if (rnc.isNotEmpty) 'companyRnc': rnc,
        if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
          'companyCloudId': cloudCompanyId,
        'sessions': sessions,
        'movements': movements,
      };

      final response = await _postByRncWithIdentityFallback(
        baseUrl: baseUrl,
        endpoint: '/api/cash/sync/by-rnc',
        headers: headers,
        payload: payload,
        timeout: const Duration(seconds: 20),
        reason: 'cash_sync',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await AppLogger.instance.logWarn(
          'Cloud cash sync failed status=${response.statusCode}',
          module: 'cloud_sync',
        );
        _recordSyncFailure('HTTP ${response.statusCode}');
        return false;
      }

      await AppLogger.instance.logInfo(
        'Cloud cash sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
      _recordSyncFailure(e.toString());
      await AppLogger.instance.logWarn(
        'Cloud cash sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<bool> syncQuotesIfEnabled() async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) return true;
      final rnc = settings.rnc?.trim() ?? '';
      final cloudCompanyId = await _ensureCloudCompanyId(settings);
      if (rnc.isEmpty && (cloudCompanyId == null || cloudCompanyId.isEmpty)) {
        return false;
      }

      final baseUrl = _resolveBaseUrl(settings);
      final headers = <String, String>{'Content-Type': 'application/json'};
      final cloudKey = settings.cloudApiKey?.trim();
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }

      final now = DateTime.now();
      final from = now.subtract(const Duration(days: _historyDaysToSync));
      final fromMs = from.millisecondsSinceEpoch;
      final db = await AppDb.database;

      final quoteRows = await db.rawQuery(
        '''
        SELECT q.*, c.nombre AS client_name, c.telefono AS client_phone, c.rnc AS client_rnc
        FROM ${DbTables.quotes} q
        INNER JOIN ${DbTables.clients} c ON q.client_id = c.id
        WHERE q.created_at_ms >= ?
        ORDER BY q.created_at_ms DESC
        ''',
        [fromMs],
      );

      final quotesPayload = <Map<String, dynamic>>[];
      for (final row in quoteRows) {
        final localId = row['id'] as int;
        final createdAtMs = row['created_at_ms'] as int;
        final updatedAtMs = row['updated_at_ms'] as int;

        final items = await db.query(
          DbTables.quoteItems,
          where: 'quote_id = ?',
          whereArgs: [localId],
          orderBy: 'id ASC',
        );

        quotesPayload.add({
          'localId': localId,
          'clientNameSnapshot': (row['client_name'] as String?) ?? 'Cliente',
          'clientPhoneSnapshot': row['client_phone'] as String?,
          'clientRncSnapshot': row['client_rnc'] as String?,
          'ticketName': row['ticket_name'] as String?,
          'subtotal': (row['subtotal'] as num?)?.toDouble() ?? 0.0,
          'itbisEnabled': (row['itbis_enabled'] as int? ?? 1) == 1,
          'itbisRate': (row['itbis_rate'] as num?)?.toDouble() ?? 0.18,
          'itbisAmount': (row['itbis_amount'] as num?)?.toDouble() ?? 0.0,
          'discountTotal': (row['discount_total'] as num?)?.toDouble() ?? 0.0,
          'total': (row['total'] as num?)?.toDouble() ?? 0.0,
          'status': row['status'] as String? ?? 'OPEN',
          'notes': row['notes'] as String?,
          'createdAt': DateTime.fromMillisecondsSinceEpoch(
            createdAtMs,
          ).toUtc().toIso8601String(),
          'updatedAt': DateTime.fromMillisecondsSinceEpoch(
            updatedAtMs,
          ).toUtc().toIso8601String(),
          'items': items.map((i) {
            final unitPrice =
                ((i['unit_price'] ?? i['price']) as num?)?.toDouble() ?? 0.0;

            return {
              'productCodeSnapshot': i['product_code_snapshot']?.toString(),
              'productNameSnapshot':
                  (i['product_name_snapshot']?.toString()) ?? 'N/A',
              'description': (i['description']?.toString()) ?? '',
              'qty': (i['qty'] as num?)?.toDouble() ?? 0.0,
              'unitPrice': unitPrice,
              'cost': (i['cost'] as num?)?.toDouble() ?? 0.0,
              'discountLine': (i['discount_line'] as num?)?.toDouble() ?? 0.0,
              'totalLine': (i['total_line'] as num?)?.toDouble() ?? 0.0,
            };
          }).toList(),
        });
      }

      for (var i = 0; i < quotesPayload.length; i += _chunkSize) {
        final chunk = quotesPayload.sublist(
          i,
          (i + _chunkSize) > quotesPayload.length
              ? quotesPayload.length
              : (i + _chunkSize),
        );

        final payload = {
          ...await _companyIdentityPayload(settings),
          if (rnc.isNotEmpty) 'companyRnc': rnc,
          if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
            'companyCloudId': cloudCompanyId,
          'quotes': chunk,
        };

        final response = await _postByRncWithIdentityFallback(
          baseUrl: baseUrl,
          endpoint: '/api/quotes/sync/by-rnc',
          headers: headers,
          payload: payload,
          timeout: const Duration(seconds: 20),
          reason: 'quotes_sync',
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await AppLogger.instance.logWarn(
            'Cloud quotes sync failed status=${response.statusCode}',
            module: 'cloud_sync',
          );
          _recordSyncFailure('HTTP ${response.statusCode}');
          return false;
        }
      }

      await AppLogger.instance.logInfo(
        'Cloud quotes sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
      _recordSyncFailure(e.toString());
      await AppLogger.instance.logWarn(
        'Cloud quotes sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<bool> provisionAdminUser({
    required String cloudUsername,
    required String password,
  }) async {
    try {
      final settings = await BusinessSettingsRepository().loadSettings();
      if (!settings.cloudEnabled) return false;
      final rnc = settings.rnc?.trim() ?? '';
      final cloudCompanyId = await _ensureCloudCompanyId(settings);
      if (rnc.isEmpty && (cloudCompanyId == null || cloudCompanyId.isEmpty)) {
        return false;
      }

      final baseUrl = _resolveBaseUrl(settings);
      final headers = <String, String>{'Content-Type': 'application/json'};
      final cloudKey = settings.cloudApiKey?.trim();
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }

      final payload = {
        ...await _companyIdentityPayload(settings),
        if (rnc.isNotEmpty) 'companyRnc': rnc,
        if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
          'companyCloudId': cloudCompanyId,
        'companyName': settings.businessName,
        'username': cloudUsername.trim(),
        'password': password,
        'role': 'admin',
      };

      final api = ApiClient(baseUrl: baseUrl);
      final response = await api.postJson(
        provisionUserPath,
        headers: headers,
        body: payload,
        timeout: const Duration(seconds: 8),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await AppLogger.instance.logWarn(
          'Cloud user provision failed status=${response.statusCode}',
          module: 'cloud_sync',
        );
        return false;
      }
      return true;
    } catch (e) {
      await AppLogger.instance.logWarn(
        'Cloud user provision error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<Map<String, dynamic>> _buildPayload(
    BusinessSettings settings,
    String rnc,
    String? cloudCompanyId,
  ) async {
    final themeKey = await _loadThemeKey();
    final logoUrl = _normalizeUrl(settings.logoPath);

    return <String, dynamic>{
      ...await _companyIdentityPayload(settings),
      if (rnc.isNotEmpty) 'companyRnc': rnc,
      if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
        'companyCloudId': cloudCompanyId,
      'companyName': _normalizeText(settings.businessName) ?? 'Empresa',
      'logoUrl': ?logoUrl,
      'phone': _normalizeText(settings.phone),
      'phone2': _normalizeText(settings.phone2),
      'email': _normalizeEmail(settings.email),
      'address': _normalizeText(settings.address),
      'city': _normalizeText(settings.city),
      'slogan': _normalizeText(settings.slogan),
      'website': _normalizeUrl(settings.website),
      'instagramUrl': _normalizeUrl(settings.instagramUrl),
      'facebookUrl': _normalizeUrl(settings.facebookUrl),
      'themeKey': ?themeKey,
    };
  }

  String _resolveBaseUrl(BusinessSettings settings) {
    final endpoint = settings.cloudEndpoint?.trim();
    final raw = (endpoint != null && endpoint.isNotEmpty)
        ? endpoint
        : backendBaseUrl;

    // Normalizar para evitar errores comunes (ej: pegar URL terminando en /api
    // o pegar una URL con ruta /api/xxx en vez de la raíz del backend).
    final normalized = AppConfig.normalizeBaseUrl(raw);
    try {
      final uri = Uri.parse(normalized);
      final path = uri.path.trim();
      if (path.isNotEmpty && path != '/' && path != '/api') {
        return AppConfig.normalizeBaseUrl(
          uri.replace(path: '', query: '', fragment: '').toString(),
        );
      }
      if (path == '/api') {
        return AppConfig.normalizeBaseUrl(
          uri.replace(path: '', query: '', fragment: '').toString(),
        );
      }
    } catch (_) {}

    if (normalized.endsWith('/api')) {
      return normalized.substring(0, normalized.length - 4);
    }
    return normalized;
  }

  String? _normalizeText(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  String? _normalizeUrl(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return null;
    if (!v.startsWith('http')) return null;
    return v;
  }

  String? _normalizeEmail(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return null;
    final isValid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
    return isValid ? v : null;
  }

  Future<String?> _loadThemeKey() async {
    try {
      final prefs = await PrefsSafe.getInstance();
      if (prefs == null) return AppThemeEnum.proPos.key;
      final key = prefs.getString('app_theme') ?? AppThemeEnum.proPos.key;
      return AppThemes.getThemeEnumByKey(key).key;
    } catch (_) {
      return AppThemeEnum.proPos.key;
    }
  }

  String _generateCloudCompanyId() {
    final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rand = Random();
    final suffix = List.generate(
      6,
      (_) => rand.nextInt(36).toRadixString(36),
    ).join();
    return 'fp-$now-$suffix';
  }

  Future<String?> _ensureCloudCompanyId(BusinessSettings settings) async {
    final existing = settings.cloudCompanyId?.trim();
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _generateCloudCompanyId();
    final repo = BusinessSettingsRepository();
    await repo.updateField('cloud_company_id', generated);
    return generated;
  }

  bool _isUploadsUrl(String url, String baseUrl) {
    try {
      final parsed = Uri.parse(url);
      if (!parsed.path.startsWith('/uploads/products/')) return false;
      final base = Uri.parse(baseUrl);
      return parsed.host == base.host;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isRemoteImageAlive(String url) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final cached = _imageHealthCache[url];
    if (cached != null) {
      final ttlMs = cached.ok ? 30 * 60 * 1000 : 5 * 60 * 1000;
      if (now - cached.checkedAtMs < ttlMs) {
        return cached.ok;
      }
    }

    try {
      final request = await http
          .head(Uri.parse(url), headers: const {'Accept': 'image/*,*/*;q=0.8'})
          .timeout(const Duration(seconds: 5));
      final contentType = (request.headers['content-type'] ?? '').toLowerCase();
      final ok =
          request.statusCode >= 200 &&
          request.statusCode < 300 &&
          contentType.startsWith('image/');
      _imageHealthCache[url] = (ok: ok, checkedAtMs: now);
      return ok;
    } catch (_) {
      _imageHealthCache[url] = (ok: false, checkedAtMs: now);
      return false;
    }
  }

  Future<String?> _uploadProductImage({
    required String baseUrl,
    required String filePath,
    required CloudCompanyIdentity companyIdentity,
    String? oldImageUrl,
    String? cloudKey,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final api = ApiClient(baseUrl: baseUrl);
      final uri = api.uri('/api/uploads/product-image');
      final request = http.MultipartRequest('POST', uri);
      if (cloudKey != null && cloudKey.isNotEmpty) {
        request.headers['x-cloud-key'] = cloudKey;
      }
      final tenantKey = companyIdentity.companyTenantKey?.trim();
      if (tenantKey != null && tenantKey.isNotEmpty) {
        request.headers['x-company-tenant-key'] = tenantKey;
      }
      if (companyIdentity.companyCloudId != null &&
          companyIdentity.companyCloudId!.isNotEmpty) {
        request.headers['x-company-cloud-id'] = companyIdentity.companyCloudId!;
      }
      final identityPayload = companyIdentity.toPayload();
      for (final entry in identityPayload.entries) {
        final value = entry.value;
        if (value == null) continue;
        final asText = value.toString().trim();
        if (asText.isEmpty) continue;
        request.fields[entry.key] = asText;
      }
      if (oldImageUrl != null && oldImageUrl.isNotEmpty) {
        request.fields['oldImageUrl'] = oldImageUrl;
      }
      final lower = filePath.toLowerCase();
      MediaType contentType;
      if (lower.endsWith('.png')) {
        contentType = MediaType('image', 'png');
      } else if (lower.endsWith('.webp')) {
        contentType = MediaType('image', 'webp');
      } else {
        // Default to jpeg so servers that validate mimetype don't reject.
        contentType = MediaType('image', 'jpeg');
      }

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          contentType: contentType,
        ),
      );

      final response = await api.sendMultipart(
        request,
        timeout: const Duration(seconds: 20),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        try {
          final body = await response.stream.bytesToString();
          await AppLogger.instance.logWarn(
            'Upload failed status=${response.statusCode} body=$body',
            module: 'cloud_sync',
          );
        } catch (_) {}
        return null;
      }
      final body = await response.stream.bytesToString();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final url = decoded['url']?.toString();
      return url;
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteProductImage({
    required String baseUrl,
    required String imageUrl,
    required CloudCompanyIdentity companyIdentity,
    String? cloudKey,
  }) async {
    try {
      final parsed = Uri.parse(imageUrl);
      final filename = parsed.pathSegments.isNotEmpty
          ? parsed.pathSegments.last
          : '';
      if (filename.isEmpty) return;

      final headers = <String, String>{};
      if (cloudKey != null && cloudKey.isNotEmpty) {
        headers['x-cloud-key'] = cloudKey;
      }
      final tenantKey = companyIdentity.companyTenantKey?.trim();
      if (tenantKey != null && tenantKey.isNotEmpty) {
        headers['x-company-tenant-key'] = tenantKey;
      }
      if (companyIdentity.companyCloudId != null &&
          companyIdentity.companyCloudId!.isNotEmpty) {
        headers['x-company-cloud-id'] = companyIdentity.companyCloudId!;
      }
      final queryParams = <String, String>{};
      final identityPayload = companyIdentity.toPayload();
      for (final entry in identityPayload.entries) {
        final value = entry.value;
        if (value == null) continue;
        final asText = value.toString().trim();
        if (asText.isEmpty) continue;
        queryParams[entry.key] = asText;
      }
      final query = Uri(queryParameters: queryParams).query;
      final api = ApiClient(baseUrl: baseUrl);
      await api.delete(
        '/api/uploads/product-image/$filename${query.isNotEmpty ? '?$query' : ''}',
        headers: headers,
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {}
  }
}
