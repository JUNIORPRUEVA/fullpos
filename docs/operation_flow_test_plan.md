# FULLPOS - Pruebas mínimas de sesión única

## Objetivo
Validar el flujo único de sesión operativa sin pasos intermedios ni acciones separadas.

## Casos obligatorios

1. Login -> sin sesión activa -> sin permiso de apertura
   - Entrar con usuario cajero sin permiso para iniciar sesión.
   - Resultado esperado: se muestra el modal de apertura y la confirmación queda bloqueada.

2. Login -> sin sesión activa -> con permiso
   - Entrar con admin/supervisor.
   - Abrir caja con fondo inicial.
   - Resultado esperado: se crea `ActiveSession` y permite entrar a ventas.

3. Ventas sin sesión
   - Con usuario logueado y sin sesión activa.
   - Intentar cobrar en ventas.
   - Resultado esperado: bloqueo + solicitud de apertura de caja.

4. Logout con sesión activa
   - Con sesión activa, intentar cerrar sesión desde sidebar o cuenta.
   - Resultado esperado: bloqueo con diálogo y única acción para cerrar la sesión completa.

5. Cierre único de sesión
   - Con sesión activa, ejecutar el cierre.
   - Resultado esperado: se cierra la sesión, se cierra la caja, se imprime el comprobante y el usuario sale del sistema.

6. Recuperación tras reinicio
   - Simular sesión abierta con `business_date` anterior o reinicio del cliente.
   - Entrar nuevamente al sistema.
   - Resultado esperado: se restaura la `ActiveSession` si sigue abierta.

7. Conflicto de dos usuarios
   - Con una sesión activa ya abierta, otro usuario intenta iniciar una nueva sesión en la misma caja.
   - Resultado esperado: bloqueo por sesión activa existente.
