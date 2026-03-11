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
import '../../features/settings/data/business_settings_model.dart';
import '../../features/settings/data/business_settings_repository.dart';
import '../../features/products/data/products_repository.dart';
import '../../features/products/models/product_model.dart';
import '../../features/sales/data/sales_repository.dart';
import '../../features/sales/data/sales_model.dart';
import '../config/backend_config.dart';
import '../config/app_config.dart';
import '../logging/app_logger.dart';
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

  /// Devuelve la URL efectiva usada para nube (considera `cloudEndpoint` si existe).
  ///
  /// Útil para diagnóstico en UI.
  String debugResolveCloudBaseUrl(BusinessSettings settings) {
    return _resolveBaseUrl(settings);
  }

  static const int _historyDaysToSync = 90;
  static const int _chunkSize = 200;

  void startRealtimeSyncEngine() {
    if (_engineStarted) return;
    _engineStarted = true;

    _outboxPollingTimer?.cancel();
    _outboxPollingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(_drainOutbox());
    });
    unawaited(_drainOutbox());
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
    Duration delay = const Duration(milliseconds: 800),
    String reason = 'products_changed',
  }) {
    unawaited(
      _enqueueTarget(CloudSyncTarget.products, delay: delay, reason: reason),
    );
  }

  void scheduleSalesSyncSoon({
    Duration delay = const Duration(milliseconds: 600),
    String reason = 'sales_changed',
  }) {
    unawaited(
      _enqueueTarget(CloudSyncTarget.sales, delay: delay, reason: reason),
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

  Future<void> retryAllFailedSyncNow() async {
    await _outbox.retryAllFailedNow();
    _kickOutboxDispatcher();
  }

  Future<List<Map<String, dynamic>>> readSyncStatusRows() {
    return _outbox.listStatusRows();
  }

  Future<void> _enqueueTarget(
    CloudSyncTarget target, {
    required Duration delay,
    required String reason,
  }) async {
    await _outbox.enqueue(target: target.value, reason: reason, delay: delay);
    await AppLogger.instance.logInfo(
      'Sync job queued target=${target.value} reason=$reason delayMs=${delay.inMilliseconds}',
      module: 'cloud_sync',
    );
    _kickOutboxDispatcher();
  }

  void _kickOutboxDispatcher() {
    _outboxDispatchDebounce?.cancel();
    _outboxDispatchDebounce = Timer(const Duration(milliseconds: 250), () {
      _outboxDispatchDebounce = null;
      unawaited(_drainOutbox());
    });
  }

  Future<void> _drainOutbox() async {
    if (_outboxRunning) return;
    _outboxRunning = true;
    try {
      while (true) {
        final dueTargets = await _outbox.listDueTargets(limit: 8);
        if (dueTargets.isEmpty) break;

        for (final rawTarget in dueTargets) {
          final target = CloudSyncTarget.tryParse(rawTarget);
          if (target == null) continue;

          await _outbox.markSyncing(target.value);
          final startedAt = DateTime.now().millisecondsSinceEpoch;
          await AppLogger.instance.logInfo(
            'Sync started target=${target.value}',
            module: 'cloud_sync',
          );

          final success = await _runTargetSync(target);
          final duration = DateTime.now().millisecondsSinceEpoch - startedAt;

          if (success) {
            await _outbox.markSuccess(target.value, durationMs: duration);
            await AppLogger.instance.logInfo(
              'Sync success target=${target.value} durationMs=$duration',
              module: 'cloud_sync',
            );
            continue;
          }

          final attempts = (await _outbox.getAttemptCount(target.value)) + 1;
          final retryDelay = _retryDelayForAttempt(attempts);
          await _outbox.markFailure(
            target.value,
            error: 'sync_failed',
            attemptCount: attempts,
            retryDelay: retryDelay,
          );
          await AppLogger.instance.logWarn(
            'Sync failed target=${target.value} attempts=$attempts retryInMs=${retryDelay.inMilliseconds}',
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
        return false;
      }

      await AppLogger.instance.logInfo('Cloud sync ok', module: 'cloud_sync');
      return true;
    } catch (e) {
      await AppLogger.instance.logWarn(
        'Cloud sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<bool> syncProductsIfEnabled() async {
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
            companyRnc: rnc.isNotEmpty ? rnc : null,
            companyCloudId:
                (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
                ? cloudCompanyId
                : null,
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
          if (!p.prefersImage) {
            await _deleteProductImage(
              baseUrl: baseUrl,
              imageUrl: imageUrl,
              cloudKey: cloudKey,
            );
            if (p.id != null) {
              try {
                await repo.update(p.copyWith(imageUrl: null));
              } catch (_) {}
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
          if (p.prefersImage)
            if (imageUrl != null) 'imageUrl': imageUrl,
          if (!p.prefersImage) 'imageUrl': null,
        });
      }

      final payload = {
        if (rnc.isNotEmpty) 'companyRnc': rnc,
        if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
          'companyCloudId': cloudCompanyId,
        'products': payloadProducts,
        if (deletedCodes.isNotEmpty) 'deletedProducts': deletedCodes.toList(),
      };

      final api = ApiClient(baseUrl: baseUrl);
      final response = await api.postJson(
        '/api/products/sync/by-rnc',
        headers: headers,
        body: payload,
        timeout: const Duration(seconds: 12),
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
        return false;
      }

      await AppLogger.instance.logInfo(
        'Cloud products sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
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
        if (rnc.isNotEmpty) 'companyRnc': rnc,
        if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
          'companyCloudId': cloudCompanyId,
        'clients': payloadClients,
      };

      final api = ApiClient(baseUrl: baseUrl);
      final response = await api.postJson(
        '/api/clients/sync/by-rnc',
        headers: headers,
        body: payload,
        timeout: const Duration(seconds: 15),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await AppLogger.instance.logWarn(
          'Cloud clients sync failed status=${response.statusCode}',
          module: 'cloud_sync',
        );
        return false;
      }

      await AppLogger.instance.logInfo(
        'Cloud clients sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
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
        if (rnc.isNotEmpty) 'companyRnc': rnc,
        if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
          'companyCloudId': cloudCompanyId,
        'categories': payloadCategories,
      };

      final api = ApiClient(baseUrl: baseUrl);
      final response = await api.postJson(
        '/api/categories/sync/by-rnc',
        headers: headers,
        body: payload,
        timeout: const Duration(seconds: 15),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await AppLogger.instance.logWarn(
          'Cloud categories sync failed status=${response.statusCode}',
          module: 'cloud_sync',
        );
        return false;
      }

      await AppLogger.instance.logInfo(
        'Cloud categories sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
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
        if (rnc.isNotEmpty) 'companyRnc': rnc,
        if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
          'companyCloudId': cloudCompanyId,
        'suppliers': payloadSuppliers,
      };

      final api = ApiClient(baseUrl: baseUrl);
      final response = await api.postJson(
        '/api/suppliers/sync/by-rnc',
        headers: headers,
        body: payload,
        timeout: const Duration(seconds: 15),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await AppLogger.instance.logWarn(
          'Cloud suppliers sync failed status=${response.statusCode}',
          module: 'cloud_sync',
        );
        return false;
      }

      await AppLogger.instance.logInfo(
        'Cloud suppliers sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
      await AppLogger.instance.logWarn(
        'Cloud suppliers sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
    }
  }

  Future<bool> syncSalesIfEnabled() async {
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
        if (s.deletedAtMs != null) continue;

        // Mantener consistencia con el reporte local (invoice + sale).
        if (s.kind != 'invoice' && s.kind != 'sale') continue;

        final saleWithItems = await SalesRepository.getSaleWithItems(s.id!);
        if (saleWithItems == null) continue;

        final sale = saleWithItems['sale'] as SaleModel;
        final items =
            (saleWithItems['items'] as List<SaleItemModel>?) ?? const [];

        // Mantener consistencia con el reporte local (solo ventas finalizadas).
        const allowedStatuses = {'completed', 'PAID', 'PARTIAL_REFUND'};
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
          'paidAmount': sale.paidAmount,
          'changeAmount': sale.changeAmount,
          'fiscalEnabled': sale.fiscalEnabled == 1,
          'ncfFull': sale.ncfFull,
          'ncfType': sale.ncfType,
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

      for (var i = 0; i < payloadSales.length; i += _chunkSize) {
        final chunk = payloadSales.sublist(
          i,
          (i + _chunkSize) > payloadSales.length
              ? payloadSales.length
              : (i + _chunkSize),
        );

        final payload = {
          if (rnc.isNotEmpty) 'companyRnc': rnc,
          if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
            'companyCloudId': cloudCompanyId,
          'sales': chunk,
        };

        final api = ApiClient(baseUrl: baseUrl);
        final response = await api.postJson(
          '/api/sales/sync/by-rnc',
          headers: headers,
          body: payload,
          timeout: const Duration(seconds: 20),
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          await AppLogger.instance.logWarn(
            'Cloud sales sync failed status=${response.statusCode}',
            module: 'cloud_sync',
          );
          return false;
        }
      }

      await AppLogger.instance.logInfo(
        'Cloud sales sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
      await AppLogger.instance.logWarn(
        'Cloud sales sync error: ${e.toString()}',
        module: 'cloud_sync',
      );
      return false;
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

      final sessionsRows = await db.query(
        DbTables.cashSessions,
        where: 'closed_at_ms IS NOT NULL AND closed_at_ms >= ?',
        whereArgs: [fromMs],
        orderBy: 'closed_at_ms DESC',
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

      final movementsRows = await db.query(
        DbTables.cashMovements,
        where: 'created_at_ms >= ?',
        whereArgs: [fromMs],
        orderBy: 'created_at_ms DESC',
        limit: 8000,
      );
      final movements = movementsRows.map((row) {
        final localId = row['id'] as int;
        final sessionLocalId = row['session_id'] as int;
        final createdAtMs = row['created_at_ms'] as int;
        return {
          'localId': localId,
          'sessionLocalId': sessionLocalId,
          'type': (row['type'] as String?) ?? 'IN',
          'amount': (row['amount'] as num).toDouble(),
          'note': (row['reason'] as String?) ?? (row['note'] as String?),
          'createdAt': DateTime.fromMillisecondsSinceEpoch(
            createdAtMs,
          ).toUtc().toIso8601String(),
        };
      }).toList();

      final payload = {
        if (rnc.isNotEmpty) 'companyRnc': rnc,
        if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
          'companyCloudId': cloudCompanyId,
        'sessions': sessions,
        'movements': movements,
      };

      final api = ApiClient(baseUrl: baseUrl);
      final response = await api.postJson(
        '/api/cash/sync/by-rnc',
        headers: headers,
        body: payload,
        timeout: const Duration(seconds: 20),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        await AppLogger.instance.logWarn(
          'Cloud cash sync failed status=${response.statusCode}',
          module: 'cloud_sync',
        );
        return false;
      }

      await AppLogger.instance.logInfo(
        'Cloud cash sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
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
          if (rnc.isNotEmpty) 'companyRnc': rnc,
          if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
            'companyCloudId': cloudCompanyId,
          'quotes': chunk,
        };

        final api = ApiClient(baseUrl: baseUrl);
        final response = await api.postJson(
          '/api/quotes/sync/by-rnc',
          headers: headers,
          body: payload,
          timeout: const Duration(seconds: 20),
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await AppLogger.instance.logWarn(
            'Cloud quotes sync failed status=${response.statusCode}',
            module: 'cloud_sync',
          );
          return false;
        }
      }

      await AppLogger.instance.logInfo(
        'Cloud quotes sync ok',
        module: 'cloud_sync',
      );
      return true;
    } catch (e) {
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
      if (rnc.isNotEmpty) 'companyRnc': rnc,
      if (cloudCompanyId != null && cloudCompanyId.isNotEmpty)
        'companyCloudId': cloudCompanyId,
      'companyName': _normalizeText(settings.businessName) ?? 'Empresa',
      if (logoUrl != null) 'logoUrl': logoUrl,
      'phone': _normalizeText(settings.phone),
      'phone2': _normalizeText(settings.phone2),
      'email': _normalizeEmail(settings.email),
      'address': _normalizeText(settings.address),
      'city': _normalizeText(settings.city),
      'slogan': _normalizeText(settings.slogan),
      'website': _normalizeUrl(settings.website),
      'instagramUrl': _normalizeUrl(settings.instagramUrl),
      'facebookUrl': _normalizeUrl(settings.facebookUrl),
      if (themeKey != null) 'themeKey': themeKey,
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

  Future<String?> _uploadProductImage({
    required String baseUrl,
    required String filePath,
    String? oldImageUrl,
    String? cloudKey,
    String? companyRnc,
    String? companyCloudId,
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
      if (oldImageUrl != null && oldImageUrl.isNotEmpty) {
        request.fields['oldImageUrl'] = oldImageUrl;
      }
      if (companyRnc != null && companyRnc.isNotEmpty) {
        request.fields['companyRnc'] = companyRnc;
      }
      if (companyCloudId != null && companyCloudId.isNotEmpty) {
        request.fields['companyCloudId'] = companyCloudId;
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
      final api = ApiClient(baseUrl: baseUrl);
      await api.delete(
        '/api/uploads/product-image/$filename',
        headers: headers,
        timeout: const Duration(seconds: 8),
      );
    } catch (_) {}
  }
}
