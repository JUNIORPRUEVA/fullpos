# Catalog Sync Architecture

## Objetivo

El flujo de catalogo usa una estrategia local-first para mantener respuesta inmediata en UI y sincronizacion casi en tiempo real con el backend. La primera implementacion cubre productos, pero el patron se diseno para poder repetirse en clientes, gastos, ventas, suplidores y otros modulos.

## Flujo local-first

1. Una mutacion de producto en FULLPOS escribe primero en SQLite.
2. El registro local queda marcado con metadata de sync: `sync_status`, `needs_sync`, `local_updated_at_ms`, `version`, `last_sync_error`.
3. En la misma transaccion se inserta o actualiza un item en `product_sync_outbox`.
4. La UI se refresca desde la base local inmediatamente mediante `ProductSyncEventBus`.

Este orden evita que la experiencia de caja dependa de la red y garantiza que un crash entre escritura local y enqueue no deje cambios perdidos.

## Flujo outbox

La tabla `product_sync_outbox` mantiene una sola operacion pendiente por producto para coalescer ediciones repetidas.

Campos principales:

- `entity_type`, `entity_id`
- `operation_type`
- `payload_json`
- `status`
- `priority`
- `retry_count`
- `next_attempt_at_ms`
- `last_error`

El worker `ProductSyncService` hace lo siguiente:

1. Lee items `pending` o `failed` vencidos.
2. Marca el item como `syncing`.
3. Publica la operacion al backend en `/api/products/sync/operations`.
4. Si el backend confirma, aplica el snapshot canonico del servidor en SQLite.
5. Si falla, deja el item en `failed` con backoff exponencial.

Las operaciones de stock usan prioridad mas alta para salir antes del resto de cambios.

## Flujo backend

El backend trata al servidor como autoridad:

1. Resuelve la empresa por JWT o por `companyCloudId` y `companyRnc`.
2. Busca el producto por `serverProductId`, `localProductId` o `code`.
3. Valida conflicto usando `version` y `lastClientMutationId`.
4. Aplica la mutacion atomica.
5. Incrementa `version`.
6. Devuelve el producto canonico.
7. Emite un evento realtime solo despues del commit.

Eventos emitidos:

- `product.created`
- `product.updated`
- `product.deleted`
- `product.stock_updated`

## Flujo realtime

Se usa Socket.IO con rooms por empresa.

- FULLPOS Owner autentica con JWT y se une automaticamente al room de su empresa.
- FULLPOS autentica con `x-cloud-key` y referencia de empresa.
- Cuando llega `product.event`, cada cliente actualiza solo el registro afectado.

FULLPOS aplica el snapshot recibido en SQLite.

FULLPOS Owner actualiza el estado en memoria de la pantalla de productos y solo hace `GET /api/products/:id` como fallback puntual si necesita refrescar el registro recibido.

## Manejo de conflictos

La estrategia principal es versionado autoritativo del servidor.

- Cada producto tiene `version`.
- El cliente envia `baseVersion` y `clientMutationId`.
- Si el servidor ya tiene otra version y no se trata de una repeticion idempotente del mismo `clientMutationId`, responde `409`.
- El cliente marca el producto local como `conflict` y registra `last_sync_error`.

Esto evita sobrescrituras silenciosas. Si en el futuro se necesita una resolucion asistida, el mismo estado de conflicto sirve para abrir una UI de revision.

## Retry y resiliencia

- El worker local usa backoff exponencial.
- Los items fallidos quedan persistidos en SQLite.
- El worker se inicia al arrancar la app y reanuda pendientes automaticamente.
- Socket.IO se reconecta automaticamente.
- Owner mantiene polling lento como fallback de recuperacion, no como mecanismo principal.

## Soft delete

Los deletes se manejan con `deletedAt` para evitar perdida de contexto durante sync.

- En FULLPOS se marca `deleted_at_ms` localmente.
- En backend se llena `deletedAt` y se incrementa `version`.
- El evento `product.deleted` permite limpiar listas y caches sin recargar todo el catalogo.

## Escalado a otras tablas

Para extender el patron a clientes, gastos, ventas o suplidores, repetir estos componentes:

1. Metadata local de sync por entidad.
2. Outbox dedicado o un outbox generico con clave de entidad.
3. Worker con retry, coalescing e idempotencia.
4. Endpoint backend por operaciones con version y `clientMutationId`.
5. Emision realtime post-commit.
6. Listener en cliente que actualice solo el registro afectado.

La regla importante es mantener una sola fuente de verdad inmediata en local y una sola fuente de verdad autoritativa en servidor, unidas por outbox y eventos realtime.