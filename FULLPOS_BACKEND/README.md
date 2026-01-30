# FULLPOS Backend

Backend en Node.js + TypeScript con Express y Prisma para los m\u00f3dulos de autenticaci\u00f3n, reportes del due\u00f1o (Owner), descargas de app y servicio de overrides.

## Requisitos
- Node.js 18+
- PostgreSQL (usa `DATABASE_URL`)

## Instalaci\u00f3n r\u00e1pida
```bash
cd fullpos_backend
cp .env.example .env   # completar secretos y URL de BD
npm install
npm run migrate:dev    # aplica migraciones en la BD apuntada por .env
npm run seed           # datos demo (usuario owner/fullpos123)
npm run dev            # desarrollo
```

Scripts disponibles:
- `npm run dev`: servidor en desarrollo con recarga
- `npm run start`: servidor compilado (`npm run build` primero)
- `npm run migrate`: despliega migraciones
- `npm run migrate:dev`: crea/aplica migraciones en desarrollo
- `npm run generate`: genera Prisma Client
- `npm run seed`: carga datos demo multiempresa

## Variables de entorno clave
- `DATABASE_URL`: conexi\u00f3n PostgreSQL
- `JWT_ACCESS_SECRET` / `JWT_REFRESH_SECRET`: llaves de firma
- `JWT_ACCESS_EXPIRES_IN` / `JWT_REFRESH_EXPIRES_IN`: duraciones (`30m`, `7d`, etc.)
- `CORS_ORIGINS`: lista separada por comas
- `OVERRIDE_API_KEY`: API key opcional para `override/request` y `override/verify`
- `OWNER_APP_ANDROID_URL` / `OWNER_APP_IOS_URL` / `OWNER_APP_VERSION`: links para descargas

## Endpoints principales
- `POST /api/auth/login`: login (usuario/email + password)
- `POST /api/auth/refresh`: refresh de tokens
- `GET /api/auth/me`: perfil + empresa
- `POST /api/auth/provision-owner`: crear/actualizar usuario owner por RNC (protegido por `OVERRIDE_API_KEY` si aplica)
- `GET /api/reports/sales/summary?from&to`
- `GET /api/reports/sales/by-day?from&to`
- `GET /api/reports/sales/list?from&to&page=1&pageSize=20`
- `GET /api/reports/cash/closings?from&to`
- `GET /api/reports/cash/closing/:id`
- `GET /api/downloads/owner-app`: links de app owner
- `POST /api/override/request|approve|verify`, `GET /api/override/audit`
- `GET /api/override/requests`: lista de solicitudes pendientes

Rutas de reportes y auth requieren `Authorization: Bearer <token>`.

## Pruebas r\u00e1pidas
Usa `test.http` con VSCode REST Client o similar. Credenciales seed: `owner / fullpos123`. Ajusta `from/to` al rango deseado.
