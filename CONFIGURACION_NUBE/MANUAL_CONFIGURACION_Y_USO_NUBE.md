
# Manual de Configuración y Uso de la Nube (FULLPOS)

Este manual explica cómo **activar** y **usar** la nube en FULLPOS para que el dueño pueda **ver su negocio remotamente** (desde FULLPOS Owner).

IMPORTANTE: La nube es un servicio de pago.

---

## 1) Costo del servicio

- **USD 15 / mes por usuario** que use la app **FULLPOS Owner**.
- Se cobra por cada usuario que tenga acceso remoto.

Activa la nube solo si realmente necesitas el acceso remoto.

---

## 2) Requisitos

- Tener contratado/activo el servicio de nube.
- Tener internet en el equipo.
- Tener el **RNC del negocio** configurado en FULLPOS (Configuración → Negocio).

---

## 2.1) Solicitar la app / soporte (WhatsApp)

Para solicitar la app o ayuda con la configuración, escribe por WhatsApp a:

- **Número:** 8295344286
- **Enlace directo:** https://wa.me/18295344286

---

## 3) Activar la nube en el POS

En la aplicación FULLPOS:

1. Ir a: **Configuración → NUBE (Nube y Accesos)**.
2. El switch **siempre aparece desactivado por defecto**.
3. Activa: **“Sincronización en la nube”** solo si vas a usar el servicio.

---

## 4) Crear usuario y contraseña para entrar a la nube (FULLPOS Owner)

Para ver tu negocio remotamente se usa la app **FULLPOS Owner**.

En FULLPOS (POS):

1. Ir a **Configuración → NUBE (Nube y Accesos)**.
2. En la sección **“Acceso a la nube (FULLPOS Owner)”**:
	 - Escribe el **Usuario** (ej: `owner` o tu correo)
	 - Escribe la **Contraseña** y confírmala
	 - Presiona **Guardar usuario y contraseña**

Esto crea/actualiza el acceso remoto en el servidor.

Luego, en FULLPOS Owner:

1. Instala/abre FULLPOS Owner.
2. Inicia sesión con el usuario y contraseña que acabas de configurar.

---

## 5) ¿Qué hace exactamente la “Nube” en FULLPOS?

Cuando la nube está activa:

- Se habilitan **funciones remotas** (por ejemplo autorizaciones/overrides remotos cuando aplique).
- Se habilita el **acceso remoto del dueño** mediante FULLPOS Owner.

---

## 6) Flujo de uso (Acceso remoto del dueño)

1. En FULLPOS: activa la nube (switch) si usarás el servicio.
2. En FULLPOS: configura usuario/contraseña (sección “Acceso a la nube”).
3. En FULLPOS Owner: inicia sesión y revisa tus reportes.

---

## 7) Flujo de uso (Aprobación remota / Override remoto)

1. El cajero intenta una acción que requiere autorización.
2. FULLPOS muestra una ventana de autorización.
3. Si la nube está activa, el cajero puede usar el **método remoto (nube)** para enviar la solicitud.
4. El propietario/supervisor aprueba desde el sistema remoto (Owner/Backend).
5. FULLPOS valida el token/resultado con el servidor.

---

## 8) Problemas comunes

- **No me deja guardar el usuario/contraseña**
	- Verifica que el negocio tenga **RNC** configurado en Configuración → Negocio.
	- Verifica que la contraseña tenga al menos 6 caracteres.

- **No puedo entrar en FULLPOS Owner (credenciales inválidas)**
	- Asegúrate de escribir el usuario igual.
	- Vuelve a configurar la contraseña en Configuración → Nube.

- **La nube está “Activada” pero no funciona**
	- Verifica que hay internet.
	- Contacta soporte por WhatsApp si persiste.

---

## 9) Configuración avanzada (si soporte lo solicita)

Normalmente no necesitas tocar configuración técnica.

Si soporte te pide revisar parámetros, usa la plantilla:

- `CONFIGURACION_NUBE/PLANTILLA_CONFIG_NUBE.json`

---

## 10) Checklist rápido

- [ ] Activé Configuración → Nube
- [ ] Configuré Usuario/Contraseña para FULLPOS Owner
- [ ] Probé iniciar sesión en FULLPOS Owner

