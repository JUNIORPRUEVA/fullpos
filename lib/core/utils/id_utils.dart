import 'dart:math';

class IdUtils {
  IdUtils._();

  static String uuidV4() {
    final rand = Random.secure();
    String hex(int length) =>
        List.generate(length, (_) => rand.nextInt(16).toRadixString(16)).join();

    return '${hex(8)}-${hex(4)}-4${hex(3)}-${_variant(rand)}${hex(3)}-${hex(12)}';
  }

  static String _variant(Random rand) {
    final v = rand.nextInt(4) + 8; // 8,9,a,b
    return v.toRadixString(16);
  }
}
