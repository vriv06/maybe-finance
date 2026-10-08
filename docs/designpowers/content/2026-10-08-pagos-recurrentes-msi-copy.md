# Copy: Pagos recurrentes y cuotas

_2026-10-08 · content-writer · 3ª pasada (dirección de Victor tras revisar mockups): sin "MSI" en la UI, solo el texto indispensable, "Doesn't repeat" siempre por defecto._
_2026-10-08 · design-lead · sincronizado con el canvas de Victor (https://claude.ai/artifact/1gVBYF2NsiBFS45AoPC1JT): cambios marcados "Victor canvas edit 2026-10-08"; detalle en §13._

Strings de interfaz en **inglés** (hardcode, sin i18n). Notas en español. **Las tablas "Kept" son la fuente de verdad.** Si un id no aparece en ellas, no existe: ver §11 (changelog de removidos).

---

## 0. Reglas

### 0.1 Filtro de Victor (aplica a todo string nuevo)
Un string se queda solo si es: un label, una cifra esencial, un mensaje de error, una consecuencia destructiva, o lo mínimo para explicar una fila generada o deuda vs gasto donde de otro modo habría confusión. Ante la duda, se quita antes de reescribirlo. Nada de textos de ayuda tipo "Usually…".

### 0.2 Voz
Sentence case, voz activa, segunda persona. Sin exclamaciones, sin regaños, sin jerga ("deferred", "diferimiento", "MSI"). Oraciones ≤ 15 palabras. Nivel de lectura: grado ≤ 6 en todo el doc.

### 0.3 Vocabulario

| Concepto | En la UI | Nunca |
|---|---|---|
| `RecurringTransaction` | Recurring payment | rule, schedule, subscription |
| Tipo `charge` | Monthly charge | Subscription |
| Tipo `installments` | **Installments** | ~~Installments (MSI)~~, MSI, months without interest, `<abbr>` |
| Fila `installment` | Installment {2} of {6} | cuota, 2/6 |
| Ocurrencia de charge con fin | Payment {3} of {12} | |
| Fila `msi_purchase` | Paid in {6} installments (línea de procedencia) | MSI purchase |
| Detener (`cancel!`) | Stop payments / Stopped | Cancel (solo existe `b3.confirm_secondary`) |
| `completed` | Paid off (installments) / Ended (charge) | Completed |
| Secundario de confirms destructivos | Keep it | Cancel |
| Mes de presupuesto | Nombre de `Budget#name` ("December 2026") | cycle |

"MSI" no aparece en ningún string de UI. Solo puede verse si es dato del usuario (p. ej. el nombre que él le puso a una transacción).

### 0.4 Formatos
- **Dinero:** `format_money` server-side (el resumen B2 también se calcula en servidor, D4 de interacción). `tabular-nums`.
- **Fechas:** `Mar 27, 2027` (`%b %-d, %Y`); en el año actual `Oct 27`; mes de fin `Mar 2027`. Al lector, mes completo vía `<time datetime>`.
- **Meses de presupuesto:** van del 28 al 27 con `cycle_end_day = 27`; etiquetas de `cycle_range_containing` / `Budget#name`. Nunca rangos a mano.
- **Plurales:** todo `{n}` con singular/plural (`pluralize`).
- **Separador `·`:** `aria-hidden="true"`; en texto accesible, coma.

### 0.5 Iconos (`icon` helper, siempre con texto, `aria-hidden`)
`repeat` monthly charge · `credit-card` installments · `calendar-clock` Upcoming · `alert-triangle` advertencia · `check` paid off/ended.

---

## 1. Conteo antes / después

| Superficie | Antes (2ª pasada) | Después | Removidos |
|---|---|---|---|
| B1 Campos | 17 | 10 | 7 |
| B2 Resumen | 7 | 6 | 1 |
| B Errores | 8 | 8 | 0 (acortados) |
| B3 Convertir | 22 | 16 | 6 |
| C1 Filas generadas | 14 | 12 | 2 |
| C2 Tarjeta | 37 | 31 | 6 |
| C4 Presupuesto | 6 | 5 | 1 |
| F Presupuestos futuros | 16 | 12 | 4 |
| W Advertencia | 6 | 6 | 0 (acortados) |
| C3 Plan / borrar | 32 | 27 | 5 |
| **Total** | **165** | **133** | **32** |

Además, casi todos los que se quedaron se acortaron: se quitaron segundas oraciones y "MSI".

---

## 2. B1 — Campos en "New transaction" (Kept)

| id | String | Contexto | A11y |
|---|---|---|---|
| `b1.disclosure_title` | Recurring payment | `DS::Disclosure` propio, cerrado | `<summary>` |
| `b1.type_label` | Repeat | `<legend>` del grupo de radios | `<fieldset>` |
| `b1.type_none` | Doesn't repeat | **Siempre seleccionado por defecto**, en todas las cuentas y al reabrir el form. Al cambiar a una cuenta sin tarjeta con Installments elegido, vuelve aquí | |
| `b1.type_charge` | Monthly charge | Radio | |
| `b1.type_installments` | Installments | Radio, solo si la cuenta es tarjeta de crédito; va al final | |
| `b1.payments_label_installments` | Number of installments | Number, 2–48 | `inputmode="numeric"` |
| `b1.payments_label_charge` | Ends after | Number opcional (charge). Vacío = sin fin; el resumen lo dice ("no end date") | Sufijo dentro del `<label>` |
| `b1.payments_suffix` | payments | Sufijo del anterior | Parte del label |
| `b1.first_payment_label` | First payment | Date (solo Installments); por defecto fecha de compra + 1 mes | |
| `b1.submit` | (botón existente, sin cambio) | | |

## 3. B2 — Resumen en vivo (Kept)

`role="status"`, `aria-atomic`, `aria-busy` al recalcular, debounce 500 ms. Si falta un dato, la región queda **vacía** (sin texto).

| id | String | Contexto |
|---|---|---|
| `b2.summary_installments` | {6} installments of {$1,666.67} · last on {Mar 27, 2027} | Cuotas iguales. **Visual en 2 líneas**: línea 1 = cifras, línea 2 = `b2.line2_last_on`; el `·` queda solo en el texto accesible (como coma) |
| `b2.line2_last_on` | Last on {Oct 8, 2027} | Línea 2 del resumen, mayúscula inicial _(Victor canvas edit 2026-10-08)_ |
| `b2.line2_last_one` | Last one {$1,666.65} on {Mar 27, 2027} | Línea 2 de `_uneven`; mayúscula unificada por design-lead siguiendo la edición de Victor |
| `b2.line2_charge_end` | {12} payments · last on {Sep 15, 2027} | Línea 2 de `_charge_end` (empieza con cifra; sin cambio) |
| `b2.line2_no_end` | No end date | Línea 2 de `_charge_open`; mayúscula unificada por design-lead |
| `b2.summary_installments_uneven` | {6} installments of {$1,666.67} · last one {$1,666.65} on {Mar 27, 2027} | Solo si la última difiere por redondeo |
| `b2.summary_charge_end` | {$199.00} every month · {12} payments · last on {Sep 15, 2027} | Charge con fin |
| `b2.summary_charge_open` | {$199.00} every month · no end date | Charge sin fin |
| `b2.summary_past_due` | {3} already due. They'll be added with their original dates. | Línea extra si hay fechas pasadas |
| `b2.summary_unavailable` | We couldn't calculate this. You can still save. | Falló el preview |

## 4. B — Errores de validación (Kept, acortados)

Junto al campo, `aria-invalid` + `aria-describedby`. Al enviar, foco al primero.

| id | String | Cuándo |
|---|---|---|
| `b.err.payments_range_installments` | Enter 2 to 48 installments. | Fuera de rango o no entero |
| `b.err.payments_range_charge` | Enter a whole number, or leave it empty. | Charge inválido |
| `b.err.first_payment_missing` | Choose a date for the first payment. | Vacío |
| `b.err.first_payment_before_purchase` | The first payment can't be before {Oct 8, 2026}. | Antes de la compra |
| `b.err.expense_only` | Only expenses can repeat. | Defensa server-side |
| `b.err.installments_credit_only` | Installments only work on credit cards. | Defensa; también nota al cambiar de cuenta |
| `b.err.account_not_manual` | Only manual accounts can have recurring payments. | Cuenta conectada o inactiva |
| `b.err.amount_too_small` | Too small to split into {6} installments. Use fewer. | Cuota < 0.01 |

## 5. B3 — Convertir desde el drawer (Kept)

| id | String | Contexto | A11y |
|---|---|---|---|
| `b3.title` | Recurring payment | `h4` en Settings | |
| `b3.status_one_time` | One time | Estado bajo el título cuando la transacción no repite _(Victor canvas edit 2026-10-08)_ | |
| `b3.status_charge` | Monthly charge | Estado cuando ya es pago de un charge _(Victor canvas edit 2026-10-08)_ | |
| `b3.status_installments` | Installments · {3} of {12} | Estado cuando es cuota/compra en cuotas _(Victor canvas edit 2026-10-08)_ | "Installments, 3 of 12" |
| `b3.button` | Edit | Botón `outline` con `pencil`; abre los campos _(Victor canvas edit 2026-10-08)_ (antes "Set up") | Nombre accesible "Edit recurring payment" |
| `b3.review` | Review | Primario del paso de campos | Nombre accesible "Review recurring payment" |
| `b3.confirm_heading_installments` | Split {$10,000.00} into {6} installments | `h4` de confirmación, recibe foco | |
| `b3.confirm_heading_charge` | Repeat {$199.00} every month | Idem | |
| `b3.confirm_point_debt` | Your card balance stays the same. | Solo installments. Evita el miedo a duplicar deuda | |
| `b3.confirm_point_backfill` | Adds {3} past {installments/payments} with their original dates. Past budgets will change. | Solo si hay pasadas. Consecuencia | |
| `b3.confirm_primary_installments` | Split into {6} installments | | |
| `b3.confirm_primary_charge` | Start monthly charge | | |
| `b3.confirm_secondary` | Cancel | Cierra sin guardar. Único "Cancel" de la feature | |
| `b3.success_installments` | Split into {6} installments. | Notice | `role="status"` |
| `b3.success_charge` | Monthly charge started. | Notice | |
| `b3.err.transfer` | Transfers can't repeat. | | `role="alert"` |
| `b3.err.already_linked` | This is already part of a recurring payment. | | |
| `b3.err.not_standard` | Turn off One-time Expense to set this up. | También como descripción del bloque en filas `one_time` (sin botón) | |
| `b3.err.generic` | We couldn't set this up. Nothing changed. Try again. | Rollback, nunca 500 | |

## 6. C1 — Filas generadas (Kept)

| id | String | Contexto | A11y |
|---|---|---|---|
| `c1.installment_line` | Installment {2} of {6} | Línea bajo el nombre, `credit-card` | |
| `c1.charge_line_end` | Payment {3} of {12} | `repeat` | |
| `c1.charge_line_open` | Monthly charge | `repeat` | |
| `c1.msi_purchase_line` | Paid in {6} installments | Fila `msi_purchase`, `credit-card` | |
| `c1.view_plan` | View plan | Link al final de la línea | "View plan for {name}" |
| `c1.drawer_msi_purchase` | Adds to your card balance, not to spending. Each installment counts as spending. | Drawer de `msi_purchase`. Deuda vs gasto | |
| `c1.drawer_link` | View plan | Botón en el drawer | "View plan for {name}" |
| `c1.locked_amount_help_installment` | Set by the plan. | Junto al monto deshabilitado | `aria-describedby`; un campo deshabilitado necesita razón |
| `c1.locked_amount_help_msi` | To change it, delete this purchase and add it again. | Junto al monto deshabilitado | Idem; único camino posible en v1 |
| `c1.err.kind_locked` | This is part of a recurring payment, so it can't be one-time. | Defensa | |
| `c1.err.transfer_match_locked` | This is part of a recurring payment, so it can't be a transfer. | Defensa | |

Toggles "One-time Expense" y "Exclude": ocultos en `installment` y `msi_purchase`.

## 7. C2 — Tab en la tarjeta de crédito (Kept)

| id | String | Contexto | A11y |
|---|---|---|---|
| `c2.heading` | Recurring payments | Label del tab y `h2` | |
| `c2.kpi_committed_label` | Committed per month | Cifra principal | `<dl>` |
| `c2.kpi_left_label` | Left on installments | Cifra 2; se omite si no hay cuotas activas | |
| `c2.kpi_ends_label` | Last installment | Cifra 3; se omite si no hay cuotas activas | |
| `c2.kpi_ends_value` | {Mar 2027} | Formato | "March 2027" |
| `c2.upcoming_heading` | Upcoming | `h3`, `calendar-clock` | |
| `c2.upcoming_group` | {Oct 27} / Today / Tomorrow | `h4` por fecha | |
| `c2.upcoming_group_total` | {$4,850.00} | Total del grupo | "Total for October 27: $4,850.00" |
| `c2.upcoming_row` | {MacBook Air} · Installment {3} of {6} · {$1,666.67} | Fila | |
| `c2.upcoming_row_charge` | {Netflix} · Monthly charge · {$299.00} | Fila | |
| `c2.upcoming_more` | See later months | Link al presupuesto del primer mes fuera del horizonte | "See later months in your budget" |
| `c2.msi_caption` | Installments | Caption tabla 1 | `<caption>` |
| `c2.msi_col_name` | Purchase | | `<th scope="col">` |
| `c2.msi_col_monthly` | Per month | | |
| `c2.msi_col_left_count` | Payments left | Valor "{4} of {6}" | |
| `c2.msi_col_left_amount` | Left to pay | | |
| `c2.msi_col_ends` | Ends | | |
| `c2.charges_caption` | Monthly charges | Caption tabla 2 | |
| `c2.charges_col_name` | Name | | |
| `c2.charges_col_amount` | Per month | | |
| `c2.charges_col_next` | Next payment | | |
| `c2.charges_col_ends` | Ends | Valor sin fin: "No end date" | |
| `c2.row_action` | View plan | Por fila | "View plan for {name}" |
| `c2.empty_title` | No recurring payments on this card | Vacío | |
| `c2.empty_body` | Add one when you create a transaction. | Vacío: dice dónde se crea (no es obvio) | |
| `c2.empty_cta` | New transaction | | |
| `c2.all_done_title` | Nothing left to pay | Todo terminado | |
| `c2.past_disclosure` | Past plans ({3}) | Disclosure | |
| `c2.status_paid_off` | Paid off {Jul 14, 2026} | `check` + texto | |
| `c2.status_ended` | Ended {Sep 15, 2027} | | |
| `c2.status_stopped` | Stopped {Nov 2, 2026} | | |

## 8. C4 — Bloque en presupuesto (Kept)

| id | String | Contexto | A11y |
|---|---|---|---|
| `c4.line` | {$4,850.00} committed to recurring payments | Línea principal, `repeat` | |
| `c4.line_percent` | {45%} of your budget | Siempre que haya base, también > 100% ("123% of your budget") _(Victor canvas edit 2026-10-08)_ | "…, 45% of your budget" |
| `c4.line_percent_reference` | {45%} of your {October 2026} budget | Mes futuro sin presupuesto propio; seguido de `w.ba.reference` | |
| `c4.line_link` | See details | Summary del disclosure con la lista del mes | "See recurring payment details" |
| `c4.line_zero` | (regla, sin string) | Sin compromisos: el bloque no se muestra | |

## 9. F — Meses futuros en presupuesto (Kept)

| id | String | Contexto | A11y |
|---|---|---|---|
| `f.page_title` | {December 2026} budget | `<title>` | Confirma dónde está tras navegar |
| `f.starts` | Starts {Nov 28} | Junto al nombre, solo en meses futuros; con año si no es el actual | Distingue futuro sin color |
| `f.nav_previous` | Previous budget: {November 2026} | `aria-label` chevron | |
| `f.nav_next` | Next budget: {January 2027} | `aria-label` chevron | |
| `f.nav_next_disabled` | You can plan up to 12 months ahead. | `aria-label` + `title` del chevron deshabilitado | `aria-disabled="true"` |
| `f.committed_label` | Committed | Centro del donut (en lugar de "Spent") | "Committed: $X of $Y" |
| `f.summary_committed` | {$4,850.00} committed | Budgeted summary (en lugar de "spent") | |
| `f.category_committed` | {$1,200.00} committed | Monto de la fila de categoría | "$1,200.00 committed from $3,000.00" |
| `f.drawer_section` | Committed in {December 2026} | Sección del drawer de categoría | |
| `f.drawer_empty` | Nothing committed in this category. | | |
| `f.empty_title` | Nothing committed for {December 2026} yet | En lugar del bloque C4 | |
| `f.autofill_title` | Start from your {October 2026} budget | Título del toggle cuando la fuente no es el mes anterior | |
| `f.autofill_body` | Copies {October 2026}'s budget | Cuerpo del toggle junto a `f.autofill_title` (reemplaza el cuerpo existente solo en ese caso) _(Victor canvas edit 2026-10-08)_ | |

## 10. W — Advertencia B + A (Kept, acortada)

Se muestra cuando lo comprometido en el mes supera lo presupuestado para gasto. `alert-triangle` + texto, `text-warning`. Sin `aria-live`. El CTA reemplaza la oración "qué hacer".

| id | String | Contexto |
|---|---|---|
| `w.ba.title` | Recurring payments are {$1,700.00} over your {December 2026} budget | Título del Alert en C4 (único texto del Alert + CTA) |
| `w.ba.reference` | Compared with your {October 2026} budget. Set up {December 2026} to use its own. | Solo en C4 **neutro** de un mes futuro sin presupuesto propio; ya no va dentro de la advertencia _(Victor canvas edit 2026-10-08)_ |
| `w.b.cta` | Review budget | Link; nombre accesible "Review December 2026 budget" |

## 10b. BI — Impacto en presupuesto al capturar cuotas (nuevo) _(Victor canvas edit 2026-10-08)_

Bloque bajo el resumen B2 cuando el tipo es Installments. Muestra los meses de presupuesto de las próximas 3 cuotas con la compra incluida.

| id | String | Contexto | A11y |
|---|---|---|---|
| `bi.title_over` | This puts {November 2026} {$301.00} over budget | Cabecera si algún mes se pasa (el primero que se pasa). Rojo + `alert-triangle` | Se anuncia (añadido al resumen B2, ver interacción) |
| `bi.title_over_multi` | This puts {2} budgets over. The first is {November 2026}. | **Propuesto por design-lead** (no está en el canvas): si se pasa más de un mes. Pendiente content-writer | |
| `bi.subtitle` | Budget impact of the next {3} installments | Subtítulo; sin exceso es la única cabecera. Plural: "next installment" si queda 1 | |
| `bi.month_over` | {$301.00} over | Derecha de la fila del mes que se pasa | |
| `bi.month_percent` | {98%} of budget | Derecha de la fila que no se pasa | |
| `bi.month_detail` | {$7,801.00} of {$7,500.00} budgeted | Línea bajo la barra | "$7,801.00 of $7,500.00 budgeted" |
| `bi.legend_committed` | Already committed | Leyenda | Leyenda `aria-hidden` (las barras también) |
| `bi.legend_purchase` | This purchase | Leyenda | |
| `bi.legend_budget` | Budget | Leyenda (marca vertical) | |
| `bi.reference` | Months without a budget use your {October 2026} budget. | **Propuesto por design-lead** (no está en el canvas): una vez bajo la lista si algún mes usa presupuesto de referencia. Pendiente content-writer | |

## 11. C3 — Plan, detener, borrar (Kept)

| id | String | Contexto |
|---|---|---|
| `c3.title` | {MacBook Air} | `h2` del diálogo |
| `c3.subtitle_installments` | {12} installments of {$1,250.00} · {Active} | |
| `c3.subtitle_charge` | Monthly charge · {$299.00} · {Active} | |
| `c3.progress` | {2} of {12} paid · {$12,500.00} left | Solo installments |
| `c3.schedule_locked_installments` | To change installments or dates, delete the purchase and add it again. | En lugar de campos de fecha/número (installments) |
| `c3.save` | Save changes | |
| `c3.saved_notice` | Changes saved. | Notice |
| `c3.stop_button` | Stop payments | `outline-destructive`, sin título ni descripción encima |
| `c3.confirm_edit_title` | Save changes to future payments? | Solo si hay pagos ya generados |
| `c3.confirm_edit_body` | The {2} payments already added won't change. | |
| `c3.confirm_edit_primary` | Save changes | |
| `c3.confirm_edit_secondary` | Keep editing | Foco inicial |
| `c3.confirm_stop_title` | Stop {Netflix}? | |
| `c3.confirm_stop_body_charge` | No new payments will be added. The {5} already added stay. | |
| `c3.confirm_stop_body_installments` | The {10} installments left ({$12,500.00}) won't count in future budgets. The full purchase stays on your card balance. | Consecuencia deuda vs gasto |
| `c3.confirm_stop_primary` | Stop payments | |
| `c3.confirm_stop_secondary` | Keep it | Foco inicial |
| `c3.stopped_notice` | {Netflix} stopped. | Notice |
| `c3.delete_msi_title` | Delete this purchase and its installments? | |
| `c3.delete_msi_body` | All {12} installments will be deleted, including the {2} already added. Your card balance and past budgets will change. This can't be undone. | |
| `c3.delete_msi_primary` | Delete | `destructive` _(Victor canvas edit 2026-10-08)_ (antes "Delete purchase and installments"; el título dice qué se borra) |
| `c3.delete_msi_secondary` | Keep it | Foco inicial |
| `c3.delete_msi_subtitle` | Also deletes its {12} installments. | Reemplaza `delete_subtitle` en Settings del drawer |
| `c3.delete_occurrence_title` | Delete this installment? / Delete this payment? | |
| `c3.delete_occurrence_body` | It won't be added again. Your {November 2026} budget will change. | |
| `c3.delete_occurrence_primary` | Delete installment / Delete payment | |
| `c3.delete_occurrence_secondary` | Keep it | Foco inicial |

A11y de diálogos: foco inicial en el botón seguro; foco de vuelta al disparador; destructivo reconocible por texto; `aria-describedby` al cuerpo.

---

## 12. Changelog — removidos (Victor, 2026-10-08)

Los builders no deben buscar estos ids: **no existen**. Donde una superficie los usaba, no se pone nada en su lugar salvo lo indicado.

| id | Motivo |
|---|---|
| `b1.type_help_installments` | Ayuda; la confirmación y el drawer explican deuda vs gasto |
| `b1.type_help_charge` | Ayuda obvia |
| `b1.payments_help_installments` | "Usually 3, 6…" señalado por Victor |
| `b1.payments_help_charge` | El resumen ya dice "no end date" |
| `b1.first_payment_help_installments` | "Usually one month…" señalado por Victor; el valor por defecto basta |
| `b1.first_payment_help_charge` | Ya sin uso (D3) |
| `b1.short_month_note` | Caso borde; el resumen muestra la fecha real |
| `b2.summary_incomplete` | La región queda vacía |
| `b3.body_credit`, `b3.body_other` | El título + "Set up" bastan |
| `b3.confirm_point_budget`, `b3.confirm_point_future` | Repiten el encabezado |
| `b3.confirm_point_charge_next`, `b3.confirm_point_charge_backfill` | Fusionados en el encabezado y en `b3.confirm_point_backfill` |
| `c1.drawer_charge` | La línea "Monthly charge" basta |
| `c1.generated_notice` | Fuera de v1 |
| `c1.locked_amount_help` | Partido en `_installment` / `_msi` (2ª pasada) |
| `c2.kpi_committed_sub`, `c2.kpi_left_sub` | Upcoming ya muestra el próximo pago; el conteo de planes no cambia nada |
| `c2.summary_sentence`, `c2.summary_sentence_charges_only` | Repiten las cifras |
| `c2.upcoming_last` | "Installment 6 of 6" ya lo dice |
| `c2.all_done_body` | Obvio |
| `c4.line_split` | La lista del disclosure lo desglosa |
| `f.horizon` | Fusionado en `f.nav_next_disabled` |
| `f.readonly_help`, `f.autofill_note`, `f.empty_body` | Explicaciones que no cambian lo que hace la persona |
| `c3.edit_note` | `c3.confirm_edit_body` dice la consecuencia cuando importa |
| `c3.schedule_locked_charge` | "Stop payments" está a la vista |
| `c3.stop_title`, `c3.stop_body` | El confirm dice la consecuencia |
| `c3.delete_msi_hint` | Alternativa confusa (Stop deja la deuda sin cuotas) |
| `w.a.*`, `w.c.*`, `w.b.title`, `w.b.body` | Descartados en la 2ª pasada (B + A) |
| Toda mención "(MSI)", `<abbr title="Months without interest">` | Victor: el tipo es solo "Installments" |

## 13. Canvas de Victor (2026-10-08) — cambios y removidos

| id | Cambio | Fuente |
|---|---|---|
| `b2.line2_*` | Línea 2 del resumen con mayúscula ("Last on…") | Victor canvas edit; `last_one` / `no_end` unificados por design-lead |
| `b3.status_*`, `b3.button` | Estado actual bajo el título + "Edit" en lugar de "Set up" | Victor canvas edit (vía orchestrator) |
| `c1.drawer_installment` | **Removido**: el drawer de cuota es solo "Installment 1 of 12" + View plan | Victor canvas edit |
| `c3.delete_msi_primary` | "Delete" | Victor canvas edit |
| `c4.line_percent` | Se muestra también > 100% | Victor canvas edit |
| `f.autofill_body` | Nuevo cuerpo corto | Victor canvas edit |
| `w.ba.body`, `w.ba.body_card`, `w.b.multi` | **Removidos**: C2 ya no advierte; en C4 el Alert es título + CTA | Victor canvas edit (vía orchestrator) |
| `bi.*` | **Nuevos**: impacto en presupuesto al capturar | Victor canvas edit (vía orchestrator); `bi.title_over_multi` y `bi.reference` propuestos por design-lead |

Riesgo de vocabulario: `b3.status_one_time` ("One time") convive con el toggle existente "One-time Expense" (kind `one_time`, que excluye de promedios). Son cosas distintas con casi el mismo nombre; content-writer debería confirmar si conviene "Doesn't repeat" (el mismo string del radio) como estado.
