# FULLPOS - Pruebas mínimas flujo "Iniciar operación"

## Objetivo
Validar separación CAJA (día) vs TURNO (cajero) con compatibilidad de datos existentes.

## Casos obligatorios

1. Login -> caja cerrada -> sin permiso de abrir caja
   - Entrar con usuario cajero sin `can_open_cashbox`.
   - Ir a `Iniciar operación`.
   - Resultado esperado: botón "Abrir caja" deshabilitado y mensaje "Requiere supervisor/admin".

2. Login -> caja cerrada -> con permiso
   - Entrar con admin/supervisor.
   - Abrir caja diaria con fondo inicial.
   - Abrir turno del usuario.
   - Resultado esperado: permite entrar a ventas.

3. Ventas sin turno
   - Con sesión iniciada pero sin turno abierto.
   - Intentar cobrar en ventas.
   - Resultado esperado: bloqueo + redirección a `Iniciar operación`.

4. Logout con turno abierto
   - Con turno abierto, intentar cerrar sesión desde sidebar o cuenta.
   - Resultado esperado: bloqueo con diálogo "Debes cerrar turno antes de salir" y acción "Ir a cierre".

5. Cerrar caja con turno abierto
   - Con caja diaria abierta y al menos un turno abierto.
   - Intentar "Cerrar caja del día".
   - Resultado esperado: bloqueo con mensaje de turnos abiertos.

6. Turno de ayer sin cerrar
   - Simular turno abierto con `business_date` anterior.
   - Entrar en `Iniciar operación`.
   - Resultado esperado: obliga a ir al cierre de turno antes de continuar.

7. Conflicto de dos cajeros
   - Con caja diaria abierta, cajero A abre turno.
   - Cajero B intenta abrir turno en misma caja.
   - Resultado esperado: bloqueo "Ya existe un turno abierto en esta caja".
