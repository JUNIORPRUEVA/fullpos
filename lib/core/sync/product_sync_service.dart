import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:sqflite/sqflite.dart';

import '../../features/products/models/product_model.dart';
import '../../features/settings/data/business_settings_repository.dart';
import '../db/app_db.dart';
import '../db/tables.dart';
import '../logging/app_logger.dart';
import '../network/api_client.dart';
import '../services/cloud_sync_service.dart';
import 'product_sync_event_bus.dart';
import 'product_sync_outbox_repository.dart';

class ProductRealtimeEvent {
  const ProductRealtimeEvent({
    required this.eventId,
    required this.type,
    required this.product,
  });

  final String eventId;
  final String type;
  final ProductModel product;
}

class ProductSyncService {
  ProductSyncService._();

  static final ProductSyncService instance = ProductSyncService._();

  final ProductSyncOutboxRepository _outbox = ProductSyncOutboxRepository();
  final ValueNotifier<String> connectionState = ValueNotifier<String>(
    'disconnected',
  );

  Timer? _dispatchDebounce;
  Timer? _pollingTimer;
  bool _draining = false;
  bool _started = false;
  io.Socket? _socket;
  final Set<String> _seenEventIds = <String>{};

  void start() {
    if (_started) return;
    _started = true;
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      unawaited(_drainOutbox());
      unawaited(_ensureRealtimeConnection());
    });
    unawaited(_drainOutbox());
    unawaited(_ensureRealtimeConnection());
  }

  void scheduleProcessing({Duration delay = Duration.zero}) {
    _dispatchDebounce?.cancel();
    _dispatchDebounce = Timer(delay, () {
      _dispatchDebounce = null;
      unawaited(_drainOutbox());
    });
  }

  Future<List<Map<String, dynamic>>> readStatusRows() {
    return _outbox.listStatusRows();
  }

  Future<int> pendingCount() {
    return _outbox.pendingCount();
  }

  Future<int?> lastSuccessAtMs() {
    return _outbox.lastSuccessAtMs();
  }

  Future<void> retryFailedNow() async {
    await _outbox.retryFailedNow();
    scheduleProcessing();
  }

  Future<void> _drainOutbox() async {
    if (_draining) return;
    _draining = true;
    try {
      while (true) {
        final items = await _outbox.listDueItems(limit: 10);
        if (items.isEmpty) break;

        for (final item in items) {
          final id = item['id'] as int;
          final retryCount = (item['retry_count'] as int?) ?? 0;
          await _outbox.markSyncing(id);
          await AppLogger.instance.logInfo(
            'Product sync request start outboxId=$id op=${item['operation_type']}',
            module: 'product_sync',
          );

          try {
            final payload = jsonDecode(item['payload_json'] as String)
                as Map<String, dynamic>;
            final response = await _pushOperation(payload);
            await _applyServerProduct(
              response.product,
              clearSyncError: true,
              markNeedsSync: false,
            );
            await _outbox.markSuccess(id);
            await AppLogger.instance.logInfo(
              'Product sync success outboxId=$id productId=${response.product.id} type=${response.eventType}',
              module: 'product_sync',
            );
          } on _ProductSyncConflict catch (conflict) {
            await _markConflict(conflict.serverProduct, conflict.message);
            await _outbox.markFailure(
              id,
              error: conflict.message,
              retryCount: retryCount + 1,
              retryDelay: const Duration(minutes: 10),
            );
            await AppLogger.instance.logWarn(
              'Conflict detected localProductId=${conflict.localProductId} serverId=${conflict.serverProduct.serverId} message=${conflict.message}',
              module: 'product_sync',
            );
          } catch (error) {
            final nextRetry = _retryDelayForAttempt(retryCount + 1);
            await _markProductFailed(
              localProductId: item['entity_id'] as int,
              message: error.toString(),
            );
            await _outbox.markFailure(
              id,
              error: error.toString(),
              retryCount: retryCount + 1,
              retryDelay: nextRetry,
            );
            await AppLogger.instance.logWarn(
              'Product sync failure outboxId=$id retry=${retryCount + 1} error=$error',
              module: 'product_sync',
            );
          }
        }
      }
    } finally {
      _draining = false;
    }
  }

  Duration _retryDelayForAttempt(int attempt) {
    final safeAttempt = attempt < 1 ? 1 : attempt;
    final seconds = min(300, 1 << min(8, safeAttempt));
    return Duration(seconds: seconds);
  }

  Future<_PushResult> _pushOperation(Map<String, dynamic> payload) async {
    final settings = await BusinessSettingsRepository().loadSettings();
    if (!settings.cloudEnabled) {
      throw StateError('Cloud sync disabled');
    }

    final companyRnc = settings.rnc?.trim() ?? '';
    final companyCloudId = settings.cloudCompanyId?.trim() ?? '';
    if (companyRnc.isEmpty && companyCloudId.isEmpty) {
      throw StateError('Cloud company not configured');
    }

    final baseUrl = CloudSyncService.instance.debugResolveCloudBaseUrl(settings);
    final headers = <String, String>{'Content-Type': 'application/json'};
    final cloudKey = settings.cloudApiKey?.trim();
    if (cloudKey != null && cloudKey.isNotEmpty) {
      headers['x-cloud-key'] = cloudKey;
    }

    final response = await ApiClient(baseUrl: baseUrl).postJson(
      '/api/products/sync/operations',
      headers: headers,
      body: {
        if (companyRnc.isNotEmpty) 'companyRnc': companyRnc,
        if (companyCloudId.isNotEmpty) 'companyCloudId': companyCloudId,
        'operations': [payload],
      },
      timeout: const Duration(seconds: 12),
    );

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 409) {
      final conflictProduct = _serverProductFromJson(
        body['serverProduct'] as Map<String, dynamic>,
      );
      throw _ProductSyncConflict(
        localProductId: (payload['localProductId'] as num).toInt(),
        serverProduct: conflictProduct,
        message: (body['message'] as String?) ?? 'server_conflict',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(body['message']?.toString() ?? 'sync_failed');
    }

    final productBody = body['product'];
    if (productBody is! Map<String, dynamic>) {
      return _PushResult(
        eventType: body['eventType'] as String? ?? 'product.deleted',
        product: _fallbackProductFromPayload(payload),
      );
    }

    return _PushResult(
      eventType: body['eventType'] as String? ?? 'product.updated',
      product: _serverProductFromJson(productBody),
    );
  }

  ProductModel _fallbackProductFromPayload(Map<String, dynamic> payload) {
    final product = Map<String, dynamic>.from(
      (payload['product'] as Map?) ?? const <String, dynamic>{},
    );
    final occurredAtRaw = payload['occurredAt']?.toString();
    final occurredAt = occurredAtRaw == null
        ? DateTime.now()
        : DateTime.tryParse(occurredAtRaw) ?? DateTime.now();
    final deletedAtRaw = product['deletedAt']?.toString();
    final deletedAt = deletedAtRaw == null
        ? null
        : DateTime.tryParse(deletedAtRaw);
    return ProductModel(
      id: 0,
      businessId: product['businessId']?.toString(),
      serverId: (payload['serverProductId'] as num?)?.toInt(),
      code: product['code']?.toString() ?? '',
      name: product['name']?.toString() ?? '',
      imageUrl: product['imageUrl'] as String?,
      purchasePrice: (product['cost'] as num?)?.toDouble() ?? 0,
      salePrice: (product['price'] as num?)?.toDouble() ?? 0,
      stock: (product['stock'] as num?)?.toDouble() ?? 0,
      isActive: product['isActive'] as bool? ?? false,
      syncStatus: 'synced',
      localUpdatedAtMs: occurredAt.millisecondsSinceEpoch,
      serverUpdatedAtMs: occurredAt.millisecondsSinceEpoch,
      version: (payload['baseVersion'] as num?)?.toInt() ?? 0,
      lastModifiedBy: payload['lastModifiedBy']?.toString(),
      lastSyncError: null,
      needsSync: false,
      lastSyncedAtMs: DateTime.now().millisecondsSinceEpoch,
      deletedAtMs: deletedAt?.millisecondsSinceEpoch,
      createdAtMs: occurredAt.millisecondsSinceEpoch,
      updatedAtMs: occurredAt.millisecondsSinceEpoch,
    );
  }

  ProductModel _serverProductFromJson(Map<String, dynamic> json) {
    final updatedAt = DateTime.parse(json['updatedAt'] as String);
    final deletedAtRaw = json['deletedAt'] as String?;
    final deletedAt = deletedAtRaw == null ? null : DateTime.parse(deletedAtRaw);
    return ProductModel(
      id: 0,
      businessId: json['businessId']?.toString(),
      serverId: (json['id'] as num?)?.toInt(),
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      purchasePrice: (json['cost'] as num?)?.toDouble() ?? 0,
      salePrice: (json['price'] as num?)?.toDouble() ?? 0,
      stock: (json['stock'] as num?)?.toDouble() ?? 0,
      stockMin: 0,
      isActive: json['isActive'] as bool? ?? true,
      syncStatus: 'synced',
      localUpdatedAtMs: updatedAt.millisecondsSinceEpoch,
      serverUpdatedAtMs: updatedAt.millisecondsSinceEpoch,
      version: (json['version'] as num?)?.toInt() ?? 0,
      lastModifiedBy: json['lastModifiedBy']?.toString(),
      lastSyncError: null,
      needsSync: false,
      lastSyncedAtMs: DateTime.now().millisecondsSinceEpoch,
      deletedAtMs: deletedAt?.millisecondsSinceEpoch,
      createdAtMs: updatedAt.millisecondsSinceEpoch,
      updatedAtMs: updatedAt.millisecondsSinceEpoch,
    );
  }

  Future<void> _applyServerProduct(
    ProductModel serverProduct, {
    required bool clearSyncError,
    required bool markNeedsSync,
  }) async {
    final db = await AppDb.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      final localRows = await txn.query(
        DbTables.products,
        where: 'server_id = ? OR code = ?',
        whereArgs: [serverProduct.serverId, serverProduct.code],
        limit: 1,
      );

      final localId = localRows.isEmpty
          ? null
          : (localRows.first['id'] as int?);
      final local = localRows.isEmpty ? null : ProductModel.fromMap(localRows.first);

      if (local != null &&
          local.needsSync &&
          serverProduct.version > local.version &&
          markNeedsSync == false) {
        throw _ProductSyncConflict(
          localProductId: local.id ?? 0,
          serverProduct: serverProduct,
          message: 'server_version_newer_than_local_pending_change',
        );
      }

      final values = <String, Object?>{
        'business_id': serverProduct.businessId,
        'server_id': serverProduct.serverId,
        'code': serverProduct.code,
        'name': serverProduct.name,
        'image_url': serverProduct.imageUrl,
        'purchase_price': serverProduct.purchasePrice,
        'sale_price': serverProduct.salePrice,
        'stock': serverProduct.stock,
        'is_active': serverProduct.isActive ? 1 : 0,
        'sync_status': markNeedsSync ? 'pending' : 'synced',
        'local_updated_at_ms': local?.localUpdatedAtMs ?? serverProduct.localUpdatedAtMs,
        'server_updated_at_ms': serverProduct.serverUpdatedAtMs,
        'version': serverProduct.version,
        'last_modified_by': serverProduct.lastModifiedBy,
        'last_sync_error': clearSyncError ? null : serverProduct.lastSyncError,
        'needs_sync': markNeedsSync ? 1 : 0,
        'last_synced_at_ms': now,
        'deleted_at_ms': serverProduct.deletedAtMs,
        'updated_at_ms': serverProduct.serverUpdatedAtMs ?? serverProduct.updatedAtMs,
      };

      if (localId == null) {
        await txn.insert(
          DbTables.products,
          {
            ...serverProduct.toMap(),
            ...values,
            'created_at_ms': serverProduct.createdAtMs,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        await txn.update(
          DbTables.products,
          values,
          where: 'id = ?',
          whereArgs: [localId],
        );
      }

      final resolvedId = localId ??
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT id FROM ${DbTables.products} WHERE server_id = ? OR code = ? ORDER BY id DESC LIMIT 1',
              [serverProduct.serverId, serverProduct.code],
            ),
          );
      if (resolvedId != null) {
        ProductSyncEventBus.instance.emit(
          ProductSyncChange(
            localProductId: resolvedId,
            serverProductId: serverProduct.serverId,
            reason: 'server_snapshot_applied',
          ),
        );
      }
    });
  }

  Future<void> _markProductFailed({
    required int localProductId,
    required String message,
  }) async {
    final db = await AppDb.database;
    await db.update(
      DbTables.products,
      {
        'sync_status': 'failed',
        'last_sync_error': message,
        'needs_sync': 1,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [localProductId],
    );
  }

  Future<void> _markConflict(ProductModel serverProduct, String message) async {
    final db = await AppDb.database;
    await db.update(
      DbTables.products,
      {
        'sync_status': 'conflict',
        'last_sync_error': message,
      },
      where: 'server_id = ? OR code = ?',
      whereArgs: [serverProduct.serverId, serverProduct.code],
    );
  }

  Future<void> _ensureRealtimeConnection() async {
    final settings = await BusinessSettingsRepository().loadSettings();
    if (!settings.cloudEnabled) {
      _disposeSocket();
      return;
    }

    final companyRnc = settings.rnc?.trim() ?? '';
    final companyCloudId = settings.cloudCompanyId?.trim() ?? '';
    if (companyRnc.isEmpty && companyCloudId.isEmpty) {
      _disposeSocket();
      return;
    }

    final current = _socket;
    if (current != null &&
        (current.connected || current.disconnected == false)) {
      return;
    }

    final baseUrl = CloudSyncService.instance.debugResolveCloudBaseUrl(settings);
    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableReconnection()
        .setReconnectionAttempts(999999)
        .setReconnectionDelay(1500)
        .setAuth({
          'clientType': 'pos',
          'companyRnc': companyRnc,
          'companyCloudId': companyCloudId,
          'cloudKey': settings.cloudApiKey,
        })
        .build();

    final socket = io.io(baseUrl, options);
    socket.onConnect((_) async {
      connectionState.value = 'connected';
      await AppLogger.instance.logInfo(
        'Product realtime socket connected',
        module: 'product_sync',
      );
    });
    socket.onDisconnect((_) async {
      connectionState.value = 'disconnected';
      await AppLogger.instance.logWarn(
        'Product realtime socket disconnected',
        module: 'product_sync',
      );
    });
    socket.onReconnect((_) async {
      connectionState.value = 'connected';
      await AppLogger.instance.logInfo(
        'Product realtime socket reconnected',
        module: 'product_sync',
      );
    });
    socket.onConnectError((error) async {
      connectionState.value = 'error';
      await AppLogger.instance.logWarn(
        'Product realtime socket connect error: $error',
        module: 'product_sync',
      );
    });
    socket.on('product.event', (data) {
      unawaited(_handleRealtimePayload(data));
    });
    socket.connect();
    _socket = socket;
    connectionState.value = 'connecting';
  }

  Future<void> _handleRealtimePayload(dynamic data) async {
    if (data is! Map) return;
    final payload = Map<String, dynamic>.from(data);
    final eventId = payload['eventId']?.toString() ?? '';
    if (eventId.isNotEmpty && !_seenEventIds.add(eventId)) {
      return;
    }
    if (_seenEventIds.length > 200) {
      _seenEventIds.remove(_seenEventIds.first);
    }

    final productJson = payload['product'];
    if (productJson is! Map) return;
    final product = _serverProductFromJson(
      Map<String, dynamic>.from(productJson),
    );
    await AppLogger.instance.logInfo(
      'Websocket event received type=${payload['type']} productId=${product.serverId}',
      module: 'product_sync',
    );
    try {
      await _applyServerProduct(
        product,
        clearSyncError: true,
        markNeedsSync: false,
      );
    } on _ProductSyncConflict catch (conflict) {
      await _markConflict(conflict.serverProduct, conflict.message);
      await AppLogger.instance.logWarn(
        'Conflict detected during realtime apply localProductId=${conflict.localProductId} message=${conflict.message}',
        module: 'product_sync',
      );
    }
  }

  void _disposeSocket() {
    _socket?.dispose();
    _socket = null;
    connectionState.value = 'disconnected';
  }
}

class _PushResult {
  const _PushResult({required this.eventType, required this.product});

  final String eventType;
  final ProductModel product;
}

class _ProductSyncConflict implements Exception {
  const _ProductSyncConflict({
    required this.localProductId,
    required this.serverProduct,
    required this.message,
  });

  final int localProductId;
  final ProductModel serverProduct;
  final String message;

  @override
  String toString() => message;
}