# Design State: Pagos recurrentes y MSI

_Last updated: 2026-10-08 by design-lead (visual)_

## Brief
- **Problem:** Compras a MSI y suscripciones se capturan a mano cada mes; no hay visibilidad de deuda MSI ni flujo comprometido.
- **Primary persona:** Victor — single user, self-hosted, cuentas manuales MX, ciclo de presupuesto día 27.
- **Success metric:** 1 captura por compra MSI; cuotas aparecen solas en el ciclo correcto; saldo = deuda total sin duplicar; compromisos visibles en <5 s; cero CPU en ocio.
- **Brief document:** [docs/designpowers/briefs/2026-10-06-pagos-recurrentes-msi.md](docs/designpowers/briefs/2026-10-06-pagos-recurrentes-msi.md)

## Personas
_Pendiente (inclusive-personas). Base: Victor + espectro del brief (carga cognitiva, lector de pantalla, daltonismo, móvil con prisa)._

## Design Principles
1. **Reusar antes de crear** — todo entra como campo/fila en pantallas existentes; ningún componente DS nuevo.
2. **El sistema calcula, la persona confirma** — cuota, pagos restantes y fecha de fin se derivan y se anuncian (`aria-live`).
3. **Una verdad por número** — deuda, gasto y compromiso se calculan en un solo lugar (constante compartida en `Transaction` + scope único de saldo).
4. **Lo generado se ve y se explica** — "Installment 2 of 6" en texto + icono, enlace a la regla, sin toggles riesgosos en filas generadas.
5. **Cero estado solo por color** — texto + icono siempre; teclado y lector de pantalla completos.

Detalle: docs/designpowers/strategy/2026-10-06-pagos-recurrentes-msi-strategy.md

## Taste Profile
- **Emotional target:** alerta útil — el compromiso mensual se ve como un límite real, sin ruido
- **Quality level:** Flagship (pulido dentro de componentes DS existentes; sin componentes nuevos)
- **Key references:** Maybe mismo (baseline), Dime "Upcoming" (estructura, no estética)
- **Anti-references:** dashboard ruidoso, wizard de varios pasos, banca tradicional
- **Aesthetic principles:** El número es la alerta · Color de advertencia escaso y ganado · Indistinguible de Maybe · Un campo, no un flujo · Lo generado, explicado
- **Taste document:** docs/designpowers/taste/2026-10-08-pagos-recurrentes-msi-taste.md

## Decisions Log

| Date | Agent | Decision | Rationale |
|------|-------|----------|-----------|
| 2026-10-06 | user | Generalizar MSI a "pagos recurrentes con fecha de fin" (cubre suscripciones) | Un solo concepto para ambos casos |
| 2026-10-06 | user | Camino B: modelo `RecurringTransaction` que genera transacciones reales | Cuotas visibles/editables, presupuestos casi sin cambios |
| 2026-10-06 | orchestrator | Generación perezosa por request (check de fecha + job una vez/día), no cron ni sync-on-login | Cero CPU en ocio; `auto_sync_on_login` está desactivado en `auto_sync.rb`; patrón tomado de Dime |
| 2026-10-06 | orchestrator | Ocurrencias se crean con su fecha original + índice único (regla, fecha) | Apagar el contenedor no altera presupuestos; reintentos idempotentes |
| 2026-10-06 | orchestrator | MSI: compra original suma deuda total y no cuenta como gasto; cuotas (`kind: installment`) cuentan como gasto y no mueven saldo | Separar deuda de gasto sin duplicar deuda |
| 2026-10-06 | user | Brief aprobado | — |
| 2026-10-06 | design-strategist | Compra original MSI = `kind: msi_purchase` nuevo (no `one_time` ni `excluded`) | `one_time`/`excluded` son toggles visibles: apagarlos duplicaría gasto; semántica clara |
| 2026-10-06 | design-strategist | Constante `Transaction::BUDGET_EXCLUDED_KINDS` usada por las 4 queries (incluye corregir `Transaction::Search`) | Una verdad por número; hoy Search ya es inconsistente |
| 2026-10-06 | design-strategist | Cuotas = filas `kind: installment` ignoradas por scope único en los 3 calculadores de saldo | Visibles/editables; evita deuda doble |
| 2026-10-06 | design-strategist | Tabla `recurring_transactions` + `recurring_transaction_id`/`occurrence_date` en transactions | Idempotencia limpia y editar/cancelar solo futuras |
| 2026-10-06 | design-strategist | Vista de compromisos: primaria en ficha de tarjeta de crédito, secundaria una línea en presupuesto | MSI es por tarjeta; reusa tabs/listas |
| 2026-10-06 | design-strategist | Captura: campos en `DS::Disclosure` del form + bloque equivalente en `transactions/show` para convertir existente | Un campo extra, cero pantallas nuevas |
| 2026-10-06 | user | `Transaction::Search#totals` también excluye `one_time` (y `msi_purchase`) | Mismo número que presupuesto en todas las pantallas |
| 2026-10-06 | user | Convertir compra pasada a MSI genera cuotas vencidas con su fecha original | Presupuestos de meses pasados quedan correctos |
| 2026-10-06 | user | Editar/cancelar regla solo afecta cuotas futuras | Historia generada no cambia |
| 2026-10-06 | user | Estrategia aprobada; inclusive-personas omitido (single user, espectro ya en brief) | — |
| 2026-10-08 | orchestrator | Exclusiones de gasto en un solo helper SQL `Transaction.budget_excluded_kinds_sql`, usado por `IncomeStatement::Totals`, `FamilyStats`, `CategoryStats` y `Transaction::Search#totals` | Una verdad por número; elimina 4 listas escritas a mano |
| 2026-10-08 | orchestrator | Exclusión de saldo en `Balance::SyncCache#converted_entries` (rechaza `installment`) | Es el único feed de entries de los 3 calculadores de saldo |
| 2026-10-08 | orchestrator | `installment_number` + índice único `(recurring_transaction_id, installment_number)` como llave de idempotencia | Reintentos y requests concurrentes no duplican cuotas |
| 2026-10-08 | orchestrator | Disparador perezoso: `before_action` (`RecurringGeneration`) encola `GenerateRecurringTransactionsJob` máx. 1 vez/familia/día vía `families.recurring_generated_on`, solo con planes activos | Cero CPU en ocio; se incluye en línea propia después de `Authentication` (include multi-módulo aplica en orden inverso) |
| 2026-10-08 | orchestrator | `belongs_to :recurring_transaction` se movió de Task 2 a Task 5; Account `dependent: :destroy`, Category/Merchant `dependent: :nullify` para planes | Sin el modelo rompía `TransactionImport`; FKs impedían borrar cuentas/categorías con planes |
| 2026-10-08 | user | Taste: emoción "alerta útil", calidad Flagship, refs Maybe + Dime Upcoming; anti-refs dashboard ruidoso / wizard / banca tradicional | Calibración design-taste |
| 2026-10-08 | content-writer | Concepto UI "Recurring payment"; tipos "Monthly charge" / "Installments (MSI)" con `<abbr>` "Months without interest" | Vale para ambos tipos; MSI es el modelo mental de Victor; "Monthly charge" > "Subscription" (renta, seguros) |
| 2026-10-08 | content-writer | Cancelar plan se llama "Stop" (estado "Stopped"); completados "Paid off" (MSI) / "Ended" (charge) | Evita choque con el botón "Cancel" del diálogo |
| 2026-10-08 | content-writer | Copy recomienda advertencia variante B (compromisos del ciclo > gasto presupuestado del ciclo) | Por qué concreto sin umbral arbitrario; acción real ("Review budget"); decide design-lead + Victor |
| 2026-10-08 | content-writer | Sentence case en strings nuevos; nivel de lectura grado 5–7; `·` aria-hidden; fechas `Mar 27, 2027` sin cero | Consistencia y legibilidad |
| 2026-10-08 | user | Advertencia de compromisos = variantes B + A combinadas: primero "los pagos recurrentes del ciclo superan lo presupuestado" (B, contra total presupuestado del ciclo) y luego qué % del presupuesto representan (A) | Dice el porqué y la magnitud; cierra la pregunta del umbral |
| 2026-10-08 | user | Nuevo alcance: ver presupuestos de meses futuros con la carga de cargos mensuales e installments ya comprometidos | Planear compras MSI viendo el impacto en ciclos futuros; entra en el plan (fase C) |
| 2026-10-08 | design-lead (interaction) | Captura en `DS::Disclosure` propio "Recurring payment" (solo en Expense), tipo como radios; Monthly charge sin campo "First payment" (la transacción es el pago 1) | Se descubre al escanear; un campo menos; coincide con `create_from_entry!` |
| 2026-10-08 | design-lead (interaction) | Resumen B2 calculado en servidor (Turbo frame `recurring_preview`, `role=status`, `aria-busy`), debounce 500 ms | Formato server-side y misma matemática que el modelo; un anuncio por pausa |
| 2026-10-08 | design-lead (interaction) | Conversión B3 inline en el drawer en dos pasos (campos → Review → confirmación); foco al encabezado de la confirmación; éxito por turbo_stream con foco al bloque de procedencia | Backfill reescribe presupuestos pasados: merece revisión sin modal extra |
| 2026-10-08 | design-lead (interaction) | Confirm global extendido con botón secundario ("Keep it") con foco inicial en destructivos (`CustomConfirm cancel_text:`) | Hoy el foco inicial cae en el botón destructivo; extensión, no componente nuevo |
| 2026-10-08 | design-lead (interaction) | Advertencia B + A: compromisos del ciclo (generados + por generar, familia completa) > `budgeted_spending` del ciclo; % entero hacia arriba; % neutro en la línea C4 cuando no se excede | Color solo cuando se gana; el % informa siempre |
| 2026-10-08 | design-lead (interaction) | Compromisos en presupuesto en bloque propio (columna izquierda, bajo el donut) con disclosure "See details" que lista los pagos del ciclo; solo ciclo actual y futuros | Visible aunque el presupuesto no esté inicializado; sirve con varias tarjetas |
| 2026-10-08 | design-lead (interaction) | C2 = tab "Recurring payments" en tarjeta de crédito (Activity sigue por defecto); Upcoming = ciclo actual + 2 siguientes | Reusa `UI::AccountPage` tabs; link directo `?tab=recurring` |
| 2026-10-08 | design-lead (interaction) | Presupuestos futuros = misma pantalla con "Committed" en lugar de "Spent"; horizonte 12 ciclos; navegación por chevron/picker existentes; montos de presupuesto editables, compromisos solo lectura; autofill desde el último presupuesto inicializado | Reusar antes de crear; continuidad cuando el ciclo se vuelve actual |
| 2026-10-08 | design-lead (interaction) | Schedule de un plan (inicio, número de pagos) no editable en v1 | Cierra el riesgo de `last_generated_on` del carry-over |
| 2026-10-08 | design-lead (interaction) | Notice de generación perezosa (`c1.generated_notice`) fuera de v1 | Sin momento natural para avisar sin polling |
| 2026-10-08 | user | Ciclo futuro sin presupuesto configurado: comparar compromisos contra el último presupuesto configurado, y decirlo en la advertencia ("Compared with your October 2026 budget…") | Es la pregunta al planear una compra MSI |
| 2026-10-08 | content-writer | Strings de §10 de interacción revisados y con id final; `w.ba.title` empieza por el concepto ("Recurring payments are $X over your December 2026 budget") | Se entiende al escanear; % va en el cuerpo |
| 2026-10-08 | content-writer | La palabra "cycle" no aparece en la UI: se usa el nombre del mes de `Budget#name` y rangos de `cycle_range_containing` (28 → 27) | Vocabulario interno; Maybe ya nombra presupuestos por mes |
| 2026-10-08 | content-writer | Schedule bloqueado: charge → "stop this charge and add a new one"; MSI → "delete the MSI purchase and add it again" (Stop deja la deuda sin cuotas) | Camino correcto según el modelo |
| 2026-10-08 | content-writer | Copy de presupuestos futuros (`f.*`): "Committed", "Starts Nov 28", autofill "Start from your October 2026 budget" + nota de que los compromisos siguen visibles | Alcance nuevo; nunca "Spent"/"Projected" en futuro |
| 2026-10-08 | orchestrator (transmite a Victor) | 2ª pasada del copy aprobada y vinculante (§6 B + A, §5.3 futuros, ciclos 28 → 27, nombres de mes vía `Budget#name`, variantes partidas `c3.schedule_locked_*` / `c1.locked_amount_help_*`); se usa textual | user direction (transmitida por el orchestrator) |
| 2026-10-08 | design-lead (visual) | Toda lista nueva (Upcoming C2, detalles C4, drawer de categoría futura) reusa la anatomía de `entries/_entry_group` (inset `p-1` + lista blanca `shadow-border-xs` + `shared/ruler`) con una sola "fila de compromiso" | Indistinguible de Maybe; una fila, tres superficies |
| 2026-10-08 | design-lead (visual) | Advertencia B + A = `DS::Alert variant: :warning` existente (título yellow-700, cuerpo `text-secondary`, CTA `DS::Link outline sm`); `text-warning` nunca como texto | `text-warning` sobre tinte = 3.34:1 (falla AA); yellow-700/yellow-50 = 5.20:1, oscuro 8.92:1; cero componentes nuevos |
| 2026-10-08 | design-lead (visual) | C4 replica el esqueleto de "Budgeted": etiqueta + cifra `text-xl` + barra `bg-inverse`/`bg-surface-inset` + "87% of your budget" en `text-primary font-medium`; en exceso la cifra/barra se reemplazan por el Alert | El número es la alerta; cero amarillo en normal |
| 2026-10-08 | design-lead (visual) | Mes futuro: chip `f.starts` (`bg-surface-inset text-primary font-medium` + `calendar-clock`), "Committed" con icono `repeat` en `text-primary font-medium` en el donut, sin tabs | Distinción por forma y palabra, no por gris/opacidad (pedido del content-writer) |
| 2026-10-08 | design-lead (visual) | Línea de procedencia C1 visible también en móvil; "View plan" en `text-primary font-medium` | Lo generado se explica sin hover ni pantalla ancha |
| 2026-10-08 | design-lead (visual) | Tablas C2 en < md ocultan "Payments left"/"Left to pay"/"Ends" y los muestran como 2ª línea bajo el nombre | Sin scroll horizontal a 375 px |
| 2026-10-08 | design-lead (visual) | Error de bloque B3 usa `DS::Alert :error` (icono `x-circle` del componente) en lugar de `alert-triangle` | Reusar el componente tal cual |
| 2026-10-08 | orchestrator (transmite a Victor) | Ronda de revisión de mockups: copy 3ª pasada (tablas "Kept" = fuente de verdad, sin "MSI"), "Doesn't repeat" marcado por defecto en B1 y B3, pixel perfect | user direction (transmitida por el orchestrator) |
| 2026-10-08 | design-lead (visual) | Rev 2: se quitan del spec y mockups todos los ids removidos (§12 del copy); advertencia = título + una línea de cifras + `w.ba.reference` (si aplica) + "Review budget" dentro de `DS::Alert :warning` (se mantiene el par AA del Alert aunque el copy diga `text-warning`) | Verificado en claro/oscuro: sigue leyéndose como alerta; `text-warning` como texto falla AA |
| 2026-10-08 | design-lead (visual) | "Doesn't repeat" checked por defecto; en B3 "Review" `disabled` hasta elegir tipo | Default explícito y seguro |
| 2026-10-08 | design-lead (visual) | Pares de campos con `@container` + `@sm:grid-cols-2` (stretch) e inputs `h-5`; resumen B2 en 2 líneas fijas (cifras / fecha) con icono `mt-0.5`; líneas icono+texto que pueden partir con `items-start` + un solo span; sin `px-1`; KPIs C2 en 1 columna bajo md | Desalineaciones medidas con `audit()` (label partido +16 px, date +2 px, icono huérfano, KPIs desfasados); 0 px de diferencia a 375/768/1280 |
| 2026-10-08 | orchestrator (transmite a Victor) | El canvas de Victor (https://claude.ai/artifact/1gVBYF2NsiBFS45AoPC1JT) es la fuente de verdad visual; sus ediciones son vinculantes. La advertencia de exceso sale de C2 y pasa a la captura (bloque "budget impact" en B1 con Installments); rojo aceptado ahí. B3 cerrado muestra estado + "Edit" | user direction (transmitida por el orchestrator, vía comentarios del canvas) |
| 2026-10-08 | design-lead (visual) | Rev 3 del spec sincronizada con el canvas: bloque de impacto con utilidades DS (escala común `max(budget×1.2, total)`, segmento de la compra `bg-destructive`, marca `bg-current text-secondary`), C4 en exceso = cabecera neutra con barra roja + Alert solo título/CTA, C1 con cuenta primero y drawer de cuota en una fila, "Delete" en confirm de compra | Fidelidad al canvas sin estilos inline ni tokens nuevos |
| 2026-10-08 | design-lead (visual) | Propuesta (pendiente de Victor): texto rojo del bloque de impacto en `text-red-700 theme-dark:text-red-400` en lugar de `text-destructive` | `text-destructive` 4.36:1 falla AA en texto pequeño; red-700 5.86:1 (par de `DS::Alert :error`) |
| 2026-10-08 | design-lead (interaction) | Impacto en captura: mismo preview y debounce (500 ms) que B2, meses de las 3 primeras cuotas, `committed(C)`/`budget_basis(C)` de §6.1, `bi.title_over` se anuncia dentro del `sr-only` del resumen; no bloquea el envío; no aparece en B3 en v1 | Una sola región viva; paridad con C4 al guardar |
| 2026-10-08 | design-lead (visual) | Interpretaciones del canvas: `·` tras la cuenta va dentro de `hidden lg:inline`; sin `·` antes de "View plan" en las 3 filas; "Last one…"/"No end date" con mayúscula como "Last on"; toggle 23×23 del canvas = placeholder, `DS::Toggle` no cambia; `c4.line_percent_reference` cuando el mes usa presupuesto de referencia | Consistencia; evitar un `·` suelto en móvil |
| 2026-10-08 | user | "Doesn't repeat" es siempre la opción seleccionada por defecto en Repeat | Ningún plan se crea sin intención explícita |
| 2026-10-08 | user | Tipo se llama solo "Installments" (sin "(MSI)" ni `<abbr>`); quitar todo texto auxiliar innecesario (p. ej. "Usually 3, 6, 9, 12, 18 or 24.", "Usually one month after the purchase.") en todas las superficies | Menos jargon/ruido; el copy solo donde aporta |
| 2026-10-08 | user | Mockups deben quedar pixel perfect: alineación de campos, helpers y resumen sin desalineaciones | Calidad Flagship |
| 2026-10-08 | user (Victor) | Tipo = "Installments" (sin "(MSI)" ni `<abbr>` en la UI); quitar textos de ayuda y explicaciones innecesarias; "Doesn't repeat" siempre por defecto en Repeat | Revisión de mockups |
| 2026-10-08 | content-writer | 3ª pasada: 165 → 133 strings (32 removidos, changelog §12 del copy doc); el resto acortado; tablas Kept = fuente de verdad; `msi_purchase` se rotula "Paid in {n} installments"; KPI "Left on installments" / "Last installment"; la advertencia pierde la oración de consejo (el CTA "Review budget" la reemplaza) | Filtro de Victor: solo labels, cifras, errores, consecuencias destructivas y deuda vs gasto |
| 2026-10-08 | user | La advertencia de presupuesto sale de la ficha de tarjeta (C2) y se mueve al momento de captura: al elegir Installments en una transacción nueva se muestra la proyección del presupuesto de los próximos meses con esa compra incluida (ya comprometido + esta compra vs presupuesto), y el monto excedido en rojo (`text-destructive`) | Decidir antes de comprar; supersede "color de advertencia escaso" para este caso (rojo en vez de amarillo) |
| 2026-10-08 | orchestrator | Default para build (Victor pidió construir sin más cambios): texto rojo del bloque de impacto usa `text-red-700 theme-dark:text-red-400` (AA 5.86/4.95:1); barras siguen `bg-destructive` | Accesibilidad gana sobre estética; mismo par que `DS::Alert :error`; reversible en una clase |
| 2026-10-08 | orchestrator | Default para build: el segmento "This purchase" queda rojo en todos los meses, como está en el canvas | Canvas es la fuente de verdad; Victor puede pedir neutral después |
| 2026-10-09 | orchestrator | Fases B y C construidas (18 tasks + revisión final + ronda de fixes) y verificadas en navegador contra el canvas; plan de código `docs/superpowers/plans/2026-10-08-recurring-transactions-phases-b-c.md` | Build pedido por Victor sin más cambios de diseño |
| 2026-10-09 | orchestrator | Defaults de build: sólo transacciones en la moneda principal pueden ser plan (`b.err.foreign_currency`); "Ends after" de cargos mensuales tope 600; monto de cuotas/compra MSI bloqueado en servidor (fecha editable); cifras de la pestaña de tarjeta por estatus del plan, Upcoming por generación | Seguridad de datos y consistencia de números |

## Open Questions
- [x] Nombre del concepto en UI (inglés) — resuelto por content-writer: "Recurring payment" / "Monthly charge" / "Installments (MSI)" (ver copy doc §1)
- [x] ¿Disclosure propio "Recurring payment" en el form o campos dentro de "Details"? — resuelto por interaction-design: disclosure propio
- [x] Horizonte de Upcoming en C2 — resuelto: ciclo actual + 2
- [x] Debounce del resumen aria-live — resuelto: 500 ms, preview en servidor
- [x] Ciclos futuros sin presupuesto configurado → comparar contra el último configurado (usuario, 2026-10-08)
- [x] Strings nuevos de §10 del doc de interacción — revisados por content-writer; aprobados por Victor (transmitido por orchestrator)
- [ ] Ejemplos de ciclo del copy dicen "27 – 26"; con `cycle_end_day = 27` el código da ciclos 28 → 27 — content-writer / verificar configuración de Victor
- [x] Umbral de la advertencia → B + A (usuario, 2026-10-08)
- [ ] Texto rojo del bloque de impacto: ¿`text-red-700`/`red-400` (AA) en lugar de `text-destructive` (4.36:1)? — Victor
- [ ] Segmento "This purchase" siempre rojo, incluso en meses que no se pasan — confirmar con Victor
- [ ] `bi.title_over_multi`, `bi.reference` y estado "One time" vs toggle "One-time Expense" — content-writer

### Resueltas (propuesta del strategist, pendiente de confirmación del usuario donde se indica)
- [x] Vista de próximos/compromisos → ficha de tarjeta + línea en presupuesto
- [x] Editar/cancelar regla → solo futuras (usuario confirma al aprobar la estrategia)
- [x] Convertir transacción existente → sí, desde `transactions/show`
- [x] Marcar compra original → `kind: msi_purchase`

## Status / Pending (2026-10-08)

**Done:** discovery, brief, strategy, design plan, superpowers Phase A plan, **Phase A (Tasks 1–9) done** — commits `ebf96a96..HEAD` on `feature/meses-sin-intereses`. Migration applied on `maybe_test` and `maybe_production`. Tests `test/models test/jobs test/controllers`: same 124 pre-existing failures as before Phase A (111 are `tailwind.css` not built in the bind-mounted source), no new ones. Rubocop clean.

Final whole-branch review: ready. Its 3 Important findings were fixed in Task 10 (`65a21ac0`): a deleted occurrence is never regenerated; deleting an MSI purchase deletes its plan and installments (destroying an MSI plan directly reverts the purchase to `standard`); `msi_purchase`/`installment` kinds are locked and excluded from transfer matching.

**Phase B must handle (carry-over from reviews):**
- Reset `last_generated_on` (or persist a watermark) if a plan's schedule becomes editable.
- `create_from_entry!`: only accept `standard`, non-transfer transactions.
- Show validation errors instead of a 500: one-time toggle on locked rows, `TransferMatchesController#create`.
- Hide/disable the one-time toggle on `msi_purchase`/`installment` rows.
- Generation date uses server/app date, not the family timezone.
- Limit plans to manual, active accounts; one invalid plan must not stop the family job.
- `Category#replace_and_destroy!` should move the plan's category, not nullify it.

Detailed ledger: `.superpowers/sdd/progress.md` (git-excluded).

**Phases B + C: built and browser-verified (2026-10-09).** Pending for Victor: content review of `b.err.foreign_currency`, `bi.title_over_multi`, `bi.reference`; confirm every credit card shows the Recurring payments tab (empty state when no plans).

**Was next (code):** superpowers plans for Phase B (capture UI: `DS::Disclosure` fields in the transaction form + convert from `transactions/show`, calling `RecurringTransaction.create_from_entry!`) and Phase C (commitments view on the credit card + one line in budget).

**Next (Designpowers workflow):** design-taste → content-writer (open: UI name, proposal "Recurring payment") → interaction-design → design-lead → Phase B/C plans → design-builder + screenshot checkpoint → critic / accessibility-reviewer / heuristic-evaluator + reconciliation + fix round → synthetic-user-testing → verification-before-shipping → team presentation → design-retrospective.

**Test environment:** web+worker of project `maybe-finance-dev` on http://localhost:3001 pointed at `maybe_test` (override file in the session scratchpad sets `POSTGRES_DB: maybe_test` and port 3001). Running `bin/rails test` reloads fixtures in `maybe_test`.

**Infra:** moving to a dedicated server; compose now requires `SECRET_KEY_BASE` in `.env` (commit `6e050109` on main).

## Artefact Index

| Artefact | Path | Status |
|----------|------|--------|
| Brief | docs/designpowers/briefs/2026-10-06-pagos-recurrentes-msi.md | Approved |
| Strategy | docs/designpowers/strategy/2026-10-06-pagos-recurrentes-msi-strategy.md | Approved |
| Plan (design) | docs/designpowers/plans/2026-10-06-pagos-recurrentes-msi-plan.md | Draft |
| Plan (code, Phase A — superpowers) | docs/superpowers/plans/2026-10-06-recurring-transactions-phase-a.md | Phase A done |
| Taste | docs/designpowers/taste/2026-10-08-pagos-recurrentes-msi-taste.md | Approved |
| Copy | docs/designpowers/content/2026-10-08-pagos-recurrentes-msi-copy.md | Approved (2ª pasada: §10 de interacción revisado, `f.*` y `w.ba.*` finales) |
| Interaction | docs/designpowers/interaction/2026-10-08-pagos-recurrentes-msi-interaction.md | Draft (ready for design-lead visual) |
| Visual spec | docs/designpowers/visual/2026-10-08-pagos-recurrentes-msi-visual.md | Rev 3 (sincronizado con el canvas) — ready for writing-design-plans |
| Canvas (fuente de verdad visual) | https://claude.ai/artifact/1gVBYF2NsiBFS45AoPC1JT · copia en docs/designpowers/visual/canvas/ (+ CHANGES-from-rev2.md) | Vigente — editado por Victor |
| Mockups (HTML estático) | docs/designpowers/visual/mockups/index.html | Superseded por el canvas (rev 2, solo historia) |

## Design Debt Register
_Items: 5 | Critical: 0 | Oldest: 2026-10-08_

| ID | Date | Source | Severity | What | Who is affected | Suggested fix | Status | Notes |
|----|------|--------|----------|------|----------------|---------------|--------|-------|
| DD-1 | 2026-10-08 | interaction-design | Medium | `DS::Tabs` sin roles ARIA (`tablist`/`tab`/`aria-selected`) | Lector de pantalla | Agregar roles y `aria-selected` en `DS::Tabs::Nav` | Open | Afecta el nuevo tab C2 |
| DD-2 | 2026-10-08 | interaction-design | Low | X del header de `DS::Dialog` con `tabindex="-1"` | Teclado | Quitar `tabindex` | Open | Esc sigue funcionando |
| DD-3 | 2026-10-08 | interaction-design | Medium | `#notification-tray` sin `role="status"`; auto-dismiss sin pausa | Lector de pantalla, lectura lenta | `role="status"` + pausar en hover/focus | Open | Incluido en implicaciones Fase B |
| DD-4 | 2026-10-08 | design-lead (visual) | Low | `text-secondary` sobre `bg-container-inset` = 4.43:1 en encabezados de grupo (`_entry_group`, Activity), 0.07 bajo AA | Baja visión | Usar `text-primary` o `text-secondary` sobre `bg-container` en encabezados de grupo | Open | Patrón existente; las listas nuevas lo heredan |
| DD-5 | 2026-10-08 | design-lead (visual) | Low | `outline-destructive` (red-600 sobre blanco) = 4.36:1; inflows `text-green-600` = 3.09:1 | Baja visión | Pasar a red-700 / green-700 en claro | Open | Existente del DS; afecta "Stop payments" y "Delete…" |

## Handoff Chain

### 2026-10-06 orchestrator → design-strategist
> "Brief aprobado: pagos recurrentes con dos tipos, Cargo (suscripción) y MSI. El reto central es que en MSI la deuda entra completa el día de la compra pero el gasto se reparte, y hay 4 queries de gasto + 3 calculadores de saldo que deben quedar consistentes. Necesito principios, el flujo de captura (incluyendo convertir una transacción existente), y dónde vive la vista de compromisos — reutilizando UI existente, nada desde cero."

### 2026-10-06 design-strategist → writing-design-plans
> "Estrategia lista: modelo `recurring_transactions` más dos kinds nuevos (`msi_purchase` y `installment`). Lo crítico es que las 4 queries de gasto compartan una constante y que los 3 calculadores de saldo usen un solo scope, con tests de paridad; ahí está el mayor riesgo. La captura va como campos en el disclosure del form y en `transactions/show` para convertir una existente, y la vista de compromisos vive en la ficha de tarjeta. Ordena el plan empezando por modelo y consistencia de números antes de cualquier UI."

### 2026-10-08 content-writer → interaction-design
> "Copy listo en docs/designpowers/content/2026-10-08-pagos-recurrentes-msi-copy.md: concepto 'Recurring payment', tipos 'Monthly charge' / 'Installments (MSI)', y 'Stop' en vez de 'Cancel' para no chocar con el botón del diálogo. Te toca decidir si la captura va en un disclosure propio (recomendado) o dentro de 'Details', dónde vive la confirmación de conversión (la propuse inline en el drawer, no un modal) y el debounce del resumen aria-live. La advertencia tiene 3 variantes; desde copy recomiendo B (ciclo sobre el gasto presupuestado), pero el umbral lo cierran design-lead y Victor."

### 2026-10-08 interaction-design → design-lead (visual)
> "Spec de interacción listo en docs/designpowers/interaction/2026-10-08-pagos-recurrentes-msi-interaction.md. Lo que más pide tu ojo: el bloque de compromisos en la columna izquierda del presupuesto (neutro con % y, solo al pasar el 100%, la advertencia B + A, la única con amarillo), y cómo un ciclo futuro se distingue del actual sin depender del color ("Starts Nov 28" + "Committed" en lugar de "Spent"). En el form, el resumen en vivo se atenúa mientras recalcula (≤150 ms, nada con reduced-motion), y en el drawer la confirmación de conversión es un paso inline, no un modal. Strings nuevos en §10 pendientes de revisión del content-writer."

### 2026-10-08 content-writer → design-lead (visual) (2ª pasada)
> "Los strings de §10 ya tienen id final en el copy doc. Lo visual que importa: `w.ba.title` es largo ('Recurring payments are $1,700.00 over your December 2026 budget') y tiene que caber en la columna izquierda del presupuesto y en C2 sin truncarse. `f.starts` y 'Committed' son lo único que distingue un mes futuro del actual, así que necesitan peso propio y no solo opacidad. En estado normal, `c4.line_percent` va en neutro, y el amarillo solo aparece arriba del 100%."

### 2026-10-08 design-lead (visual) → writing-design-plans
> "Spec visual en docs/designpowers/visual/2026-10-08-pagos-recurrentes-msi-visual.md y mockups en docs/designpowers/visual/mockups/index.html. Todo cabe en lo que ya existe: una sola 'fila de compromiso' sobre la anatomía de `_entry_group` sirve para C2, C4 y el drawer de categoría futura, y la advertencia es `DS::Alert :warning` con mensaje compuesto (no `text-warning`, que falla AA). Planea con cuidado el cambio de la línea de procedencia en `_transaction` (hoy `hidden lg:block`) y el punto único de decisión 'committed vs spent' para meses futuros (donut, summary, filas, drawer). Sin tokens ni componentes nuevos; DD-4/DD-5 son deuda existente, fuera de alcance."

### 2026-10-08 content-writer → design-lead (visual) (3ª pasada)
> "Copy recortado a 133 strings: el tipo es solo 'Installments' y ya no hay ningún 'MSI' ni `<abbr>`. Hay que actualizar los mockups: quitar las ayudas 'Usually…', la descripción del bloque B3, la frase resumen y las subcifras de C2, la línea de desglose de C4 y el título y la descripción sobre 'Stop payments'. 'Doesn't repeat' queda marcado por defecto también en B3; confírmalo en el mockup. Los ids tachados en los specs ya no existen, y la fuente de verdad son las tablas Kept del copy doc."

### 2026-10-08 design-lead (visual, rev 2) → writing-design-plans
> "Rev 2 lista: copy 3ª pasada aplicada (sin 'MSI', sin ayudas), 'Doesn't repeat' marcado por defecto y alineación medida a 0 px en 375/768/1280. Lo que el plan debe llevar tal cual: pares de campos con `@container` + `@sm:grid-cols-2` e inputs `h-5` (pasando `class: \"form-field__input h-5\"` completo, porque el form builder reemplaza la clase), el resumen B2 en dos líneas fijas y las líneas de procedencia con `items-start` y un solo span. La advertencia sigue siendo `DS::Alert :warning` por contraste AA."

### 2026-10-08 design-lead (visual, rev 3 / canvas) → writing-design-plans
> "El canvas de Victor manda ahora; el spec rev 3, el copy (§10b y §13) y la interacción (D13, D14, §2.4b) ya lo reflejan. El cambio grande es de lugar: la advertencia ya no vive en la tarjeta, vive en la captura, como un bloque de impacto que sale del mismo preview de B2 y usa exactamente `committed(C)`/`budget_basis(C)` de C4, así que planea un solo cálculo y un test de paridad. B3 cerrado ahora muestra el estado y 'Edit'. Queda abierto con Victor el rojo del texto (propuse red-700 por AA); no bloquea el plan porque es una clase."
