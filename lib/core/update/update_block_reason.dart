/// Códigos de razón por la que una actualización no puede proceder.
enum BlockReasonCode {
  pendingPayment,
  activeSale,
  cashClosingInProgress,
  databaseWriteActive,
  activePrinting,
  importExportRunning,
  backupRunning,
  activeSync,
  unsavedChanges,
  criticalDialogOpen,
  openCashShiftRequiresClose,
  unknownBlocker,
}

/// Acción de navegación sugerida para resolver un bloqueo.
enum BlockNavigationAction {
  /// Ir a la pantalla de ventas (restaurar venta activa).
  openSales,

  /// Ir a la pantalla de cobro/pago.
  openPayment,

  /// Ir a la pantalla de cierre de caja.
  openCashClose,

  /// Ir a la pantalla de estado de impresión.
  openPrintStatus,

  /// Ir a la pantalla de importación/exportación.
  openImportExport,

  /// Ir a la pantalla de estado de sync.
  openSyncStatus,

  /// Ir a la pantalla de estado de backup.
  openBackupStatus,

  /// Ir a la pantalla de cierre de turno.
  openShiftClose,

  /// Ir al formulario con cambios sin guardar.
  openUnsavedForm,

  /// Cerrar/finalizar el diálogo crítico actual.
  closeCriticalDialog,

  /// Sin acción específica.
  none,
}

/// Razón estructurada por la que una actualización está bloqueada.
///
/// Incluye un [code] para identificar el tipo de bloqueo,
/// un [title] y [message] para mostrar al usuario,
/// y un [action] opcional para navegar a la pantalla donde
/// el usuario puede resolver el problema.
class UpdateBlockReason {
  const UpdateBlockReason({
    required this.code,
    required this.title,
    required this.message,
    this.action = BlockNavigationAction.none,
  });

  final BlockReasonCode code;
  final String title;
  final String message;
  final BlockNavigationAction action;

  // -- Razones predefinidas --

  static const pendingPayment = UpdateBlockReason(
    code: BlockReasonCode.pendingPayment,
    title: 'Cobro pendiente',
    message:
        'Hay un cobro pendiente. Finaliza o cancela el cobro antes de actualizar FullPOS.',
    action: BlockNavigationAction.openPayment,
  );

  static const activeSale = UpdateBlockReason(
    code: BlockReasonCode.activeSale,
    title: 'Venta abierta',
    message:
        'Hay una venta abierta. Debes completarla, guardarla o cancelarla antes de actualizar FullPOS.',
    action: BlockNavigationAction.openSales,
  );

  static const cashClosingInProgress = UpdateBlockReason(
    code: BlockReasonCode.cashClosingInProgress,
    title: 'Cierre de caja en proceso',
    message:
        'El cierre de caja está en proceso. Espera que termine antes de actualizar.',
    action: BlockNavigationAction.openCashClose,
  );

  static const databaseWriteActive = UpdateBlockReason(
    code: BlockReasonCode.databaseWriteActive,
    title: 'Escritura en base de datos',
    message:
        'Hay una operación de escritura en la base de datos. Espera que termine antes de actualizar.',
    action: BlockNavigationAction.none,
  );

  static const activePrinting = UpdateBlockReason(
    code: BlockReasonCode.activePrinting,
    title: 'Impresión en proceso',
    message:
        'Hay una impresión en proceso. Espera que termine la impresión y vuelve a intentarlo.',
    action: BlockNavigationAction.openPrintStatus,
  );

  static const importExportRunning = UpdateBlockReason(
    code: BlockReasonCode.importExportRunning,
    title: 'Importación o exportación en proceso',
    message:
        'Hay una importación o exportación en proceso. Espera que termine antes de actualizar.',
    action: BlockNavigationAction.openImportExport,
  );

  static const backupRunning = UpdateBlockReason(
    code: BlockReasonCode.backupRunning,
    title: 'Respaldo en proceso',
    message:
        'Hay un respaldo de datos en proceso. Espera que termine antes de actualizar.',
    action: BlockNavigationAction.openBackupStatus,
  );

  static const activeSync = UpdateBlockReason(
    code: BlockReasonCode.activeSync,
    title: 'Sincronización en proceso',
    message:
        'Hay una sincronización en proceso. Espera que termine antes de actualizar.',
    action: BlockNavigationAction.openSyncStatus,
  );

  static const unsavedChanges = UpdateBlockReason(
    code: BlockReasonCode.unsavedChanges,
    title: 'Cambios sin guardar',
    message:
        'Hay cambios sin guardar. Guarda o descarta los cambios antes de actualizar.',
    action: BlockNavigationAction.openUnsavedForm,
  );

  static const criticalDialogOpen = UpdateBlockReason(
    code: BlockReasonCode.criticalDialogOpen,
    title: 'Diálogo crítico abierto',
    message:
        'Hay un diálogo crítico abierto. Ciérralo antes de actualizar FullPOS.',
    action: BlockNavigationAction.closeCriticalDialog,
  );

  static const openCashShiftRequiresClose = UpdateBlockReason(
    code: BlockReasonCode.openCashShiftRequiresClose,
    title: 'Turno abierto',
    message: 'Debes cerrar el turno antes de actualizar FullPOS.',
    action: BlockNavigationAction.openShiftClose,
  );

  static const unknownBlocker = UpdateBlockReason(
    code: BlockReasonCode.unknownBlocker,
    title: 'Proceso pendiente',
    message:
        'Hay un proceso abierto que debe finalizarse antes de instalar la actualización.',
    action: BlockNavigationAction.none,
  );

  /// Prioridad de resolución (menor número = mayor prioridad).
  int get priority => switch (code) {
    BlockReasonCode.pendingPayment => 0,
    BlockReasonCode.activeSale => 1,
    BlockReasonCode.cashClosingInProgress => 2,
    BlockReasonCode.databaseWriteActive => 3,
    BlockReasonCode.activePrinting => 4,
    BlockReasonCode.importExportRunning => 5,
    BlockReasonCode.backupRunning => 6,
    BlockReasonCode.activeSync => 7,
    BlockReasonCode.unsavedChanges => 8,
    BlockReasonCode.criticalDialogOpen => 9,
    BlockReasonCode.openCashShiftRequiresClose => 10,
    BlockReasonCode.unknownBlocker => 11,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateBlockReason &&
          runtimeType == other.runtimeType &&
          code == other.code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'UpdateBlockReason($code): $title';
}
