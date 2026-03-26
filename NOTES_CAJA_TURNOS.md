# Arquitectura final: Sesión única de caja (FULLPOS)

## Flujo final
- **Login**: el usuario entra y el sistema valida si existe una `ActiveSession`.
- **Sin sesión activa**: se muestra un único modal para abrir caja e iniciar la sesión operativa.
- **Con sesión activa**: el usuario entra directo al POS.
- **Cierre**: `CashCloseDialog` ejecuta `OperationFlowService.closeActiveSession()`, imprime el comprobante y fuerza logout.

## Principios obligatorios
- Solo existe una sesión operativa visible para la UI.
- No existe pantalla intermedia de "Iniciar operación".
- No existe acción visible para abrir turno o cerrar caja por separado.
- El flujo completo es: `LOGIN → OPEN CASH → WORK → CLOSE SESSION → LOGOUT`.

## Implementación técnica
- `ActiveSession` es la fuente única de estado operativo.
- `cashbox_daily` y `cash_sessions` se conservan solo como persistencia interna para compatibilidad de ventas y reportes.
- El cierre ocurre dentro de una sola operación transaccional: cierre de sesión, cierre de caja y generación del resumen.
- La base de datos impide sesiones abiertas duplicadas por usuario o por caja.

## Fórmula oficial de efectivo esperado
Implementada en `CashRepository._buildSummaryUnsafe(sessionId)`:

```text
efectivo_esperado = apertura + ventas_efectivo + entradas - salidas - devoluciones_efectivo
```

Notas:
- `apertura` = fondo inicial de la sesión.
- Las devoluciones de efectivo se restan por su valor absoluto.

## Checklist de pruebas manuales obligatorias
1. Login sin sesión activa -> modal obligatorio de apertura.
2. Login con sesión activa restaurable -> entrada directa al POS.
3. Intentar vender sin sesión -> bloqueo y solicitud de apertura.
4. Cerrar sesión -> validar en DB: sesión `CLOSED`, caja `CLOSED`, cierre impreso y logout.
5. Re-login después del cierre -> obliga a abrir caja nuevamente.
6. Reinicio o caída con sesión abierta -> la sesión se restaura al volver a entrar.
7. Intento de segunda sesión concurrente -> bloqueo por integridad.

## Cómo probar rápidamente
- Ejecutar tests automáticos:
  - `flutter test test/cash_shift_hardening_test.dart`
  - `flutter test`
- Validar el flujo real en Windows:
  - `LOGIN -> OPEN CASH -> WORK -> CLOSE SESSION -> LOGOUT`
