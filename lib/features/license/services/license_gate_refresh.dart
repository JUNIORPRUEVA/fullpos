import 'package:flutter/foundation.dart';

/// Notificador global para invalidar el gate de licencia del router.
///
/// Se mantiene en un archivo separado para evitar imports circulares entre
/// `router.dart` y pantallas/servicios de licencias.
final ValueNotifier<int> licenseGateRefreshToken = ValueNotifier<int>(0);

void bumpLicenseGateRefresh() {
  licenseGateRefreshToken.value++;
}
