# Auditoría y Hardening: Caja y Turnos (FULLPOS)

## Flujo actual detectado
- **Apertura de caja diaria**: `OperationFlowService.openDailyCashboxToday()` sobre `cashbox_daily`.
- **Apertura de turno**: `OperationFlowService.openShiftForCurrentUser()` crea registro en `cash_sessions` ligado a `cashbox_daily_id` + `business_date`.
- **Bloqueo de ventas sin turno**: `router.dart` (`/sales` redirige a `/operation-start`) + validación en `sales_page.dart`.
- **Cierre de turno**: `CashCloseDialog` -> `cashSessionControllerProvider.closeSession()` -> `CashRepository.closeSession()`.
- **Cierre de caja diaria**: `OperationFlowService.closeDailyCashboxToday()`.
- **Logout con turno abierto**: `LogoutFlowService.requestLogout()` con modal bloqueante y auditoría para salida sin cerrar.

## Problemas encontrados en auditoría
- El cierre de turno no validaba de forma estricta (atómica) el estado real OPEN + ownership antes de actualizar.
- El cierre de caja no era transaccional; podía fallar en escenarios límite de concurrencia.
- Mensaje de bloqueo al cerrar caja no detallaba qué turnos abiertos impedían el cierre.
- Claridad UX turno/caja podía mejorar con ayudas explícitas para reducir errores operativos.

## Cambios realizados (hardening)
- **`CashRepository.closeSession()`**
  - Validación transaccional obligatoria: turno existe, está `OPEN`, no está ya cerrado.
  - Validación de pertenencia por cajero (`expectedUserId` o usuario en sesión).
  - Validación opcional de caja diaria (`expectedCashboxDailyId`).
  - Update condicional (`WHERE status='OPEN' AND closed_at_ms IS NULL`) + verificación de filas afectadas.
- **`OperationFlowService.closeDailyCashboxToday()`**
  - Cierre movido a transacción.
  - Revalidación de turnos abiertos dentro de la transacción.
  - Mensaje de bloqueo con detalle de turnos abiertos (`id`/cajero).
  - Verificación de filas afectadas al cerrar caja.
- **`OperationFlowService.openShiftForCurrentUser()`**
  - Apertura de turno dentro de transacción para minimizar condiciones de carrera.
  - Validación atómica: no turno abierto del usuario y no turno abierto en la caja diaria.
- **UI de Caja (`cash_box_page.dart`)**
  - Etiquetas y tooltips explícitos para separar:
    - **Turno (corte cajero)**
    - **Caja (fin del día)**
  - Formato de fecha/hora del historial y apertura en 12h (`hh:mm a`).

## Fórmula oficial de efectivo esperado
Implementada en `CashRepository._buildSummaryUnsafe(sessionId)`:

```text
efectivo_esperado = apertura + ventas_efectivo + entradas - salidas - devoluciones_efectivo
```

Notas:
- `apertura` = fondo del turno; para el primer turno del día abierto en 0 y ligado a caja diaria, hereda `cashbox_daily.initial_amount`.
- Las devoluciones de efectivo se restan por su valor absoluto.

## Checklist de pruebas manuales obligatorias
1. Caja cerrada + cajero sin permiso -> no puede operar.
2. Caja cerrada + admin -> abre caja -> abre turno -> opera.
3. Intentar vender sin turno -> bloquea y redirige.
4. Cerrar turno -> validar en DB: `status=CLOSED`, `closed_at_ms`, `expected_cash`, `closing_amount`, `difference`.
5. Logout con turno abierto -> modal -> "Cerrar turno y salir" -> logout solo si cierre exitoso.
6. "Salir sin cerrar turno" (admin/supervisor) -> motivo obligatorio + auditoría registrada.
7. Intentar cerrar caja con turno abierto -> bloquea con detalle de turnos abiertos.
8. Cerrar caja sin turnos abiertos -> cierre exitoso con `closed_at_ms` y estado `CLOSED`.
9. Turno abierto de businessDate anterior -> bloquea operación y obliga cierre.

## Cómo probar rápidamente
- Ejecutar tests automáticos (incluye hardening nuevo):
  - `flutter test test/cash_shift_hardening_test.dart`
  - `flutter test`
- Ejecutar FULLPOS en Windows y validar flujo operativo real:
  - Login -> `Iniciar operación` -> caja/turno -> ventas -> corte -> cierre de caja.
