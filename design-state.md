# Design State: Pagos recurrentes y MSI

_Last updated: 2026-10-08 by orchestrator (Phase A done)_

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
No taste profile — craft evaluation uses general quality standards only. Señal temprana: reutilizar patrones existentes (cajas con ícono del setup de presupuesto, DS components). Referencia funcional: Dime "Upcoming".

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

## Open Questions
- [ ] Nombre del concepto en UI (inglés) — content-writer (propuesta: "Recurring payment"; tipos "Monthly charge" / "Installments (MSI)")

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

**Next (code):** superpowers plans for Phase B (capture UI: `DS::Disclosure` fields in the transaction form + convert from `transactions/show`, calling `RecurringTransaction.create_from_entry!`) and Phase C (commitments view on the credit card + one line in budget).

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

## Design Debt Register
_Items: 0 | Critical: 0 | Oldest: —_

| ID | Date | Source | Severity | What | Who is affected | Suggested fix | Status | Notes |
|----|------|--------|----------|------|----------------|---------------|--------|-------|

## Handoff Chain

### 2026-10-06 orchestrator → design-strategist
> "Brief aprobado: pagos recurrentes con dos tipos, Cargo (suscripción) y MSI. El reto central es que en MSI la deuda entra completa el día de la compra pero el gasto se reparte, y hay 4 queries de gasto + 3 calculadores de saldo que deben quedar consistentes. Necesito principios, el flujo de captura (incluyendo convertir una transacción existente), y dónde vive la vista de compromisos — reutilizando UI existente, nada desde cero."

### 2026-10-06 design-strategist → writing-design-plans
> "Estrategia lista: modelo `recurring_transactions` más dos kinds nuevos (`msi_purchase` y `installment`). Lo crítico es que las 4 queries de gasto compartan una constante y que los 3 calculadores de saldo usen un solo scope, con tests de paridad; ahí está el mayor riesgo. La captura va como campos en el disclosure del form y en `transactions/show` para convertir una existente, y la vista de compromisos vive en la ficha de tarjeta. Ordena el plan empezando por modelo y consistencia de números antes de cualquier UI."
