import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PendingRegistrationItem {
  final String id;
  final Map<String, dynamic> payload;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;
  final DateTime? lastAttemptAt;

  const PendingRegistrationItem({
    required this.id,
    required this.payload,
    required this.attempts,
    required this.lastError,
    required this.createdAt,
    required this.lastAttemptAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'payload': payload,
    'attempts': attempts,
    'last_error': lastError,
    'created_at': createdAt.toIso8601String(),
    'last_attempt_at': lastAttemptAt?.toIso8601String(),
  };

  static PendingRegistrationItem fromJson(Map<String, dynamic> json) {
    return PendingRegistrationItem(
      id: (json['id'] ?? '').toString(),
      payload: (json['payload'] is Map)
          ? (json['payload'] as Map).cast<String, dynamic>()
          : <String, dynamic>{},
      attempts: int.tryParse((json['attempts'] ?? '0').toString()) ?? 0,
      lastError: (json['last_error'] ?? '').toString().trim().isEmpty
          ? null
          : (json['last_error'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      lastAttemptAt: DateTime.tryParse((json['last_attempt_at'] ?? '').toString()),
    );
  }

  PendingRegistrationItem copyWith({
    int? attempts,
    String? lastError,
    DateTime? lastAttemptAt,
  }) {
    return PendingRegistrationItem(
      id: id,
      payload: payload,
      attempts: attempts ?? this.attempts,
      lastError: lastError,
      createdAt: createdAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    );
  }
}

class PendingRegistrationQueue {
  static const _fileName = 'pending_registration_queue_v1.json';

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    final base = Directory(p.join(dir.path, 'FullPOS'));
    if (!base.existsSync()) base.createSync(recursive: true);
    return File(p.join(base.path, _fileName));
  }

  Future<List<PendingRegistrationItem>> load() async {
    final f = await _file();
    if (!await f.exists()) return <PendingRegistrationItem>[];
    try {
      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <PendingRegistrationItem>[];
      return decoded
          .whereType<Map>()
          .map((m) => PendingRegistrationItem.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return <PendingRegistrationItem>[];
    }
  }

  Future<void> save(List<PendingRegistrationItem> items) async {
    final f = await _file();
    final data = items.map((e) => e.toJson()).toList();
    await f.writeAsString(jsonEncode(data));
  }

  Future<void> enqueue(PendingRegistrationItem item) async {
    final items = await load();
    // Deduplicate by business_id if present.
    final businessId = (item.payload['business_id'] ?? '').toString().trim();
    final filtered = items.where((e) {
      final bid = (e.payload['business_id'] ?? '').toString().trim();
      return businessId.isEmpty || bid != businessId;
    }).toList();

    filtered.add(item);
    await save(filtered);
  }

  Future<void> replaceItem(PendingRegistrationItem updated) async {
    final items = await load();
    final next = <PendingRegistrationItem>[];
    for (final it in items) {
      if (it.id == updated.id) {
        next.add(updated);
      } else {
        next.add(it);
      }
    }
    await save(next);
  }

  Future<void> removeById(String id) async {
    final items = await load();
    final next = items.where((e) => e.id != id).toList();
    await save(next);
  }
}
