# Guía exacta: Reimplementar Payment con 3 switches + configuración por defecto

Esta guía reproduce exactamente los cambios realizados para:
- Pantalla de cobro (`PaymentDialog`) con 3 opciones exclusivas.
- Botón de cobro dinámico según opción.
- Configuración por defecto en **Configuración Empresa**.
- Persistencia en base de datos.

---

## Objetivo funcional

En el diálogo de pago debe existir:
1. Switch **Ticket** (cobrar e imprimir).
2. Switch **PDF** (cobrar y descargar).
3. Switch **Sin imprimir** (solo cobrar).

Comportamiento:
- Solo una opción activa a la vez.
- El botón principal cambia texto/ícono según la opción activa.
- El valor inicial de la opción sale desde Configuración Empresa.

---

## Archivos a tocar

1. `lib/features/settings/data/business_settings_model.dart`
2. `lib/features/settings/data/business_settings_repository.dart`
3. `lib/features/settings/ui/business_settings_page.dart`
4. `lib/features/sales/ui/sales_page.dart`
5. `lib/features/sales/ui/dialogs/payment_dialog.dart`

---

## Paso 1: Modelo de configuración de empresa

Archivo: `lib/features/settings/data/business_settings_model.dart`

### 1.1 Agregar propiedad nueva
Agregar en `BusinessSettings`:
- `defaultChargeOutputMode` con valores permitidos: `ticket | pdf | none`.

### 1.2 Constructor
Agregar default:
- `this.defaultChargeOutputMode = 'ticket'`

### 1.3 fromMap
Leer columna:
- `default_charge_output_mode`
- Fallback: `'ticket'`

### 1.4 toMap
Guardar campo:
- `'default_charge_output_mode': defaultChargeOutputMode`

### 1.5 copyWith
Agregar parámetro opcional:
- `String? defaultChargeOutputMode`

Y asignar:
- `defaultChargeOutputMode: defaultChargeOutputMode ?? this.defaultChargeOutputMode`

### 1.6 Igualdad
Incluir en:
- `operator ==`
- `hashCode`

---

## Paso 2: Persistencia DB + migración automática

Archivo: `lib/features/settings/data/business_settings_repository.dart`

En `_expectedColumns`, agregar:
- `'default_charge_output_mode': "TEXT DEFAULT 'ticket'"`

Con esto:
- Instalaciones nuevas crean la columna.
- Instalaciones existentes la migran automáticamente por `_migrateTableColumns`.

---

## Paso 3: Configuración visual en Configuración Empresa

Archivo: `lib/features/settings/ui/business_settings_page.dart`

### 3.1 Guardar valor al presionar "Guardar todo"
En `_saveAll()`, dentro de `copyWith(...)`, incluir:
- `defaultChargeOutputMode: _draft.defaultChargeOutputMode`

### 3.2 Nueva sección en pestaña de Impuestos
En `_buildTaxesTab(...)`, agregar sección:
- Título: `CONFIGURACIONES GENERALES`
- `DropdownButtonFormField<String>`
  - `ticket`: Ticket (Cobrar e imprimir)
  - `pdf`: PDF (Cobrar y descargar)
  - `none`: Sin imprimir (Solo cobrar)

Al cambiar dropdown:
- actualizar `_draft = _draft.copyWith(defaultChargeOutputMode: value)`
- `_hasChanges = true`

### 3.3 Normalizar valor inicial (evitar crash de Dropdown)
Antes del `DropdownButtonFormField`, crear valor seguro:
- si no está en `{ticket, pdf, none}` usar `ticket`.

---

## Paso 4: Pasar configuración al flujo de cobro

Archivo: `lib/features/sales/ui/sales_page.dart`

### 4.1 Import requerido
Agregar import:
- `../../settings/providers/business_settings_provider.dart`

### 4.2 Leer valor configurado
Antes de abrir `PaymentDialog`:
- leer `configuredChargeOutputMode = ref.read(businessSettingsProvider).defaultChargeOutputMode`

### 4.3 Enviar al diálogo
Al construir `PaymentDialog`, pasar:
- `initialChargeOutputMode: configuredChargeOutputMode`

---

## Paso 5: Rediseño completo del PaymentDialog

Archivo: `lib/features/sales/ui/dialogs/payment_dialog.dart`

### 5.1 Nuevo enum
Agregar:
- `enum PaymentOutputMode { ticket, pdf, none }`

### 5.2 Parámetro de entrada
En `PaymentDialog` agregar:
- `final String? initialChargeOutputMode;`

### 5.3 Estado interno
Reemplazar bools sueltos por modo único:
- eliminar dependencia principal de `_printTicket` y `_downloadInvoicePdf` como estado primario
- usar `PaymentOutputMode _outputMode`
- getters derivados:
  - `bool get _printTicket => _outputMode == PaymentOutputMode.ticket`
  - `bool get _downloadInvoicePdf => _outputMode == PaymentOutputMode.pdf`

### 5.4 Resolver valor inicial
Crear `_resolveInitialOutputMode()`:
- `pdf` solo válido si `allowInvoicePdfDownload == true`
- si inválido, fallback a `ticket`
- si no hay configuración, usar comportamiento por defecto anterior.

En `initState()`:
- `_outputMode = _resolveInitialOutputMode();`

### 5.5 Selectores exclusivos
Crear métodos:
- `_selectPrint()` -> `_outputMode = ticket`
- `_selectDownloadInvoicePdf()` -> `_outputMode = pdf`
- `_selectWithoutPrinting()` -> `_outputMode = none`

### 5.6 Layout responsivo del diálogo
En `build()`:
- calcular `viewport = MediaQuery.sizeOf(context)`
- `dialogWidth = (viewport.width * 0.92).clamp(500.0, 860.0)`
- `dialogMaxHeight = (viewport.height * 0.90).clamp(620.0, 920.0)`

Aplicar a `Container` principal del `Dialog`.

### 5.7 Footer con 3 switches
Reemplazar footer anterior por:
- `LayoutBuilder + Wrap`
- 3 tarjetas/switches:
  1. TICKET
  2. PDF
  3. SIN IMPRIMIR

Reglas:
- Son exclusivos (activar uno desactiva los demás por diseño de `_outputMode`).
- Si `allowInvoicePdfDownload == false`, PDF deshabilitado.

### 5.8 Botón dinámico único
Crear:
- `_chargeActionLabel()`
- `_chargeActionIcon()`

Mapeo:
- ticket -> `COBRAR E IMPRIMIR`
- pdf -> `COBRAR Y DESCARGAR`
- none -> `COBRAR SIN IMPRIMIR`

Usar un solo `ElevatedButton.icon` con texto/ícono dinámico.

### 5.9 Resultado del diálogo
Mantener payload de salida con:
- `printTicket: _printTicket`
- `downloadInvoicePdf: widget.allowInvoicePdfDownload ? _downloadInvoicePdf : false`

Así el resto del flujo no se rompe.

---

## Checklist de verificación manual

1. Ir a Configuración Empresa > Impuestos > Configuraciones generales.
2. Elegir `Ticket` y guardar.
3. Abrir cobro:
   - Debe iniciar con switch Ticket activo.
   - Botón: `COBRAR E IMPRIMIR`.
4. Activar switch PDF:
   - Botón: `COBRAR Y DESCARGAR`.
5. Activar switch Sin imprimir:
   - Botón: `COBRAR SIN IMPRIMIR`.
6. Confirmar exclusividad:
   - solo un switch activo cada vez.
7. Confirmar responsive:
   - en ventanas pequeñas no se rompe footer ni botones.

---

## Checklist de compilación

Validar errores en:
- `lib/features/settings/data/business_settings_model.dart`
- `lib/features/settings/data/business_settings_repository.dart`
- `lib/features/settings/ui/business_settings_page.dart`
- `lib/features/sales/ui/sales_page.dart`
- `lib/features/sales/ui/dialogs/payment_dialog.dart`

---

## Nota importante

Si la opción por defecto no aparece al instante en PaymentDialog:
- verificar que se presionó **GUARDAR TODO**.
- cerrar y volver a abrir el diálogo de cobro.

Con esto queda totalmente reproducible y estable.
