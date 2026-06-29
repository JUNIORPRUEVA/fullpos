import 'package:flutter_test/flutter_test.dart';
import 'package:fullpos/core/security/authz/route_permissions.dart';
import 'package:fullpos/features/settings/data/user_model.dart';

void main() {
  group('RoutePermissions', () {
    test('configures admin override permissions for requested screens', () {
      final expected = <String, String>{
        '/products/movements': 'can_view_inventory_movements',
        '/products/history': 'can_view_inventory_movements',
        '/products/count': 'can_count_inventory',
        '/layaways': 'can_view_layaways',
        '/suppliers': 'can_view_suppliers',
        '/suppliers/new': 'can_register_suppliers',
      };

      for (final entry in expected.entries) {
        final permission = RoutePermissions.forPath(entry.key);
        expect(permission, isNotNull, reason: entry.key);
        expect(permission!.legacyKey, entry.value, reason: entry.key);
      }
    });
  });

  group('UserPermissions', () {
    test('round-trips requested screen permissions through JSON map', () {
      final permissions = UserPermissions.none().copyWith(
        canViewInventoryMovements: true,
        canCountInventory: true,
        canViewLayaways: true,
        canViewSuppliers: true,
        canRegisterSuppliers: true,
      );

      final restored = UserPermissions.fromMap(permissions.toMap());

      expect(restored.canViewInventoryMovements, isTrue);
      expect(restored.canCountInventory, isTrue);
      expect(restored.canViewLayaways, isTrue);
      expect(restored.canViewSuppliers, isTrue);
      expect(restored.canRegisterSuppliers, isTrue);
    });
  });
}
