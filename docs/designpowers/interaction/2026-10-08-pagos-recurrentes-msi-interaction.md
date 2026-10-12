# Interaction design: Pagos recurrentes y MSI

_2026-10-08 · design-lead (interaction) · Modo directo._
_Insumos: brief, estrategia, plan de diseño (B1–C4), taste aprobado, copy aprobado (ids), decisiones de Victor del 2026-10-08 (advertencia B + A, presupuestos futuros), código actual: `transactions/_form`, `transactions/show`, `UI::AccountPage`, `budgets/*`, `budget_categories/*`, `DS::Disclosure`, `DS::Dialog`, `DS::Tabs`, `layouts/shared/_confirm_dialog`, `RecurringTransaction`, `Family::CyclePeriod`._

Alcance: flujos, estados, feedback, foco, teclado/lector, aria-live, fronteras Turbo, responsabilidades Stimulus, errores y ubicación de la información. **No** define estilo visual final (lo hace design-lead visual). Los strings se citan por **id del copy doc**. Los strings nuevos de §10 ya están revisados y tienen id final en el copy doc.


> **3ª pasada de copy (Victor, 2026-10-08):** el tipo se llama solo "Installments" (sin "(MSI)" ni `<abbr>`); "Doesn't repeat" siempre por defecto; 32 strings removidos. Las tablas Kept del copy doc son la fuente de verdad; los ids tachados aquí ya no existen.

---

## 0. Decisiones de esta etapa (resumen)

| # | Decisión | Por qué |
|---|---|---|
| D1 | Captura en un **`DS::Disclosure` propio** `b1.disclosure_title`, entre la sección principal y "Details" | Se descubre al escanear; "Details" ya tiene tags/notas; el título dice qué hay dentro. Cero componentes nuevos. |
| D2 | Tipo como **grupo de radios** (`<fieldset><legend>` `b1.type_label`), no `<select>` | 3 opciones visibles de un vistazo, un toque en móvil, flechas nativas. "Installments" va al final para que ocultarla no mueva las otras. |
| D3 | `Monthly charge` **no muestra "First payment"**: la transacción capturada **es** el pago 1 (así funciona `create_from_entry!`) | Un campo menos. El día de la transacción define el día de cobro. ~~`b1.first_payment_help_charge`~~ *(removed, Victor 2026-10-08)* queda sin uso. |
| D4 | El resumen B2 se **calcula en servidor** (endpoint de preview en un Turbo frame), no con `Intl.NumberFormat` en JS | Convención 3 (formato server-side) + principio "una verdad por número": misma matemática que `occurrence_amount` / `occurrence_date`. Evita que JS y Ruby difieran en el redondeo del último pago o el día 31. |
| D5 | Debounce **500 ms** antes de pedir el preview; el frame es la región `role="status"` con `aria-busy` mientras recalcula | Un anuncio por pausa, no por tecla. `aria-busy` silencia anuncios intermedios. El atenuado visual inmediato da feedback < 100 ms. |
| D6 | Conversión (B3) **inline en el drawer, en dos pasos dentro del mismo bloque**: campos → `Review` → confirmación; foco al encabezado de la confirmación (`tabindex="-1"`) | La conversión reescribe presupuestos pasados (backfill): merece un momento de revisión, pero sin modal extra. El foco se mueve solo cuando el usuario lo pidió (botón), nunca mientras escribe. |
| D7 | Diálogos destructivos (Stop, borrar MSI, borrar cuota): se **extiende el confirm dialog global** con botón secundario (`Keep it`) que recibe el foco inicial | Hoy `_confirm_dialog` solo tiene el botón de confirmar con `autofocus` (el destructivo) y una X. Es una extensión de lo existente, no un componente nuevo. Beneficia a todos los borrados de la app. |
| D8 | "Stop" / "Keep it" son **strings fijos** en todas las capas (vista, `CustomConfirm`, notices); "Cancel" solo existe como `b3.confirm_secondary` (cerrar campos sin guardar) | Pedido del content-writer. Ver checklist §7.6. |
| D9 | Advertencia **B + A**: se muestra cuando los compromisos del ciclo > `budgeted_spending` del ciclo; nombra el ciclo, el excedente y el % del presupuesto. En estado normal, el % aparece como dato neutro en la línea C4 (sin amarillo) | El % (A) es información útil siempre; el color solo se gana al pasar el 100% (taste principio 2). |
| D10 | Compromisos en presupuesto viven en un **bloque propio** en la columna izquierda (debajo del donut, encima de los tabs), no dentro de `_budgeted_summary` | Hoy `_budgeted_summary` solo se ve si el presupuesto está inicializado y hay saldo por asignar; los compromisos deben verse siempre, incluso en ciclos futuros sin configurar. |
| D11 | **Presupuestos futuros = la misma pantalla de presupuesto**, con "Committed" en lugar de "Spent". Horizonte: **12 ciclos** después del actual | Reusar antes de crear: mismo header, donut, filas de categoría y drawer. Un futuro no tiene gasto real; el compromiso ocupa su lugar con su propia etiqueta. |
| D12 | El schedule de un plan (fecha de inicio, número de pagos) **no es editable en v1** | Cierra el riesgo de `last_generated_on` del carry-over sin lógica nueva. Para cambiarlo: Stop + crear otro. |
| D13 | **(Canvas de Victor, 2026-10-08)** La advertencia de exceso **se mueve a la captura**: bloque "budget impact" en B1 con Installments (§2.4b). **C2 ya no advierte.** En C4 la advertencia queda como título + "Review budget" | Avisar cuando todavía se puede decidir la compra |
| D14 | **(Canvas)** B3 cerrado muestra el estado actual (`b3.status_*`) y el botón es "Edit" | El bloque dice qué es la transacción hoy, no solo ofrece una acción |

---

## 1. Principios de interacción transversales

- **Foco:** nunca se mueve mientras la persona escribe. Solo se mueve como respuesta a un botón (Review, Save, Stop) o a un error de envío (al primer campo inválido).
- **Anuncios (aria-live):** solo tres regiones en toda la feature:
  1. Resumen B2/B3 (`role="status"`, `aria-atomic="true"`, con `aria-busy`).
  2. Bandeja de notificaciones (`#notification-tray`), que hoy **no** tiene `role="status"`: agregarlo (§11).
  3. Errores de bloque B3 (`role="alert"`, solo tras una acción fallida).
  Advertencias y líneas de compromiso son contenido estático: no se anuncian al cargar.
- **Errores:** nunca 500. Patrón: qué pasó → qué hacer (`b.err.*`, `b3.err.*`, `c1.err.*`). El campo lleva `aria-invalid="true"` + `aria-describedby` al mensaje. El input de la persona se preserva siempre.
- **Turbo:** respuestas 422 re-renderizan el mismo frame; éxitos usan `turbo_stream` para reemplazar solo lo que cambió + notice. No hay recargas completas salvo al cerrar el diálogo del plan (`reload_on_close`).
- **Stimulus:** un solo controller nuevo, `recurring-form` (≤ 6 targets, acciones declarativas), usado en el form nuevo y en el bloque de conversión. Todo lo demás es HTML + Turbo.
- **Movimiento:** solo atenuado del resumen al recalcular y apertura nativa de `<details>`; ≤ 150 ms; nada con `prefers-reduced-motion: reduce`.
- **Fechas y ciclo:** toda etiqueta de ciclo sale de `family.cycle_range_containing` / `Budget#name`. Nada hardcodeado. **Nota para content-writer:** con `cycle_end_day = 27` el código produce ciclos **28 → 27** (p. ej. "Oct 28 – Nov 27"), no "27 – 26" como en los ejemplos del copy. Los ejemplos deben salir del helper, no escribirse a mano.

---

## 2. B1 + B2 — Captura en "New transaction"

### 2.1 Ubicación
Modal existente `transactions/new` (`DS::Dialog`, frame `modal`). Orden:
1. Tabs Expense / Income (existentes).
2. Sección principal: Description, Account (select o hidden), Amount, Category, Date.
3. **`DS::Disclosure` `b1.disclosure_title`** (nuevo uso, cerrado por defecto). **Solo se renderiza en Expense** (`nature=outflow`). En Income no existe; `b.err.expense_only` queda solo como defensa server-side.
4. `DS::Disclosure` Details (existente).
5. Submit existente (sin renombrar, `b1.submit`).

### 2.2 Flujo
1. Victor llena la sección principal como hoy.
2. Abre "Recurring payment" (click, Enter o Space sobre el `<summary>`; el lector dice "Recurring payment, collapsed/expanded").
3. Grupo de radios `b1.type_label`: `b1.type_none` (marcado), `b1.type_charge`, `b1.type_installments`.
   - `b1.type_installments` **solo existe** si la cuenta seleccionada es tarjeta de crédito. Si no hay cuenta seleccionada aún, no aparece.
4. Al elegir un tipo, aparece su grupo de campos (el otro grupo queda `hidden` y con inputs `disabled`, así no entra al tab order ni se envía):
   - **Installments:** `b1.payments_label_installments` (number, 2–48, `inputmode="numeric"`, vacío por defecto) + ~~`b1.payments_help_installments`~~ *(removed, Victor 2026-10-08)*; `b1.first_payment_label` (date, por defecto fecha de compra + 1 mes) + ~~`b1.first_payment_help_installments`~~ *(removed, Victor 2026-10-08)*; ~~`b1.type_help_installments`~~ *(removed, Victor 2026-10-08)* bajo el grupo de radios.
   - **Monthly charge:** `b1.payments_label_charge` con sufijo `b1.payments_suffix` dentro del `<label>` (opcional) + ~~`b1.payments_help_charge`~~ *(removed, Victor 2026-10-08)*; ~~`b1.type_help_charge`~~ *(removed, Victor 2026-10-08)* bajo los radios; ~~`b1.short_month_note`~~ *(removed, Victor 2026-10-08)* añadido si el día de la fecha es 29–31.
5. Debajo de los campos, el **resumen** (frame `recurring_preview`) se actualiza tras 500 ms sin cambios.
6. Submit. Éxito → el modal se cierra (comportamiento actual) y aparece notice.

### 2.3 Reglas de los campos derivados
- **First payment por defecto** = `date + 1 month`. Si Victor cambia la fecha de compra **y no ha tocado** First payment, se recalcula. Si ya lo tocó, se respeta (el controller marca el campo como "editado" en el primer `input`).
- **Cambio de cuenta con Installments elegido** a una cuenta no-tarjeta: el radio Installments desaparece, la selección vuelve a `b1.type_none`, los campos se ocultan y el texto `b.err.installments_credit_only` aparece como nota (no error, sin `aria-invalid`) bajo la leyenda, y se anuncia una vez por la región del resumen. Caso borde; lo importante es que nada se pierda en silencio.
- **Monto / pagos inválidos al escribir:** no se marcan en vivo (no regañar mientras escribe). El resumen muestra ~~`b2.summary_incomplete`~~ *(removed, Victor 2026-10-08)* (sin anuncio). La validación se hace al enviar.

### 2.4 Resumen en vivo (B2)
- **Frame:** `<turbo-frame id="recurring_preview" role="status" aria-atomic="true">` dentro del disclosure. Es persistente (existe vacío desde el render), así el lector anuncia los cambios de su contenido.
- **Fuente:** `GET /recurring_transactions/preview?…` (amount, currency, date, account_id, plan_type, total_payments, start_date). El servidor construye un `RecurringTransaction.new` **sin guardar** y renderiza:
  - `b2.summary_installments` o `b2.summary_installments_uneven` (solo si el último difiere),
  - `b2.summary_charge_end` / `b2.summary_charge_open`,
  - `+ b2.summary_past_due` si hay ocurrencias con fecha ≤ hoy (hoy = misma fecha que usa el generador, ver §11 timezone),
  - ~~`b2.summary_incomplete`~~ *(removed, Victor 2026-10-08)* si falta monto o pagos (este texto va con `aria-hidden` en la versión anunciada: no se anuncia).
  - Texto visual con `·` `aria-hidden`; texto accesible con comas (columna "Texto anunciado" del copy) en un `<span class="sr-only">`.
- **Tiempos:** en cada `input/change` relevante → atenuado inmediato + `aria-busy="true"` en el frame; tras 500 ms sin cambios → se fija `src` del frame; al cargar → `aria-busy="false"` (dispara el anuncio). Si el contenido nuevo es idéntico al anterior, no se re-asigna (no repite anuncio).
- **Error de red/servidor del preview:** se conserva el último resumen, se quita `aria-busy`, y si no había resumen se muestra `b2.summary_unavailable` (§10). El envío sigue funcionando: el servidor valida igual.

### 2.4b Impacto en presupuesto (nuevo, D13)
- **Cuándo:** solo con `plan_type = installments`, cuando el resumen B2 está completo (monto, número de pagos y primera fecha válidos) y existe un presupuesto de base (propio o el último configurado). Si falta algo, el bloque no se renderiza (silencio, no error).
- **Cálculo (servidor, misma petición del preview, mismo debounce de 500 ms y mismo `aria-busy`):** para los meses de presupuesto que contienen las **primeras 3 cuotas** del plan (menos si el plan tiene menos), `total(C) = committed(C) + cuota de este plan en C`, con `committed(C)` y `budget_basis(C)` **idénticos a §6.1** (familia completa, todas las cuentas). Exceso si `total(C) > budget_basis(C)`; mismo redondeo que §6.1.
- **Qué muestra:** cabecera `bi.title_over` (primer mes en exceso; `bi.title_over_multi` si hay más de uno) o, sin exceso, solo `bi.subtitle`; una fila por mes (`Budget#name`, `bi.month_over` o `bi.month_percent`, barra comprometido / esta compra / marca de presupuesto, `bi.month_detail`); leyenda; `bi.reference` si algún mes usa presupuesto de referencia.
- **Lector de pantalla:** el bloque no es región viva. Con exceso, `bi.title_over` se **añade al texto `sr-only` del resumen B2** (la única región `role=status`): se anuncia una vez por pausa junto con el resumen. Barras y leyenda `aria-hidden`; cada `<li>` se lee como texto. El bloque es `<section aria-labelledby>`.
- **No bloquea:** el envío nunca se impide por exceso; no hay CTA dentro del bloque.
- **Relación con presupuestos futuros:** tras guardar, `committed(C)` de C4 en esos meses = `total(C)` del preview (test de paridad).
- **B3 (convertir):** el bloque no aparece en v1 (no está en el canvas).

### 2.5 Estados

| Estado | Visual | Lector / teclado |
|---|---|---|
| Default (cerrado) | Summary "Recurring payment" | "Recurring payment, collapsed". Tab lo alcanza después de Date |
| Abierto, "Doesn't repeat" | Solo radios | Flechas mueven entre radios |
| Tipo elegido, incompleto | Campos + ~~`b2.summary_incomplete`~~ *(removed, Victor 2026-10-08)* | Nada anunciado |
| Recalculando | Resumen atenuado (≤150 ms, sin animación con reduced-motion) | `aria-busy="true"`, silencio |
| Resumen listo | Resumen con cifras `tabular-nums` | Anuncio polite único |
| Resumen listo + exceso (Installments) | Resumen + bloque de impacto con cabecera roja | El anuncio incluye `bi.title_over` |
| Resumen listo sin exceso (Installments) | Resumen + bloque de impacto neutro | Anuncio solo del resumen |
| Error de envío | `shared/form_errors` arriba + mensaje junto al campo + disclosure abierto | Foco al primer campo inválido (`autofocus` server-side en ese input) |
| Éxito | Modal cierra, notice `b3.success_installments` / `b3.success_charge` (válidos también aquí) | Notice en `role="status"` |
| Preview no disponible | Último resumen o `b2.summary_unavailable` | Anuncio único |

### 2.6 Envío y errores (server)
- Params virtuales `recurrence[plan_type|total_payments|start_date]`, fuera de `entry_params`.
- `TransactionsController#create`: si `plan_type` presente, **una sola transacción de DB**: guardar entry + `RecurringTransaction.create_from_entry!`. Si el plan es inválido → rollback de todo (no queda una compra sin plan), `render :new, status: :unprocessable_entity` con:
  - el disclosure `open: true` cuando hay errores en `recurrence[...]` o cuando `plan_type != none` (no esconder lo que el usuario llenó),
  - errores mapeados a `b.err.*` (no mensajes de ActiveRecord crudos),
  - `autofocus` en el primer campo inválido.
- Mapeo: `payments_range_installments`, `payments_range_charge`, `first_payment_missing`, `first_payment_before_purchase`, `expense_only`, `installments_credit_only`, `account_not_manual`, `amount_too_small`.

### 2.7 Stimulus `recurring-form` (nuevo, mínimo)
- `data-controller="recurring-form"` en el `<form>` (o en el bloque de conversión).
- **Targets (5):** `chargeFields`, `installmentsFields`, `installmentsOption`, `firstPayment`, `preview`.
- **Values:** `creditAccountIds` (Array), `previewUrl` (String), `accountId` (String, cuando la cuenta es fija).
- **Acciones declarativas:**
  - radios: `change->recurring-form#selectType`
  - account select: `change->recurring-form#accountChanged`
  - amount, date, payments, first payment: `input->recurring-form#schedulePreview` / `change->recurring-form#schedulePreview`
  - date: `change->recurring-form#syncFirstPayment`
  - first payment: `input->recurring-form#markFirstPaymentEdited`
  - B3: `click->recurring-form#toggle` (botón `Set up`, maneja `aria-expanded`)
- **No hace:** formatear dinero, calcular cuotas, validar reglas de negocio.

---

## 3. B3 — Convertir una transacción existente (drawer `transactions/show`)

### 3.1 Cuándo aparece el bloque (sección Settings)

| Transacción | Bloque |
|---|---|
| `standard`, expense, no transfer, sin plan, cuenta manual activa | Visible, cerrado: `b3.title` + estado `b3.status_one_time` + botón `b3.button` ("Edit", D14). ~~`b3.body_*`~~ removidos |
| `one_time` | Visible **sin botón**, descripción = `b3.err.not_standard` (explica cómo habilitarlo) |
| Transfer / `cc_payment` / income / cuenta conectada o inactiva | No se renderiza |
| `msi_purchase` / `installment` / ocurrencia de charge | No se renderiza; en su lugar el bloque de procedencia C1 arriba de Overview |

Posición: primer bloque de Settings (antes de Exclude/One-time), porque es la acción nueva más probable en una compra; Delete sigue al final.

### 3.2 Flujo
Todo dentro de `<turbo-frame id="<dom_id(entry, :recurrence)>">`.

1. **Cerrado.** Estado actual (`b3.status_*`) + botón `b3.button` ("Edit", nombre accesible "Edit recurring payment", D14), `aria-expanded="false"`, `aria-controls` al panel.
2. **Campos.** Click → `aria-expanded="true"`, panel visible (sin mover el foco; el siguiente Tab entra al primer campo):
   - Tarjeta de crédito: radios `b1.type_none` (**marcado por defecto**, Victor 2026-10-08: "Doesn't repeat" siempre es el default del grupo Repeat), `b1.type_charge` y `b1.type_installments`; los campos aparecen al elegir un tipo y `b3.review` no avanza con "Doesn't repeat". *(copy 3ª pasada; confirmar con design-lead)*
   - Otra cuenta: sin radios; texto ~~`b3.body_other`~~ *(removed, Victor 2026-10-08)* ya explica; solo campos de charge.
   - Mismos campos de §2.2 (First payment por defecto = fecha de la compra + 1 mes) + frame de preview (§2.4).
   - Botones: primario `b3.review` y secundario `b3.confirm_secondary` ("Cancel").
3. **Review.** `GET …/recurrence/new?…` dentro del frame:
   - Inválido → mismo paso de campos con errores inline (`b.err.*`), foco al primer campo inválido.
   - Válido → paso de **confirmación**: encabezado `b3.confirm_heading_installments` / `b3.confirm_heading_charge` (`h4`, `tabindex="-1"`, **recibe el foco**), lista `<ul>` con `b3.confirm_point_*` aplicables, primario `b3.confirm_primary_installments` / `b3.confirm_primary_charge`, secundario `b3.confirm_secondary`. Los valores elegidos viajan como hidden fields.
4. **Confirmar.** `POST …/recurrence`. Éxito → `turbo_stream`:
   - reemplaza el contenido del drawer (re-render de `show`, ahora `msi_purchase` o pago 1 de un charge con su bloque de procedencia C1),
   - reemplaza la fila en la lista (`turbo_stream.replace @entry`, como hace `update`),
   - notice `b3.success_installments` / `b3.success_charge`,
   - foco al bloque de procedencia C1 (`tabindex="-1"`). Las cuotas nuevas del pasado aparecerán en la lista al refrescarla (no se insertan por stream: evita inconsistencias de orden/paginación).
5. **Cancel** (en campos o confirmación) → vuelve a cerrado sin guardar; foco al botón `Set up`.
6. **Esc** cierra el drawer como hoy (hotkey existente); no hay estado a medio guardar.

### 3.3 Estados

| Estado | Qué se ve | Foco / anuncio |
|---|---|---|
| Cerrado | Título, descripción, Set up | — |
| Campos | Radios + campos + resumen | Resumen polite |
| Validando (Review en vuelo) | Botón Review `disabled` + `aria-busy` en el frame | — |
| Error de campos | Mensajes inline | Foco al primer inválido |
| Confirmación | Encabezado + viñetas + 2 botones | Foco al encabezado |
| Guardando | Primario `disabled` (evita doble envío) | — |
| Error de bloque | `b3.err.transfer` / `already_linked` / `not_standard` / `generic` en caja con icono `alert-triangle`, `role="alert"`, arriba de la confirmación | Foco al mensaje. "Nothing was changed" es verdad: todo en una transacción de DB |
| Éxito | Drawer re-renderizado | Foco al bloque C1 + notice |

### 3.4 Server
- Ruta anidada: `resource :recurrence, only: %i[new create], module: :transactions` bajo `transactions` (o equivalente). `new` = validar y renderizar confirmación; `create` = `create_from_entry!`.
- `create_from_entry!` acepta solo `standard`, expense, no transfer, sin plan, cuenta manual activa (carry-over). Cada rechazo → `b3.err.*` específico con 422 dentro del frame; cualquier otra excepción → rollback + `b3.err.generic` + log. Nunca 500.

---

## 4. C1 — Filas generadas y drawer

### 4.1 Fila (lista de transacciones y feed de la cuenta)
- Línea secundaria bajo el nombre: icono (`aria-hidden`) + `c1.installment_line` / `c1.charge_line_end` / `c1.charge_line_open` / `c1.msi_purchase_line` + link `c1.view_plan` (nombre accesible "View plan for {name}", `data-turbo-frame="modal"`).
- La línea va **dentro** de la celda del nombre: el orden de lectura es nombre → procedencia → categoría → monto.
- El checkbox de selección masiva sigue habilitado (las acciones masivas que cambian kind deben respetar el bloqueo: ver §11).

### 4.2 Drawer de una fila generada
- Bloque informativo arriba de Overview, neutro (sin color de alerta): `c1.drawer_installment` / `c1.drawer_msi_purchase` / ~~`c1.drawer_charge`~~ *(removed, Victor 2026-10-08)* + `c1.drawer_link` (abre C3 en frame `modal` sobre el drawer, igual que "Open matcher" hoy). `tabindex="-1"` para recibir foco tras convertir (§3.2).
- **Overview:** en `installment` y `msi_purchase`, Amount y Nature `disabled` con ~~`c1.locked_amount_help`~~ *(removed, Victor 2026-10-08)* vía `aria-describedby`. Name, Date (salvo linked), Category siguen editables.
- **Settings:** se ocultan Exclude, One-time y "Transfer or Debt Payment?" en `installment` y `msi_purchase`. Delete usa copy propio (§7.4, §7.5).
- **Defensa (carry-over):** si llega igual un cambio de kind o un match de transferencia sobre filas bloqueadas:
  - `TransactionsController#update` → `render :show, status: :unprocessable_entity` con `c1.err.kind_locked` como alerta en Settings (y `flash.now[:alert]` en el stream). No `update!` que lance.
  - `TransferMatchesController#create` → re-render del modal del matcher con `c1.err.transfer_match_locked`, 422.

### 4.3 Notice de generación perezosa
~~`c1.generated_notice`~~ *(removed, Victor 2026-10-08)*: **no se muestra en v1**. La generación corre en un job después del request; no hay un momento natural para avisar sin polling. Las filas se explican solas (C1). Se deja en el copy por si un futuro push por Turbo Stream lo habilita.

---

## 5. C2 — Compromisos en la tarjeta de crédito

### 5.1 Ubicación y navegación
- `UI::AccountPage#tabs` para `CreditCard`: `[:activity, :recurring]`. Tab con label `c2.heading` ("Recurring payments"), no `humanize` (hace falta mapear label, ver §11). Activity sigue siendo el tab por defecto.
- URL directa: `account_path(card, tab: "recurring")` (el tab ya persiste en query param). Destino de links desde presupuesto y advertencias.
- El tab aparece **siempre** en tarjetas de crédito (aunque no haya planes) para que la función se descubra; muestra el vacío.

### 5.2 Orden de lectura (= orden visual)
`h2` `c2.heading` → `<dl>` cifras (`c2.kpi_committed_label`, `c2.kpi_left_label`, `c2.kpi_ends_label`) → `h3` Upcoming (**sin advertencia**, D13) → tablas (captions `c2.msi_caption`, `c2.charges_caption`) → `DS::Disclosure` `c2.past_disclosure`.

### 5.3 Upcoming (decisión pendiente del copy)
- **Horizonte:** el ciclo actual + los 2 siguientes (3 ciclos), o hasta el último pago si termina antes. Al final, link `c2.upcoming_more` al presupuesto del ciclo siguiente al horizonte → puente a presupuestos futuros (§9).
- Agrupado por fecha (`h4` por grupo, `c2.upcoming_group` + `c2.upcoming_group_total`), "Today"/"Tomorrow" cuando aplique. Filas en `<ul>`; ~~`c2.upcoming_last`~~ *(removed, Victor 2026-10-08)* como texto cuando es el último pago.
- Ocurrencias = `upcoming(through: fin del 3er ciclo)` de cada plan activo de la tarjeta; no incluye filas ya generadas (ya están en Activity).

### 5.4 Estados

| Estado | Contenido |
|---|---|
| Vacío (nunca hubo planes) | `c2.empty_title`, `c2.empty_body`, `c2.empty_cta` → `new_transaction_path(account_id:, nature: "outflow")` en frame `modal` |
| Solo charges | KPIs sin "Left on MSI" ni "Last MSI payment" (se omiten, no se muestran en 0); ~~`c2.summary_sentence_charges_only`~~ *(removed, Victor 2026-10-08)*; tabla de charges |
| MSI activos | Todo; tabla MSI ordenada por fecha de fin |
| Todo terminado | `c2.all_done_title`, ~~`c2.all_done_body`~~ *(removed, Victor 2026-10-08)*, disclosure de pasados abierto |
| Pasados presentes | Disclosure `c2.past_disclosure` cerrado con estados `c2.status_paid_off` / `c2.status_ended` / `c2.status_stopped` (icono + texto) |
| ~~Advertencia~~ | Removida de C2 (D13) |
| Plan con datos inválidos | Se omite de la vista y se registra en log; la sección nunca falla completa |

Sin estado de carga: todo es server-render (pocos planes, cálculo en memoria).

---

## 6. Advertencia de compromisos (B + A)

### 6.1 Regla
Para un ciclo C:
- `committed(C)` = filas ya generadas de planes con fecha en C (installments + ocurrencias de charge; **excluye** `msi_purchase`) **+** `upcoming` de planes activos con fecha en C. Familia completa, todas las cuentas.
- `budget_basis(C)` = `budgeted_spending` del presupuesto de C si está inicializado; si no (solo ciclos futuros), el del **último presupuesto inicializado** anterior a C (presupuesto de referencia), y se dice cuál (`w.ba.reference`). Ver pregunta a Victor.
- **Se advierte** si `committed(C) > budget_basis(C)`. Porcentaje = `committed / budget_basis × 100`, entero hacia arriba en estado de advertencia (nunca "100%" estando sobre el presupuesto).
- Sin `budget_basis` (nunca configuró un presupuesto) → no hay advertencia ni porcentaje; solo la línea neutra con monto.

### 6.2 Dónde y qué

| Superficie | Ciclos evaluados | Estado normal | Estado advertencia |
|---|---|---|---|
| Presupuesto (ciclo actual o futuro) | Ese ciclo | Línea neutra `c4.line` + `c4.line_percent` | Cabecera neutra con barra `bg-destructive` y `c4.line_percent` (> 100%) + `DS::Alert :warning` con solo `w.ba.title` + CTA `w.b.cta` → editar categorías de ese presupuesto (D13) |
| Tarjeta (C2) | — | **Ya no advierte (D13)** | — |
| Captura (B1, Installments) | Meses de las 3 primeras cuotas | Bloque de impacto neutro (§2.4b) | Bloque de impacto con `bi.title_over` en rojo (§2.4b) |

- Una sola advertencia por pantalla. En presupuesto convive con el aviso existente de sobre-asignación (`_over_allocation_warning`) porque son problemas distintos; si ambos están, el de sobre-asignación queda en el donut y el de compromisos en su bloque.
- Estructura: contenedor con icono `alert-triangle` (`aria-hidden`), título como `<strong>`/`h3`, cuerpo, CTA como link con texto. Sin `aria-live`, sin `role="alert"`: es contenido de página.
- Desaparece sola cuando se corrige (más presupuesto, Stop de un plan); no hay "descartar".

---

## 7. C3 — Ver, editar, detener plan; borrar

### 7.1 Diálogo del plan
- `RecurringTransactionsController#show` → `DS::Dialog` modal (frame `modal`), `reload_on_close: true` (al cerrar se refresca la pantalla de abajo: lista, C2 o presupuesto).
- Se abre desde: `c1.view_plan` (fila), `c1.drawer_link` (drawer, se apila sobre el drawer), `c2.row_action` (tablas C2), filas de compromisos en presupuesto (§9).
- Contenido: `c3.title` (h2 del diálogo), `c3.subtitle_*`, `c3.progress` (solo MSI), ~~`c3.edit_note`~~ *(removed, Victor 2026-10-08)*, campos editables, `c3.save`, zona inferior ~~`c3.stop_title`~~ *(removed, Victor 2026-10-08)* / ~~`c3.stop_body`~~ *(removed, Victor 2026-10-08)* / `c3.stop_button`.
- **Editables (v1):** Name y Category (ambos tipos); Amount (solo charge). **No editables:** total MSI, número de pagos, primera fecha (D12) → texto ~~`c3.schedule_locked_charge`~~ *(removed, Victor 2026-10-08)* / `c3.schedule_locked_installments` en lugar de campos.
- Foco al abrir: título del diálogo. Esc / X / click fuera cierran; el foco vuelve al disparador (comportamiento nativo de `<dialog>`; verificar en Safari). **Bug existente:** la X del header tiene `tabindex="-1"`; con Esc basta para teclado, pero se registra como deuda.

### 7.2 Guardar cambios
1. `c3.save` → si hay pagos ya generados, confirm (`c3.confirm_edit_*`; secundario `c3.confirm_edit_secondary` "Keep editing" con foco inicial; no es destructivo pero sí con consecuencias).
2. `PATCH` → éxito: el diálogo se re-renderiza (frame `modal`) con valores nuevos + notice ("Changes saved" ya existe en Maybe como patrón; si no, usar `c3.save` como confirmación visual, ver §10). Foco al título.
3. Error → 422 en el mismo diálogo, mensajes inline, foco al primer inválido.

### 7.3 Detener
1. `c3.stop_button` (outline-destructive) → confirm global extendido (D7): título `c3.confirm_stop_title`, cuerpo `c3.confirm_stop_body_charge` / `_installments`, primario `c3.confirm_stop_primary`, secundario `c3.confirm_stop_secondary` ("Keep it") **con foco inicial**.
2. Confirmado → `cancel!` → diálogo re-renderizado en estado Stopped (`c2.status_stopped`, sin campos editables, sin zona Stop) + notice `c3.stopped_notice`. Foco al título.
3. Plan ya detenido o completado: el diálogo es solo lectura (subtítulo con estado), sin Save ni Stop.

### 7.4 Borrar compra MSI (drawer, Settings)
- Subtítulo `c3.delete_msi_subtitle` en lugar de `delete_subtitle`.
- Confirm global extendido: `c3.delete_msi_title`, `c3.delete_msi_body` + ~~`c3.delete_msi_hint`~~ *(removed, Victor 2026-10-08)*, primario `c3.delete_msi_primary` (variante `destructive`, alta severidad), secundario `c3.delete_msi_secondary` con foco inicial.

### 7.5 Borrar una cuota o un pago
- Confirm global extendido con `c3.delete_occurrence_*` (variante según kind: "installment" / "payment"). Foco inicial en `Keep it`.
- Tras borrar: comportamiento actual (redirect `_top`) + notice existente. La cuota no se regenera (Phase A).

### 7.6 Checklist de nombres (para builder y reviewers)
- El botón que detiene **siempre** dice "Stop payments"; el estado **siempre** "Stopped"; el secundario de confirms destructivos **siempre** "Keep it".
- "Cancel" solo aparece en `b3.confirm_secondary`. `CustomConfirm` no debe caer en su `default_btn_text` ni en "Cancel" para estos diálogos.
- El nombre accesible del botón destructivo es su texto completo ("Delete purchase and installments"), no "Confirm".

---

## 8. C4 — Bloque de compromisos en presupuesto

- **Ubicación (D10):** columna izquierda de `budgets/show`, entre la tarjeta del donut y los tabs Budgeted/Actual. Mismo contenedor que las tarjetas vecinas (`bg-container rounded-xl`).
- **Solo** en el ciclo actual y en ciclos futuros. En ciclos pasados no se muestra (las cuotas ya son gasto real en Actual).
- **Contenido:**
  - Normal: icono `repeat` + `c4.line` + `c4.line_percent` + (~~`c4.line_split`~~ *(removed, Victor 2026-10-08)* si hay ambos tipos).
  - Advertencia: reemplaza la línea por el bloque B + A (§6).
  - `DS::Disclosure` (align left) con summary `c4.line_link` ("See details") que lista los pagos del ciclo agrupados por fecha con la **misma fila de Upcoming de C2** (nombre · procedencia · tarjeta · monto) + "View plan" (modal). Así funciona con varias tarjetas y en ciclos futuros sin salir de la pantalla. Cada nombre de tarjeta enlaza a `account_path(card, tab: "recurring")`.
  - Cero compromisos → el bloque no se renderiza (`c4.line_zero`: silencio = normal).
- **Coherencia:** el monto del bloque = suma de la lista del disclosure = suma de los grupos de Upcoming de C2 que caen en ese ciclo (por tarjeta). Test de paridad (§11).

---

## 9. Presupuestos futuros (alcance nuevo, decisión de Victor)

### 9.1 Objetivo
Antes de una compra a MSI, Victor abre los próximos ciclos y ve cuánto de cada uno ya está comprometido, por categoría, frente a lo presupuestado.

### 9.2 Cómo se llega (reuso de la navegación existente)
- **Chevron derecho** del header: hoy se apaga en el ciclo actual (`next_budget_param` devuelve nil si `current?`). Se habilita hasta el horizonte.
- **Picker de mes** (`_picker`): los meses futuros dentro del horizonte se vuelven links; el chevron de año siguiente se habilita si enero del año siguiente cae dentro del horizonte.
- **"Today"** (existente) regresa al ciclo actual.
- **Desde otras superficies:** CTA de la advertencia en C2 → `budget_path(ciclo en exceso)`; `c2.upcoming_more` → primer ciclo después del horizonte de Upcoming.
- **Horizonte:** 12 ciclos después del actual (constante `Budget::FUTURE_CYCLES_LIMIT`). Fuera del horizonte: chevron y meses deshabilitados, con nombre accesible y `title` `f.nav_next_disabled` en el chevron deshabilitado.
- **Accesibilidad de la navegación (deuda existente que esta feature toca):** los chevrons son `DS::Link variant: icon` sin nombre accesible y los deshabilitados son `<span>` mudos. Agregar `aria-label` `f.nav_previous` / `f.nav_next` con el nombre del ciclo destino; los deshabilitados con `aria-disabled="true"` y su razón.

### 9.3 Qué muestra un ciclo futuro
Misma pantalla, mismos componentes. Cambia la **fuente** del número de gasto y su **etiqueta**:

| Zona | Ciclo actual / pasado (hoy) | Ciclo futuro |
|---|---|---|
| Header | Nombre del ciclo | Nombre + `f.starts` ("Starts Nov 28") en `text-secondary`, para que nunca se confunda con el actual |
| Donut, centro | "Spent" + gasto real "of $budget" | `f.committed_label` ("Committed") + compromisos "of $budget"; sin presupuesto: compromisos + link "New budget" existente |
| Donut, segmentos | Gasto real por categoría | Compromiso por categoría + gris de no usado |
| Tabs | Budgeted / Actual | **Solo Budgeted** (no hay real en el futuro; el tab Actual no se renderiza) |
| Budgeted summary | Expected income con "earned"; Budgeted con "spent / left" | Expected income **sin** barra ni "earned"; Budgeted con barra de compromiso y `f.summary_committed` / "left" |
| Bloque de compromisos (§8) | Sí (actual) | Sí, con advertencia B + A contra ese ciclo |
| Fila de categoría | "left" / "over" + gasto real "from $budgeted" | Monto derecho = compromiso de la categoría + "from $budgeted"; línea izquierda = budgeted − committed ("left"/"over" con las mismas reglas); sin inicializar: "avg" existente + compromiso a la derecha |
| Drawer de categoría | "Recent Transactions" | Sección `f.drawer_section` ("Committed in this cycle") con las filas del ciclo de esa categoría (misma fila de Upcoming) o `f.drawer_empty` |
| Categorías sin categoría | Uncategorized existente | Compromisos de planes sin categoría caen en Uncategorized |

Subcategorías: el compromiso de un plan con subcategoría suma a su fila y a la del padre, igual que el gasto real hoy.

### 9.4 Qué es editable
- **Editable (como hoy):** Setup (`budgets/edit`: budgeted spending, expected income) y asignación por categoría (`budget_categories`). Planear = ajustar el presupuesto futuro sabiendo lo comprometido.
- **Solo lectura:** todos los montos "Committed" (derivados de planes). Para cambiarlos: el plan (C3) desde "View plan".
- **Autofill:** en un ciclo futuro, el toggle "Autofill budget from previous month" toma como fuente el **último presupuesto inicializado anterior** (normalmente el actual), no estrictamente el ciclo inmediato anterior (que suele estar vacío). El copy existente ya interpola el nombre de la fuente ("Copies October 2026's…"). Sigue apagado por defecto (consistencia con Maybe).
- Visitar un ciclo futuro lo crea con `find_or_bootstrap` (comportamiento actual, inocuo: registro vacío hasta que se configure). Cuando ese ciclo se vuelve el actual, lo planeado **es** su presupuesto: continuidad sin migrar nada.

### 9.5 Estados

| Estado | Qué se ve |
|---|---|
| Futuro, sin presupuesto, sin compromisos | Donut gris "$0" + "New budget"; categorías con "avg"; sin bloque de compromisos; `f.empty_title` / ~~`f.empty_body`~~ *(removed, Victor 2026-10-08)* en el lugar del bloque, neutro |
| Futuro, sin presupuesto, con compromisos | Donut con compromisos; bloque de compromisos con % y advertencia contra el presupuesto de referencia (`w.ba.reference`) |
| Futuro, con presupuesto, bajo el límite | Todo neutro; `c4.line` + % |
| Futuro, con presupuesto, sobre el límite | Advertencia B + A en el bloque; filas de categoría "over" con las reglas actuales |
| Límite del horizonte | Chevron derecho deshabilitado con razón |
| Ciclo actual | Sin cambios salvo el bloque de compromisos (§8) |
| Error al calcular compromisos | Se omite el bloque y se registra; el presupuesto sigue usable (nunca 500) |

### 9.6 Teclado y lector
- Navegación entre ciclos por links reales (Tab + Enter); cada visita es una página: el `<title>` y el `h1`/nombre del ciclo deben incluir el nombre del ciclo para que el lector confirme dónde está.
- "Committed" siempre como texto; nunca distinguir futuro de actual solo por color o opacidad.

---

## 10. Strings nuevos o faltantes — **reviewed** (content-writer, 2ª pasada 2026-10-08)

Texto final en el copy doc (`docs/designpowers/content/2026-10-08-pagos-recurrentes-msi-copy.md`). Esta tabla solo mapea borrador → id final.

| Borrador (id) | Id final | Estado | Cambio |
|---|---|---|---|
| `w.ba.title` | `w.ba.title` (§6) | reviewed | Empieza por el concepto: "Recurring payments are {$1,700.00} over your {December 2026} budget" |
| `w.ba.body` | `w.ba.body` (§6) | reviewed | Sin cambios |
| `w.ba.body_card` | `w.ba.body_card` (§6) | reviewed | Sin cambios |
| `w.ba.reference` | `w.ba.reference` (§6) | reviewed | Sin cambios (texto de Victor) |
| `w.b.multi` | `w.b.multi` (§6) | reviewed | "{2} upcoming budgets are over. The first is {December 2026}." |
| `c4.line_percent` | `c4.line_percent` + `c4.line_percent_reference` (§5.2) | reviewed | Variante nueva para mes futuro comparado con el último presupuesto |
| `b2.summary_unavailable` | `b2.summary_unavailable` (§2.2) | reviewed | Sin cambios |
| `b3.review` | `b3.review` (§3.1) | reviewed | Nombre accesible "Review recurring payment" |
| `c2.upcoming_more` | `c2.upcoming_more` (§5.1) | reviewed | Sin cambios |
| `c3.schedule_locked` | ~~`c3.schedule_locked_charge`~~ *(removed, Victor 2026-10-08)* / `c3.schedule_locked_installments` (§7.1) | reviewed | Partido: en MSI "Stop" no sirve (deja la deuda sin cuotas); el camino es borrar y capturar de nuevo |
| `c3.saved_notice` | `c3.saved_notice` (§7.1) | reviewed | "Changes saved. Past payments didn't change." |
| `f.starts` | `f.starts` (§5.3) | reviewed | Con año si no es el actual |
| `f.committed_label` | `f.committed_label` (§5.3) | reviewed | Sin cambios |
| `f.summary_committed` | `f.summary_committed` (§5.3) | reviewed | Sin cambios |
| `f.empty_title` | `f.empty_title` (§5.3) | reviewed | Sin cambios |
| ~~`f.empty_body`~~ *(removed, Victor 2026-10-08)* | ~~`f.empty_body`~~ *(removed, Victor 2026-10-08)* (§5.3) | reviewed | Rango explícito "from {Nov 28} to {Dec 27}" |
| `f.drawer_section` | `f.drawer_section` (§5.3) | reviewed | "Committed in {December 2026}": sin la palabra "cycle" |
| `f.drawer_empty` | `f.drawer_empty` (§5.3) | reviewed | Nombre del mes en lugar de "this cycle" |
| `f.nav_previous` / `f.nav_next` | `f.nav_previous` / `f.nav_next` + `f.nav_next_disabled` (§5.3) | reviewed | Deshabilitado con razón en el nombre accesible |
| ~~`f.horizon`~~ *(removed, Victor 2026-10-08)* | ~~`f.horizon`~~ *(removed, Victor 2026-10-08)* (§5.3) | reviewed | Sin cambios |

Nuevos del copy (no estaban en el borrador): `f.page_title`, `f.category_committed`, ~~`f.readonly_help`~~ *(removed, Victor 2026-10-08)*, `f.autofill_title`, ~~`f.autofill_note`~~ *(removed, Victor 2026-10-08)*, `c1.locked_amount_help_installment`, `c1.locked_amount_help_msi`.

Sin uso / descartados: ~~`b1.first_payment_help_charge`~~ *(removed, Victor 2026-10-08)* (D3), ~~`c1.generated_notice`~~ *(removed, Victor 2026-10-08)* (fuera de v1), `w.a.*`, `w.c.*`, `w.b.title`, `w.b.body`, ~~`c1.locked_amount_help`~~ *(removed, Victor 2026-10-08)* (partido en dos).

Ejemplos de fecha corregidos en todo el copy doc: los meses de presupuesto van del 28 al 27 y su nombre sale de `Budget#name` (el `Nov 28 – Dec 27` es "December 2026"). En la UI no se usa la palabra "cycle".

---

## 11. Implicaciones para los planes de código (Fases B y C)

### Fase B — Captura
1. **Preview:** `RecurringTransactionsController#preview` (GET, render de parcial en frame `recurring_preview`). Modelo: `RecurringTransaction#preview_summary` o métodos que ya existen sobre una instancia no guardada (`occurrence_amount`, `occurrence_date`, `end_date`) + `past_due_count(as_of:)`. Validación sin guardar (`valid?`) para mapear `b.err.*`.
2. **Create con plan:** `TransactionsController#create` envuelve entry + `create_from_entry!` en una transacción; params `recurrence[...]`; 422 con disclosure abierto y `autofocus` al primer inválido.
3. **Conversión:** `Transactions::RecurrencesController` (`new` = validar + confirmación, `create` = convertir) con respuestas en frame y `turbo_stream` en éxito (drawer + fila + notice).
4. **Guardas de `create_from_entry!`** (carry-over): solo `standard`, expense, no transfer, sin plan, cuenta manual activa; errores con mensajes `b3.err.*` / `b.err.*` (reemplazar mensajes de AR, p. ej. `installments_require_credit_card`).
5. **Validaciones nuevas en el modelo:** `start_date >= fecha de la compra` (`b.err.first_payment_before_purchase`), monto por cuota ≥ 0.01 (`b.err.amount_too_small`), `total_payments ≤ 48` para installments.
6. **Stimulus** `recurring-form` (§2.7). Sin dependencias nuevas.
7. **Filas bloqueadas (carry-over):** ocultar One-time/Exclude/matcher en `installment`/`msi_purchase`; `TransactionsController#update` y `TransferMatchesController#create` devuelven 422 con `c1.err.*` en vez de lanzar. Revisar también `bulk_updates` (no permitir cambiar kind de filas bloqueadas en bloque).
8. **Fecha "hoy" (carry-over):** generador y preview usan la misma fecha de la familia (timezone de la familia, no del servidor). Un helper único (`family.today` o similar).
9. **Job robusto (carry-over):** un plan inválido no detiene `GenerateRecurringTransactionsJob` (rescue por plan + log). Limitar planes a cuentas manuales activas.
10. **`Category#replace_and_destroy!`** mueve la categoría de los planes (carry-over).
11. **Notificaciones:** `#notification-tray` con `role="status"` (`aria-live="polite"`) en `_htmldoc`. Revisar que el auto-dismiss dé tiempo de lectura (WCAG 2.2.1); si no, pausar en hover/focus.

### Fase C — Ver y gestionar
12. **Confirm global extendido (D7):** `CustomConfirm` acepta `cancel_text:`; `_confirm_dialog` renderiza un botón secundario (`value="cancel"`) con `autofocus` cuando `destructive: true` (el de confirmar pierde `autofocus` en ese caso) y `aria-describedby` al cuerpo. Fábricas: `CustomConfirm.for_plan_stop(plan)`, `.for_msi_purchase_deletion(entry)`, `.for_occurrence_deletion(entry)`.
13. **C1:** helper/partial de procedencia en `transactions/_transaction` y en `transactions/show` (bloque arriba de Overview; Amount/Nature disabled en kinds bloqueados).
14. **C2:** `UI::AccountPage#tabs` para `CreditCard` → `[:activity, :recurring]`; mapa de labels (`recurring` → "Recurring payments") en vez de `humanize`; parcial `credit_cards/tabs/_recurring`. Modelo en la cuenta/tarjeta: `account.recurring_commitments` (o métodos en `CreditCard`): `committed_per_month`, `msi_left` (suma de `remaining_balance`), `last_msi_payment_date`, `upcoming_occurrences(through:)`, `commitment_step` (para la 2ª oración de ~~`c2.summary_sentence`~~ *(removed, Victor 2026-10-08)*).
15. **C3:** `RecurringTransactionsController` (`show`, `update`, `stop` como acción member `PATCH`), `<dialog>` existente con `reload_on_close: true`. Sin edición de schedule (D12).
16. **Compromisos por ciclo (C4 + advertencia + futuros):** métodos en `Budget`:
    - `committed_spending` y `committed_spending_for(category)` (incluye subcategorías → padre),
    - `commitments` (lista de ocurrencias del ciclo: generadas con fecha en el ciclo + `upcoming` hasta `end_date` filtrado por `>= start_date`; excluye `msi_purchase`, planes cancelados),
    - `budget_basis` (propio si `initialized?`; si no, último presupuesto inicializado anterior), `commitments_percent`, `commitments_over_budget?`.
    - ~~En `Family`: `budget_cycles_over_commitment(from:, count:)` para la advertencia de C2~~ (D13: C2 ya no advierte). En su lugar, el preview de B1 calcula `total(C)` para los meses de las 3 primeras cuotas con los mismos `committed(C)` / `budget_basis(C)` (§2.4b).
    - Moneda: v1 asume moneda de la familia = moneda de las cuentas con planes; si difieren, convertir con `Money#exchange_to` (marcar en el plan de código).
17. **Presupuestos futuros:**
    - `Budget.budget_date_valid?`: permitir `end_date <= current_cycle_end + FUTURE_CYCLES_LIMIT ciclos` (calcular el fin del ciclo N con `cycle_range_containing`).
    - `Budget#next_budget_param`: quitar `return nil if current?`; usar el límite.
    - `Budget#future?` (`start_date > Date.current` en fecha de familia).
    - `Budget#previous_budget` para autofill en futuros → `latest_initialized_budget_before` (nuevo) sin romper el comportamiento actual en ciclos actuales/pasados.
    - `to_donut_segments_json` y las vistas toman "committed" cuando `future?` (un solo punto de decisión en el modelo, p. ej. `budget.displayed_spending_for(bc)`), no `if` dispersos en vistas.
    - `budget_categories/show` (drawer) con sección de compromisos cuando `future?`.
    - `_picker` y `_budget_header` respetan el nuevo límite y agregan `aria-label`.
18. **Tests de paridad:** monto de C4 = suma de su lista = suma de Upcoming de C2 en ese ciclo; compromiso de un ciclo futuro = suma de `upcoming` de los planes activos en ese rango; `budget_date_valid?` acepta ciclo actual + 12 y rechaza + 13.

### Deuda registrada (fuera de alcance, para el design-debt-tracker)
- `DS::Tabs` sin roles ARIA (`tablist`/`tab`/`aria-selected`).
- X del header de `DS::Dialog` con `tabindex="-1"`.
- Chevrons de presupuesto sin nombre accesible (se arregla aquí para lo tocado).
- `_confirm_dialog` con foco inicial en el botón destructivo (se arregla con D7).
