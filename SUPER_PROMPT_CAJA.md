# 🏦 SUPER PROMPT: AUDITORÍA COMPLETA DEL MÓDULO DE CAJA (CASH MODULE)

## 📋 PROPÓSITO

Este documento es una auditoría exhaustiva del **módulo de caja** de FULLPOS, diseñado para que puedas **replicar exactamente la misma arquitectura, lógica de negocio, flujo de datos y UI** en otra aplicación. Cubre desde las tablas de base de datos hasta los providers de estado, pasando por repositorios, servicios de operación, diálogos de apertura/cierre, impresión de tickets y manejo de movimientos manuales.

---

## 📁 ESTRUCTURA DE ARCHIVOS

```
lib/features/cash/
├── data/
│   ├── cash_model.dart                    # Modelo legacy (CashBoxModel)
│   ├── cash_movement_model.dart           # Modelo de movimientos manuales
│   ├── cash_session_model.dart            # Modelo de sesión/turno
│   ├── cash_summary_model.dart            # Modelo de resumen de cierre
│   ├── cashbox_daily_model.dart           # Modelo de caja diaria
│   ├── cash_repository.dart               # REPOSITORIO PRINCIPAL (1642 líneas)
│   ├── cash_box_repository.dart           # Repositorio legacy (abrir/cerrar caja simple)
│   ├── cash_accounting_service.dart       # Servicio de cálculos contables
│   ├── operation_flow_service.dart        # SERVICIO DE OPERACIÓN (1254 líneas)
│   ├── daily_cash_close_ticket_printer.dart  # Impresión de cierre de caja diaria
│   └── session_close_ticket_composer.dart    # Compositor de ticket de cierre de turno
├── providers/
│   └── cash_providers.dart                # Providers Riverpod
└── ui/
    ├── cash_gate_page.dart                # Página de apertura de caja (gate)
    ├── cash_open_dialog.dart              # Diálogo de apertura de caja
    ├── cash_close_dialog.dart             # Diálogo de cierre de turno (1264 líneas)
    ├── cash_box_page.dart                 # Página principal de gestión de caja
    ├── cash_history_page.dart             # Página de historial de cortes/movimientos
    ├── cash_movement_dialog.dart          # Diálogo de entrada/salida de efectivo
    ├── cash_panel_sheet.dart              # Panel lateral de resumen de turno activo
    ├── cashbox_open_dialog.dart           # Diálogo de apertura de caja diaria
    └── expenses_overview_page.dart        # Página de vista de gastos/movimientos
```

---

## 🗄️ TABLAS DE BASE DE DATOS

### 1. `cashbox_daily` — Caja diaria (una por día)

```sql
CREATE TABLE cashbox_daily (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    business_date   TEXT    NOT NULL UNIQUE,  -- 'yyyy-MM-dd'
    opened_at_ms    INTEGER NOT NULL,
    opened_by_user_id INTEGER NOT NULL,
    initial_amount  REAL    NOT NULL DEFAULT 0,
    current_amount  REAL    NOT NULL DEFAULT 0,
    status          TEXT    NOT NULL DEFAULT 'OPEN',  -- 'OPEN' | 'CLOSED'
    closed_at_ms    INTEGER,
    closed_by_user_id INTEGER,
    note            TEXT,
    created_at_ms   INTEGER,
    updated_at_ms   INTEGER
);
```

### 2. `cash_sessions` — Turnos de cajero (varios por caja diaria)

```sql
CREATE TABLE cash_sessions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    opened_by_user_id INTEGER NOT NULL,
    user_name       TEXT,
    opened_at_ms    INTEGER NOT NULL,
    initial_amount  REAL    NOT NULL DEFAULT 0,
    closing_amount  REAL,
    expected_amount REAL,
    difference      REAL,
    status          TEXT    NOT NULL DEFAULT 'OPEN',  -- 'OPEN' | 'CLOSED'
    closed_at_ms    INTEGER,
    closed_by_user_id INTEGER,
    cashbox_daily_id INTEGER,
    business_date   TEXT,
    requires_closure INTEGER DEFAULT 0,
    note            TEXT,
    created_at_ms   INTEGER,
    updated_at_ms   INTEGER,
    FOREIGN KEY (cashbox_daily_id) REFERENCES cashbox_daily(id)
);
```

### 3. `cash_movements` — Movimientos manuales (entradas/salidas)

```sql
CREATE TABLE cash_movements (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id      INTEGER NOT NULL,
    type            TEXT    NOT NULL,  -- 'IN' | 'OUT'
    amount          REAL    NOT NULL,
    reason          TEXT,
    movement_type   TEXT    DEFAULT 'expense',  -- 'expense' | 'owner_draw' | 'transfer'
    affects_profit  INTEGER DEFAULT 1,
    user_id         INTEGER,
    created_at_ms   INTEGER,
    updated_at_ms   INTEGER,
    FOREIGN KEY (session_id) REFERENCES cash_sessions(id)
);
```

### 4. `sales` — Ventas (referencia cruzada con sesiones)

```sql
-- Columnas relevantes para caja:
-- cash_session_id INTEGER  -> FK a cash_sessions.id
-- session_id      INTEGER  -> FK legacy a cash_sessions.id
-- total           REAL
-- payment_method  TEXT     -- 'cash' | 'card' | 'transfer' | 'credit'
-- payment_cash_amount     REAL
-- payment_card_amount     REAL
-- payment_transfer_amount REAL
-- kind            TEXT     -- 'invoice' | 'return'
-- status          TEXT     -- 'PAID' | 'PARTIAL_REFUND' | 'REFUNDED' | 'completed'
-- deleted_at_ms   INTEGER
```

---

## 🧠 ARQUITECTURA CONCEPTUAL

### Modelo de Dominio

```
Caja Diaria (cashbox_daily)
    │
    ├── business_date: "2024-01-15" (único por día)
    ├── initial_amount: fondo inicial
    ├── current_amount: fondo actual
    └── status: OPEN | CLOSED
         │
         └── Tiene N Turnos (cash_sessions)
              │
              ├── opened_by_user_id: cajero
              ├── initial_amount: fondo del turno
              ├── closing_amount: efectivo contado al cerrar
              ├── expected_amount: efectivo esperado
              ├── difference: diferencia
              └── status: OPEN | CLOSED
                   │
                   ├── Tiene M Ventas (sales) con cash_session_id
                   └── Tiene K Movimientos (cash_movements)
```

### Reglas de Negocio Clave

1. **Una caja diaria por día** (business_date UNIQUE). Si ya existe y está abierta, se reusa.
2. **Un turno por usuario** a la vez. No puede haber dos turnos abiertos del mismo usuario.
3. **Cada usuario es dueño exclusivo de su turno**. No se reasignan turnos entre usuarios.
4. **Un turno puede durar hasta 48 horas** antes de forzar cierre.
5. **Al cerrar el último turno de la caja diaria**, la caja se cierra automáticamente.
6. **El efectivo esperado** = fondo inicial + ventas efectivo - devoluciones efectivo + entradas manuales - salidas manuales.
7. **Las ventas a crédito/tarjeta/transferencia NO afectan el efectivo esperado** en gaveta.
8. **Los movimientos manuales** pueden ser: gasto (afecta ganancia), retiro de dueño (no afecta ganancia), transferencia (no afecta ganancia).

---

## 🔄 FLUJO DE OPERACIÓN COMPLETO

### 1. APERTURA DE CAJA (startActiveSession)

```
Usuario hace clic en "Abrir caja"
    │
    ├── CashGatePage._openCash()
    │   └── activeSessionController.startSession(openingAmount)
    │       └── OperationFlowService.startActiveSession(openingAmount, note)
    │           │
    │           ├── 1. Validar usuario actual (SessionManager.userId())
    │           ├── 2. Obtener/crear cashbox_daily para hoy
    │           │   ├── Si existe y está OPEN → reusar
    │           │   ├── Si existe y está CLOSED → reabrir (UPDATE status='OPEN')
    │           │   └── Si no existe → INSERT nueva cashbox_daily
    │           ├── 3. Verificar turnos abiertos del usuario
    │           │   ├── Si existe turno abierto → reusar (limpiar duplicados)
    │           │   └── Si no existe → INSERT nuevo cash_session
    │           ├── 4. Si el turno está en fecha anterior → mover a hoy
    │           └── 5. Retornar ActiveSession(userId, cashId, shiftId, ...)
    │
    └── Navegar a /sales (página de ventas POS)
```

### 2. CIERRE DE TURNO (closeActiveSession)

```
Usuario hace clic en "Cerrar turno"
    │
    ├── CashCloseDialog._closeCash()
    │   ├── 1. Validar autorización (AuthzService)
    │   ├── 2. Obtener closingAmount (efectivo contado)
    │   └── 3. OperationFlowService.closeActiveSession(sessionId, closingAmount, note)
    │       │
    │       ├── 1. Validar usuario actual
    │       ├── 2. Verificar que el turno existe y pertenece al usuario
    │       ├── 3. Construir CashSummaryModel (buildSummary)
    │       ├── 4. CashRepository.closeSession()
    │       │   ├── UPDATE cash_sessions SET status='CLOSED', closing_amount, expected_amount, difference, closed_at_ms
    │       │   └── Si es el último turno abierto → cerrar cashbox_daily
    │       └── 5. Imprimir ticket de cierre (SessionCloseTicketComposer)
    │
    └── Logout (opcional, según logoutAfterClose)
```

### 3. MOVIMIENTO MANUAL (addMovement)

```
Usuario hace clic en "Entrada" o "Retiro"
    │
    ├── CashMovementDialog._saveMovement()
    │   ├── 1. Validar autorización
    │   ├── 2. Validar monto > 0
    │   ├── 3. Si es retiro:
    │   │   ├── Confirmar con usuario
    │   │   └── Validar que haya efectivo suficiente (expectedCash >= amount)
    │   └── 4. CashRepository.addMovement(sessionId, type, amount, reason, movementType, affectsProfit)
    │       └── INSERT INTO cash_movements
    │
    └── Refrescar providers (cashSummaryProvider, cashMovementsProvider)
```

### 4. CARGA DEL ESTADO (loadGateState)

```
OperationFlowService.loadGateState()
    │
    ├── 1. Obtener businessDate = hoy (yyyy-MM-dd)
    ├── 2. Obtener userId del SessionManager
    ├── 3. Buscar cashbox_daily para hoy
    ├── 4. Buscar turnos abiertos del usuario
    ├── 5. Si hay turno abierto:
    │   ├── Verificar si está vinculado a una cashbox_daily
    │   ├── Si no → reparar (crear o reabrir cashbox_daily)
    │   └── Si está en fecha anterior → mover a hoy
    └── 6. Retornar OperationGateState con activeSession o null
```

---

## 📊 MODELOS DE DATOS

### CashboxDailyModel
```dart
class CashboxDailyModel {
  final int? id;
  final String businessDate;      // 'yyyy-MM-dd'
  final int openedAtMs;
  final int openedByUserId;
  final double initialAmount;
  final double currentAmount;
  final String status;            // 'OPEN' | 'CLOSED'
  final int? closedAtMs;
  final int? closedByUserId;
  final String? note;
  final int? createdAtMs;
  final int? updatedAtMs;

  bool get isOpen => status == 'OPEN';
  bool get isClosed => status == 'CLOSED';
}
```

### CashSessionModel
```dart
class CashSessionModel {
  final int? id;
  final int userId;               // opened_by_user_id
  final String userName;
  final int openedAtMs;
  final double openingAmount;     // initial_amount
  final double? closingAmount;
  final double? expectedAmount;
  final double? difference;
  final String status;            // 'OPEN' | 'CLOSED'
  final DateTime? closedAt;
  final int? closedByUserId;
  final int? cashboxDailyId;
  final String? businessDate;
  final String? note;

  bool get isOpen => status == CashSessionStatus.open;
  DateTime get openedAt => DateTime.fromMillisecondsSinceEpoch(openedAtMs);
}
```

### CashSummaryModel
```dart
class CashSummaryModel {
  final double openingAmount;
  final double totalSales;
  final double totalExpenses;
  final double totalWithdrawals;
  final double cashInManual;
  final double cashOutManual;
  final double creditAbonos;
  final double layawayAbonos;
  final double salesCashTotal;
  final double salesCardTotal;
  final double salesTransferTotal;
  final double salesCreditTotal;
  final double refundsCash;
  final double expectedCash;
  final int totalTickets;
  final int totalRefunds;

  double calculateDifference(double closingAmount) => closingAmount - expectedCash;
}
```

### CashMovementModel
```dart
class CashMovementModel {
  final int? id;
  final int sessionId;
  final String type;              // 'IN' | 'OUT'
  final double amount;
  final String reason;
  final String movementType;      // 'expense' | 'owner_draw' | 'transfer'
  final bool affectsProfit;
  final int userId;
  final DateTime createdAt;

  bool get isIn => type == CashMovementType.income;
  bool get isOut => type == CashMovementType.outcome;
}
```

### ActiveSession
```dart
class ActiveSession {
  final int userId;
  final int cashId;       // cashbox_daily.id
  final int shiftId;      // cash_sessions.id
  final int openedAt;
  final String status;
  final String userName;
  final String businessDate;

  bool get isOpen => status == CashSessionStatus.open;
}
```

### OperationGateState
```dart
class OperationGateState {
  final String businessDate;
  final CashboxDailyModel? cashboxToday;
  final CashSessionModel? userOpenShift;
  final CashSessionModel? staleOpenShift;  // turno > 48h
  final ActiveSession? activeSession;

  bool get hasCashboxTodayOpen => cashboxToday?.isOpen == true;
  bool get hasUserShiftOpen => userOpenShift?.isOpen == true;
  bool get hasStaleShift => staleOpenShift != null;
  bool get canOperate => activeSession?.isOpen == true;
}
```

---

## 🧮 CÁLCULOS CONTABLES (CashAccountingService)

### Fórmulas Clave

```
totalSold = salesCashTotal + salesCardTotal + salesTransferTotal + salesCreditTotal - refundsCash

expectedCash (gaveta) = openingAmount + cashSales - cashRefunds + cashInManual - cashOutManual

difference = countedCash - expectedCash

profit = totalSales - totalExpenses
```

### Clasificación de Movimientos

| movementType | affectsProfit | Clasificación |
|---|---|---|
| expense | true | Gasto (reduce ganancia) |
| owner_draw | false | Retiro de dueño |
| transfer | false | Transferencia |

---

## 🔐 SEGURIDAD Y VALIDACIONES

### 1. Validación de Usuario
```dart
static Future<int> _requireValidCurrentUserForCashbox() async {
  final userId = await SessionManager.userId();
  if (userId == null) {
    await SessionManager.clearInvalidSession(reason: 'cashbox_user_missing');
    throw Exception('Tu sesión anterior no coincide...');
  }
  final user = await UsersRepository.getById(userId, companyId: ...);
  if (user == null || !user.isActiveUser || user.deletedAtMs != null) {
    await SessionManager.clearInvalidSession(reason: 'cashbox_user_invalid');
    throw Exception('Tu sesión anterior no coincide...');
  }
  return userId;
}
```

### 2. Ownership de Turno
```dart
// FULLPOS SEGURIDAD: verificar ownership antes de cerrar
if (session.userId != userId) {
  throw AppException(
    type: AppErrorType.forbidden,
    code: 'cash_close_owner_mismatch',
    messageUser: 'Este turno pertenece a otro usuario...',
  );
}
```

### 3. Autorización por Permisos
```dart
// Verificar si el usuario puede abrir caja
final canOpenCashbox = perms.canOpenCashbox || perms.canOpenCash;

// Verificar si puede cerrar turno
final ok = await AuthzService.runGuardedCurrent<bool>(
  context,
  authz_perm.Permission.action(AppActions.closeSession),
  () async => true,
  reason: 'Cerrar sesión',
);
```

### 4. Timeout en Apertura
```dart
.timeout(
  const Duration(seconds: 12),
  onTimeout: () => throw TimeoutException('La apertura de caja tardó demasiado.'),
);
```

---

## 🧠 AUTO-REPARACIÓN (Self-Healing)

El sistema tiene mecanismos de auto-reparación para casos borde:

### 1. Turno huérfano sin cashbox_daily
```dart
// Si un turno existe pero no tiene cashbox_daily_id vinculado,
// se crea o reabre la caja diaria correspondiente
final repairedCashbox = await _repairCashboxForOpenShift(txn, shift: shift, ...);
```

### 2. Turno en fecha anterior
```dart
// Si el usuario tiene un turno abierto de ayer, se mueve a hoy
final movedShift = await _moveOpenShiftToBusinessDate(txn, shift: shift, ...);
```

### 3. Duplicados de turno
```dart
// Si hay múltiples turnos abiertos del mismo usuario, se cierran los duplicados
await _retireDuplicateOpenShifts(txn, rows: rows, keepShiftId: shiftId, ...);
```

### 4. Caja diaria cerrada con turnos abiertos
```dart
// Si la cashbox_daily está CLOSED pero hay turnos abiertos, se reabre
await txn.update(DbTables.cashboxDaily, {'status': 'OPEN', ...}, ...);
```

---

## 🔄 PROVIDERS RIVERPOD

```dart
// Provider principal: sesión activa
final activeSessionProvider = FutureProvider<ActiveSession?>((ref) async {
  return OperationFlowService.loadActiveSession();
});

// Provider de verificación
final isSessionActiveProvider = FutureProvider<bool>((ref) async {
  return (await OperationFlowService.loadActiveSession()) != null;
});

// StateNotifier Controller
final activeSessionControllerProvider =
    StateNotifierProvider<ActiveSessionController, AsyncValue<ActiveSession?>>(
  (ref) => ActiveSessionController(ref),
);

// Provider de resumen
final cashSummaryProvider = FutureProvider<CashSummaryModel?>((ref) async {
  final activeSession = await ref.watch(activeSessionProvider.future);
  if (activeSession == null) return null;
  return CashRepository.buildSummary(sessionId: activeSession.shiftId);
});

// Provider de movimientos
final cashMovementsProvider = FutureProvider<List<CashMovementModel>>((ref) async {
  final activeSession = await ref.watch(activeSessionProvider.future);
  if (activeSession == null) return [];
  return CashRepository.listMovements(sessionId: activeSession.shiftId);
});

// Provider de historial
final closedSessionsProvider = FutureProvider<List<CashSessionModel>>((ref) async {
  return await CashRepository.listClosedSessions(limit: 50);
});
```

### ActiveSessionController (StateNotifier)

```dart
class ActiveSessionController extends StateNotifier<AsyncValue<ActiveSession?>> {
  // Métodos públicos:
  Future<void> refresh()                    // Recargar todo
  Future<ActiveSession> startSession(...)   // Abrir caja + turno
  Future<void> closeSession(...)            // Cerrar turno
  Future<int> addMovement(...)              // Agregar movimiento manual
  Future<CashSummaryModel?> getSummary()    // Obtener resumen
}
```

---

## 🖥️ UI: PÁGINAS Y DIÁLOGOS

### 1. CashGatePage — Página de apertura (gate)

**Propósito:** Pantalla inicial cuando no hay caja abierta. Solicita el fondo inicial.

**Características:**
- Diseño centrado con panel blanco y sombras
- Campo de monto con formato RD$ y formateador AccountingAmountFormatter
- Auto-focus en el campo de monto
- Validación: monto no negativo
- Botón "Abrir caja" con estado de carga
- Timeout de 12 segundos
- Navega a /sales al abrir exitosamente

### 2. CashOpenDialog — Diálogo de apertura

**Propósito:** Diálogo modal para abrir caja desde cualquier parte de la app.

**Características:**
- Diálogo con teclado (DialogKeyboardShortcuts)
- Validación de autorización (requireAuthorizationIfNeeded)
- SnackBar de confirmación
- Manejo de errores con ErrorHandler

### 3. CashCloseDialog — Diálogo de cierre (1264 líneas)

**Propósito:** Diálogo completo para cerrar el turno con resumen.

**Características:**
- Muestra resumen: total vendido, efectivo esperado, tickets
- Carga asíncrona de: summary, session, refunds, movements, categorySummary
- Auto-close mode (cierre automático sin UI)
- Validación de ownership del turno
- Autorización con AuthzService
- Impresión de ticket de cierre (SessionCloseTicketComposer)
- Opción de logout después del cierre
- Manejo de errores de impresión (no bloqueante)
- Diseño responsive con animaciones

### 4. CashBoxPage — Página principal de caja

**Propósito:** Gestión de caja con estado actual e historial.

**Características:**
- Muestra estado: cerrado (con botón abrir) o abierto (con info de sesión)
- Historial de cortes en lista
- Botón "Entrar al POS" si hay sesión activa
- Panel de sesión (CashPanelSheet)

### 5. CashHistoryPage — Historial de cortes y movimientos

**Propósito:** Visualización de sesiones cerradas y movimientos.

**Características:**
- Tabs: Sesiones | Movimientos
- Filtro por rango de fechas
- Búsqueda por cajero, motivo, monto
- Panel lateral de detalle (slide desde derecha)
- Resumen de entradas/salidas/balance
- Re-impresión de tickets de cierre

### 6. CashMovementDialog — Entrada/Salida de efectivo

**Propósito:** Registrar movimientos manuales de caja.

**Características:**
- Tipo: IN (entrada) o OUT (salida)
- Para OUT: selector de tipo contable (gasto, retiro dueño, transferencia)
- Validación de monto > 0
- Para retiros: confirmación y verificación de efectivo suficiente
- Autorización con requireAuthorizationIfNeeded

### 7. CashPanelSheet — Panel lateral de resumen

**Propósito:** Dashboard rápido del turno activo.

**Características:**
- Total vendido (grande)
- Métricas: base inicial, efectivo esperado, tickets
- Composición del corte (desglose por método de pago)
- Historial de movimientos
- Botones: Ver corte actual, Cerrar turno
- Timer de 30s para mantener hora viva
- Diseño responsive (compact/ultra-compact)

### 8. CashboxOpenDialog — Diálogo de apertura de caja diaria

**Propósito:** Diálogo simple para abrir caja con fondo inicial.

**Características:**
- Validación de permisos (canOpenCashbox)
- Mensaje de denegado si no tiene permiso
- Diseño con branding (FullposBrandTheme)

### 9. ExpensesOverviewPage — Vista de gastos/movimientos

**Propósito:** Página dedicada a ver todos los movimientos (entradas/salidas).

**Características:**
- Filtros: rango de fechas, tipo (todos/entradas/salidas)
- Búsqueda por texto
- Resumen: total entradas, salidas, neto
- Lista con columnas: tipo, motivo, fecha, sesión, usuario, monto
- Bottom sheet de detalle al seleccionar

---

## 🖨️ IMPRESIÓN DE TICKETS

### SessionCloseTicketComposer

Genera las líneas del ticket de cierre de turno:

```
[NOMBRE EMPRESA]
RNC: xxx
TEL: xxx

====== CORTE DE TURNO ======
CAJERO: Juan Perez
SESION: #123
APERTURA: 15/01/2024 08:00 AM
CIERRE:  15/01/2024 06:00 PM
DURACION: 10h 00m
FECHA OPER.: 2024-01-15

..... RESUMEN DE VENTAS .....
TICKETS: 45
TOTAL VENDIDO: RD$ 45,000.00
EFECTIVO:      RD$ 30,000.00
TARJETA:       RD$ 10,000.00
TRANSFERENCIA: RD$  3,000.00
CREDITO:       RD$  2,000.00

..... CUADRE DE CAJA .....
BASE CAJA DIARIA: RD$ 5,000.00
BASE DE SESION:   RD$ 5,000.00
EFECTIVO VENTAS:  RD$ 30,000.00
ENTRADAS MANUALES: RD$ 500.00
SALIDAS DE CAJA:   RD$ 200.00

===== TOTALES DEL CIERRE =====
TOTAL VENDIDO: RD$ 45,000.00
EFECTIVO ESPERADO: RD$ 35,300.00
EFECTIVO CONTADO:  RD$ 35,300.00
DIFERENCIA: RD$ 0.00
```

### DailyCashCloseTicketPrinter

Genera las líneas del ticket de cierre de caja diaria (similar pero a nivel de caja, no de turno).

---

## 📝 QUERIES SQL CRÍTICOS

### Build Summary (resumen de sesión)
```sql
-- Ventas en efectivo
SELECT COALESCE(SUM(total), 0) as total
FROM sales
WHERE (cash_session_id = ? OR session_id = ?)
  AND kind = 'invoice'
  AND status IN ('completed', 'PAID', 'PARTIAL_REFUND', 'REFUNDED')
  AND deleted_at_ms IS NULL
  AND payment_method IN ('cash', 'efectivo')

-- Devoluciones en efectivo
SELECT COALESCE(SUM(ABS(total)), 0) as total
FROM sales
WHERE (cash_session_id = ? OR session_id = ?)
  AND kind = 'return'
  AND deleted_at_ms IS NULL

-- Movimientos manuales IN
SELECT COALESCE(SUM(amount), 0) as total
FROM cash_movements
WHERE session_id = ? AND type = 'IN'

-- Gastos (OUT + expense + affectsProfit)
SELECT COALESCE(SUM(amount), 0) as total
FROM cash_movements
WHERE session_id = ?
  AND type = 'OUT'
  AND movement_type = 'expense'
  AND affects_profit = 1

-- Retiros (OUT + NOT expense)
SELECT COALESCE(SUM(amount), 0) as total
FROM cash_movements
WHERE session_id = ?
  AND type = 'OUT'
  AND (movement_type != 'expense' OR affects_profit = 0)
```

### Verificar si hay otros turnos abiertos en la misma caja
```sql
SELECT id FROM cash_sessions
WHERE status = 'OPEN'
  AND closed_at_ms IS NULL
  AND id <> ?
  AND (
    (? IS NOT NULL AND cashbox_daily_id = ?)
    OR (? IS NOT NULL AND cashbox_daily_id IS NULL AND business_date = ?)
  )
LIMIT 1
```

### Resumen por categoría
```sql
SELECT
  COALESCE(c.name, 'Sin categoria') as category,
  COALESCE(SUM(si.total_line), 0) as sales_total,
  COALESCE(SUM(CASE WHEN s.payment_method IN ('cash','efectivo') THEN si.total_line ELSE 0 END), 0) as cash_sales_total,
  COALESCE(SUM(CASE WHEN s.payment_method IN ('card','tarjeta') THEN si.total_line ELSE 0 END), 0) as card_sales_total,
  COALESCE(SUM(CASE WHEN s.payment_method IN ('transfer','transferencia') THEN si.total_line ELSE 0 END), 0) as transfer_sales_total,
  COALESCE(SUM(CASE WHEN s.payment_method IN ('credit','credito') THEN si.total_line ELSE 0 END), 0) as credit_sales_total,
  0 as refund_total,
  COALESCE(SUM(si.qty), 0) as items_sold,
  0 as items_refunded
FROM sale_items si
INNER JOIN sales s ON si.sale_id = s.id
LEFT JOIN products p ON (si.product_id = p.id) OR (...)
LEFT JOIN categories c ON p.category_id = c.id
WHERE (s.cash_session_id = ? OR s.session_id = ?)
  AND s.kind IN ('invoice', 'sale')
  AND s.status IN ('completed', 'PAID', 'PARTIAL_REFUND', 'REFUNDED')
  AND s.deleted_at_ms IS NULL
GROUP BY category
```

---

## ⚠️ ERRORES Y EXCEPCIONES

| Código | Tipo | Mensaje Usuario |
|---|---|---|
| `cash_close_user_missing` | unauthorized | No se pudo confirmar el usuario actual. |
| `cash_close_shift_missing` | notFound | No encontramos un turno abierto para cerrar. |
| `cash_close_owner_mismatch` | forbidden | Este turno pertenece a otro usuario. |
| `cashbox_user_missing` | unauthorized | Tu sesión anterior no coincide... |
| `cashbox_user_invalid` | unauthorized | Tu sesión anterior no coincide... |
| `cash_movement_user_missing` | - | Tu sesión anterior no coincide... |
| `cash_movement_user_invalid` | - | Tu sesión anterior no coincide... |

---

## 📋 CHECKLIST PARA REPLICAR EL MÓDULO

### Fase 1: Base de Datos
- [ ] Crear tabla `cashbox_daily`
- [ ] Crear tabla `cash_sessions`
- [ ] Crear tabla `cash_movements`
- [ ] Asegurar que `sales` tenga `cash_session_id` y `session_id`

### Fase 2: Modelos
- [ ] `CashboxDailyModel` (fromMap, toMap, copyWith)
- [ ] `CashSessionModel` (fromMap, toMap, copyWith)
- [ ] `CashSummaryModel`
- [ ] `CashMovementModel`
- [ ] `ActiveSession`
- [ ] `OperationGateState`
- [ ] `CashAccountingTotals`, `CashClosingSummary`
- [ ] `CategoryCashSummary`, `SoldProductCashSummary`, `RefundItemByCategory`, `TransferItemByCategory`

### Fase 3: Servicios
- [ ] `CashAccountingService` (cálculos contables)
- [ ] `CashRepository` (queries SQL, CRUD)
- [ ] `OperationFlowService` (lógica de negocio de apertura/cierre)
- [ ] `SessionCloseTicketComposer` (generación de ticket)
- [ ] `DailyCashCloseTicketPrinter` (impresión de cierre diario)

### Fase 4: Estado (Providers)
- [ ] `activeSessionProvider`
- [ ] `isSessionActiveProvider`
- [ ] `activeSessionControllerProvider` (StateNotifier)
- [ ] `cashSummaryProvider`
- [ ] `cashMovementsProvider`
- [ ] `closedSessionsProvider`

### Fase 5: UI
- [ ] `CashGatePage` (página de apertura)
- [ ] `CashOpenDialog` (diálogo de apertura)
- [ ] `CashCloseDialog` (diálogo de cierre)
- [ ] `CashBoxPage` (página principal)
- [ ] `CashHistoryPage` (historial)
- [ ] `CashMovementDialog` (movimientos manuales)
- [ ] `CashPanelSheet` (panel lateral)
- [ ] `CashboxOpenDialog` (apertura de caja diaria)
- [ ] `ExpensesOverviewPage` (vista de gastos)

### Fase 6: Seguridad
- [ ] Validación de usuario activo en cada operación
- [ ] Ownership check (turno pertenece al usuario)
- [ ] Autorización por permisos (canOpenCashbox, closeSession)
- [ ] Timeout en operaciones críticas
- [ ] Limpieza de sesión inválida

### Fase 7: Auto-reparación
- [ ] Reparar turno huérfano sin cashbox_daily
- [ ] Mover turno de fecha anterior a hoy
- [ ] Cerrar turnos duplicados
- [ ] Reabrir cashbox_daily cerrada con turnos activos

---

## 🎯 RESUMEN DE ARCHIVOS Y LÍNEAS

| Archivo | Líneas | Propósito |
|---|---|---|
| `cash_repository.dart` | 1642 | Queries SQL, CRUD de sesiones, movimientos, resúmenes |
| `operation_flow_service.dart` | 1254 | Lógica de negocio: apertura, cierre, auto-reparación |
| `cash_close_dialog.dart` | 1264 | UI de cierre de turno con resumen e impresión |
| `cash_panel_sheet.dart` | 1248 | Panel lateral de dashboard del turno activo |
| `cash_history_page.dart` | 2125 | Historial de cortes y movimientos con búsqueda |
| `cash_movement_dialog.dart` | 507 | Diálogo de entrada/salida de efectivo |
| `cash_gate_page.dart` | 451 | Página de apertura de caja |
| `cash_box_page.dart` | 375 | Página principal de gestión de caja |
| `cashbox_open_dialog.dart` | 290 | Diálogo de apertura de caja diaria |
| `expenses_overview_page.dart` | 1815 | Vista de gastos/movimientos con filtros |
| `cash_open_dialog.dart` | 270 | Diálogo de apertura de caja |
| **TOTAL** | **~12,000** | **Módulo completo de caja** |

---

## 🚀 CÓMO USAR ESTE SUPER PROMPT

### Opción 1: Replicar en otra app Flutter
1. Copia la estructura de carpetas `lib/features/cash/`
2. Implementa las tablas SQL en tu `DatabaseManager`
3. Crea los modelos (fromMap/toMap)
4. Implementa `CashRepository` con las queries SQL
5. Implementa `OperationFlowService` con la lógica de negocio
6. Crea los providers Riverpod
7. Implementa las UI pages/dialogs
8. Conecta las rutas en tu router (GoRouter)

### Opción 2: Usar como prompt para IA
Copia este documento completo y pídele a una IA que genere el código para tu stack específico (Flutter, React Native, etc.)

### Opción 3: Auditoría de código existente
Usa este documento como checklist para verificar que tu implementación de caja cubre todos los casos borde, seguridad y auto-reparación.

---

## 🔗 DEPENDENCIAS EXTERNAS

| Dependencia | Uso |
|---|---|
| `flutter_riverpod` | State management |
| `go_router` | Navegación |
| `sqflite` | Base de datos SQLite |
| `intl` | Formateo de fechas/monedas |
| `AccountingAmountFormatter` | Formateo de montos contables |
| `CurrencyDisplay` | Display de moneda local |
| `ErrorHandler` | Manejo centralizado de errores |
| `SessionManager` | Gestión de sesión de usuario |
| `AuthzService` | Autorización y permisos |
| `AppActions` | Constantes de acciones auditables |
| `UnifiedTicketPrinter` | Impresión de tickets |
| `DialogKeyboardShortcuts` | Atajos de teclado en diálogos |
| `DbHardening` | Operaciones seguras en DB |
| `ColorUtils` | Utilidades de color |
| `AppStatusTheme` | Tema de estados (success/warning/error) |

---

## 📌 NOTAS IMPORTANTES

1. **Legacy vs Moderno**: El sistema tiene dos capas: una legacy (`cash_box_repository.dart`, `cash_model.dart`) y la moderna (`operation_flow_service.dart`, `cash_session_model.dart`). La moderna es la que debes replicar.

2. **Dos IDs de sesión en ventas**: Las ventas tienen `cash_session_id` (nuevo) y `session_id` (legacy). Siempre consultar ambos con OR.

3. **Auto-reparación**: El sistema está diseñado para ser tolerante a fallos. Si un turno queda huérfano, se repara automáticamente al cargar el estado.

4. **Multi-tenant**: Toda la lógica asume multi-empresa. Las tablas de usuarios y permisos incluyen `company_id`.

5. **Impresión no bloqueante**: Si la impresión falla al cerrar, el cierre igual se completa y se muestra un mensaje al usuario.

---

*Documento generado el 15/07/2026 - Auditoría completa del módulo de caja de FULLPOS*
