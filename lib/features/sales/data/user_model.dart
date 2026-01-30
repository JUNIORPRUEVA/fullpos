/// Modelo para usuarios del sistema
class UserModel {
  final int? id;
  final int companyId;
  final String username;
  final String? pin;
  final String role; // 'admin', 'cajero', 'supervisor'
  final bool isActive;
  final int createdAtMs;
  final int updatedAtMs;
  final int? deletedAtMs;

  UserModel({
    this.id,
    this.companyId = 1,
    required this.username,
    this.pin,
    this.role = 'admin',
    this.isActive = true,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.deletedAtMs,
  });

  DateTime get createdAt => DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  DateTime get updatedAt => DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  DateTime? get deletedAt => deletedAtMs != null
      ? DateTime.fromMillisecondsSinceEpoch(deletedAtMs!)
      : null;

  bool get isDeleted => deletedAtMs != null;

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] as int?,
      companyId: map['company_id'] as int? ?? 1,
      username: map['username'] as String,
      pin: map['pin'] as String?,
      role: map['role'] as String? ?? 'admin',
      isActive: (map['is_active'] as int) == 1,
      createdAtMs: map['created_at_ms'] as int,
      updatedAtMs: map['updated_at_ms'] as int,
      deletedAtMs: map['deleted_at_ms'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'username': username,
      'pin': pin,
      'role': role,
      'is_active': isActive ? 1 : 0,
      'company_id': companyId,
      'created_at_ms': createdAtMs,
      'updated_at_ms': updatedAtMs,
      'deleted_at_ms': deletedAtMs,
    };
  }

  UserModel copyWith({
    int? id,
    int? companyId,
    String? username,
    String? pin,
    String? role,
    bool? isActive,
    int? createdAtMs,
    int? updatedAtMs,
    int? deletedAtMs,
  }) {
    return UserModel(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      username: username ?? this.username,
      pin: pin ?? this.pin,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      deletedAtMs: deletedAtMs ?? this.deletedAtMs,
    );
  }
}

/// Roles disponibles
class UserRole {
  static const String admin = 'admin';
  static const String cajero = 'cajero';
  static const String supervisor = 'supervisor';

  static const List<String> all = [admin, cajero, supervisor];

  static String getDescription(String role) {
    switch (role) {
      case admin:
        return 'Administrador';
      case cajero:
        return 'Cajero';
      case supervisor:
        return 'Supervisor';
      default:
        return role;
    }
  }
}
