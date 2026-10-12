# Design Plan: Pagos recurrentes y MSI

> **For agentic workers:** REQUIRED: Use wtw-designpowers:designpowers-critique to review completed work against this plan.

**Goal:** Capturar una vez un cargo recurrente o una compra a MSI y que Maybe genere solo cada ocurrencia en su fecha, con deuda total correcta, gasto mensual repartido y una vista de compromisos.

**Design Direction:** [Brief](../briefs/2026-10-06-pagos-recurrentes-msi.md) · [Estrategia](../strategy/2026-10-06-pagos-recurrentes-msi-strategy.md) · `design-state.md`

**Personas:** Victor (single user, manual, ciclo día 27) + espectro del brief: carga cognitiva, lector de pantalla/teclado, sin color como único indicador, captura móvil con prisa.

**Reglas de ejecución (CLAUDE.md):** lógica en modelos, Minitest + fixtures, sin deps nuevas, strings en inglés hardcodeados, **no correr migraciones** (el usuario las corre), usar `icon` helper y tokens funcionales. Entorno: Docker/OrbStack — reconstruir imagen compartida `maybe-finance:local` antes de probar; tests con `RAILS_ENV=test POSTGRES_DB=maybe_test`.

**Orden:** Fase A (datos y números) debe estar verde antes de tocar UI. Cada fase cierra con su verificación.

---

## Fase A — Modelo y consistencia de números

### Task A1: Migración `recurring_transactions` + columnas en `transactions`
**Files:** `db/migrate/…_create_recurring_transactions.rb`, `db/schema.rb`
- [ ] Tabla `recurring_transactions` (uuid): `family_id`, `account_id`, `category_id` (null), `merchant_id` (null), `name`, `plan_type` (string: `charge` | `installments`), `amount` decimal(19,4) (por ocurrencia en `charge`, **total** en `installments`), `currency`, `start_date` (fecha de 1ª ocurrencia), `total_payments` int (null = sin fin), `status` (string: `active` | `cancelled` | `completed`, default `active`), `last_generated_on` date, timestamps.
- [ ] En `transactions`: `recurring_transaction_id` (uuid, FK null), `installment_number` int (null).
- [ ] Índice único `[recurring_transaction_id, installment_number]` en `transactions` (idempotencia; aplica también a `charge` usando número de ocurrencia).
- [ ] Actualizar `db/schema.rb` a mano (sin bind mount, la migración no lo regenera en el host).

**Accessibility check:** n/a (datos) — pero `total_payments` y `installment_number` habilitan el texto "Installment 2 of 6" (P4).
**Verification:** `schema.rb` refleja tabla/columnas/índice; el usuario corre `db:migrate`.

### Task A2: Nuevos kinds + constante compartida de exclusión
**Files:** `app/models/transaction.rb`
- [ ] Agregar al enum `kind`: `msi_purchase`, `installment`.
- [ ] `BUDGET_EXCLUDED_KINDS = %w[funds_movement one_time cc_payment msi_purchase].freeze`.
- [ ] `BALANCE_EXCLUDED_KINDS = %w[installment].freeze`.
- [ ] `belongs_to :recurring_transaction, optional: true`; `generated?`.

**Accessibility check:** n/a.
**Verification:** test de enum y constantes.

### Task A3: Las 4 queries de gasto usan la constante
**Files:** `app/models/income_statement/totals.rb`, `family_stats.rb`, `category_stats.rb`, `app/models/transaction/search.rb`
- [ ] Reemplazar `NOT IN ('funds_movement','one_time','cc_payment')` por bind de `Transaction::BUDGET_EXCLUDED_KINDS` en las 3 de `IncomeStatement`.
- [ ] `Search#totals` y su filtro de tipo usan la misma constante (decisión de usuario: también excluye `one_time`).
- [ ] `installment` **sí** cuenta como gasto (no está en la lista).

**Accessibility check:** P3 "una verdad por número" — mismo gasto en todas las pantallas.
**Verification:** test cruzado: mismo dataset (standard + one_time + msi_purchase + installment) → mismo gasto en totals, family/category stats y Search.

### Task A4: Las cuotas no mueven el saldo
**Files:** `app/models/balance/sync_cache.rb`
- [ ] En `converted_entries`, omitir entries cuyo `entryable` sea `Transaction` con `kind` en `BALANCE_EXCLUDED_KINDS` (único punto que alimenta forward, reverse y base).

**Accessibility check:** n/a.
**Verification:** test de paridad: cuenta de crédito manual con compra `msi_purchase` $3,000 + 3 `installment` de $1,000 → saldo = $3,000 en forward; mismo resultado con reverse.

### Task A5: `RecurringTransaction` model
**Files:** `app/models/recurring_transaction.rb`, `app/models/family.rb` (`has_many`), `app/models/account.rb` (`has_many`)
- [ ] Validaciones: `amount > 0`, `total_payments` requerido y ≥ 2 si `installments`, cuenta de crédito requerida para `installments`.
- [ ] `installment_amount`: `amount / total_payments` redondeado a 2 decimales; **la última cuota absorbe el residuo** (suma exacta = total).
- [ ] `occurrence_dates`: mensual desde `start_date`, día del mes clamped a fin de mes (31 → 28/29/30), hasta `total_payments` o abierto.
- [ ] `upcoming(limit_date)`: ocurrencias futuras no generadas (calculadas, no guardadas).
- [ ] `remaining_payments`, `remaining_balance` (installments), `end_date`, `completed?`.
- [ ] `cancel!` → `status: cancelled` (no toca filas generadas).

**Accessibility check:** P2 — todos los derivados existen como métodos para que la UI los muestre/anuncie.
**Verification:** tests: $1,000/3 → 333.33, 333.33, 333.34; inicio 31-ene → 28-feb; `upcoming` excluye generadas.

### Task A6: Generación idempotente (`generate_due!`)
**Files:** `app/models/recurring_transaction.rb`
- [ ] `generate_due!(as_of: Date.current)`: por cada ocurrencia con fecha ≤ `as_of` sin fila, crear Entry+Transaction con **fecha original**, `installment_number`, nombre, categoría, merchant; `kind: installment` si MSI, `standard` si `charge`.
- [ ] `rescue ActiveRecord::RecordNotUnique` por ocurrencia (reintento seguro).
- [ ] Actualizar `last_generated_on`; si generó la última → `completed`.
- [ ] Al terminar, `account.sync_later` una sola vez si creó algo.

**Accessibility check:** n/a.
**Verification:** tests: 3 meses "apagado" → crea 3 con fechas originales; correr 2 veces → 0 duplicados; regla cancelada → 0.

### Task A7: Crear plan desde una transacción (nueva o existente)
**Files:** `app/models/recurring_transaction.rb` (`.create_from_entry!`)
- [ ] `charge`: la entry original **es** la ocurrencia #1 (se enlaza con `installment_number: 1`), regla genera desde la #2.
- [ ] `installments`: la entry original pasa a `kind: msi_purchase` (monto total, suma deuda), regla genera cuotas 1..N desde `start_date` (default: un mes después de la compra, editable). Si la compra es pasada, `generate_due!` crea las vencidas con fecha original (decisión de usuario).
- [ ] Todo en una transacción de DB.

**Verification:** tests de ambos tipos, incluida compra de hace 2 meses → 2 cuotas pasadas creadas.

### Task A8: Disparo perezoso (CPU ≈ 0)
**Files:** `app/controllers/concerns/recurring_generation.rb` (nuevo concern), `app/controllers/application_controller.rb`, `app/jobs/generate_recurring_transactions_job.rb`, `app/models/family.rb`
- [ ] `before_action`: si `Current.family` y `family.recurring_generated_on != Date.current` → actualizar fecha y encolar job (una vez/día). Columna `families.recurring_generated_on` date (agregar a A1).
- [ ] Job: `family.recurring_transactions.active.find_each(&:generate_due!)`.

**Verification:** test de controller: 2 requests el mismo día → 1 job encolado; app ociosa → 0 jobs.

**Cierre Fase A:** suite `test/models` verde + rubocop limpio. Ningún cambio visible todavía.

---

## Fase B — Captura

### Task B1: Campos en el form de nueva transacción
**Files:** `app/views/transactions/_form.html.erb`, `app/controllers/transactions_controller.rb`
- [ ] Dentro del `DS::Disclosure` existente: select "Repeat" (`Doesn't repeat` / `Every month`) y, solo si la cuenta es de crédito y outflow, "Pay in installments (MSI)" con número de meses (2–48) y "First payment" (fecha, default +1 mes).
- [ ] Params virtuales (`recurrence[...]`), no en `entry_params`; tras crear la entry → `RecurringTransaction.create_from_entry!`.
- [ ] Mostrar/ocultar campos con el patrón Stimulus existente del form (sin controller nuevo si se puede; si no, uno mínimo).

**Accessibility check:** `<label>` explícito en cada campo; `aria-describedby` al texto de ayuda; campos ocultos realmente fuera del orden de tab; error de meses inválidos en texto junto al campo.
**Verification:** crear MSI y cargo desde el form; ver filas y regla creadas.

### Task B2: Resumen calculado en vivo (P2)
**Files:** mismo form + controller Stimulus mínimo
- [ ] Al cambiar monto/meses: "6 payments of $500.00 · last on Mar 27, 2027" en región `aria-live="polite"`.

**Accessibility check:** se anuncia sin mover el foco; legible a 200% zoom.
**Verification:** VoiceOver anuncia el resumen al cambiar meses.

### Task B3: Convertir transacción existente
**Files:** `app/views/transactions/show.html.erb`, `app/controllers/transactions/recurrences_controller.rb` (o acción en controller existente)
- [ ] Bloque con patrón caja icono + texto (como `budgets/edit`): "Make recurring" / "Pay in installments" con los mismos campos.
- [ ] Confirmación con resumen de lo que cambiará antes de guardar.
- [ ] Ocultar toggles `one_time`/`excluded` en filas `msi_purchase` e `installment` (P4).

**Accessibility check:** confirmación con texto explícito; botón principal identificable sin color.
**Verification:** convertir una compra de hace 2 meses → `msi_purchase` + cuotas vencidas con fecha original.

---

## Fase C — Ver y gestionar

### Task C1: Fila generada se explica
**Files:** parcial de fila de transacción (`app/views/transactions/_transaction.html.erb` o equivalente)
- [ ] Línea secundaria "Installment 2 of 6" / "Recurring" con icono + texto, enlazando a la regla/compra original.

**Accessibility check:** texto, no solo icono; link con nombre accesible.
**Verification:** la fila de cuota muestra y enlaza correctamente.

### Task C2: Compromisos en la tarjeta de crédito (vista primaria)
**Files:** `app/views/credit_cards/_overview.html.erb` (+ parcial nuevo)
- [ ] Sección "Installments (MSI)": por regla — nombre, cuota, pagos restantes ("4 of 6 left"), saldo pendiente, fecha de fin.
- [ ] Total "Pending MSI balance" y "Committed per month" para los próximos meses.
- [ ] Suscripciones (`charge`) de esa cuenta en sub-lista "Recurring charges".

**Accessibility check:** tabla semántica con `<th scope>`; resumen en texto además de cifras; orden por fecha de fin.
**Verification:** con 2 MSI activos, responder "¿cuánto debo a MSI y cuánto me cobran el próximo mes?" en < 5 s.

### Task C3: Editar / cancelar regla (solo futuras)
**Files:** `app/controllers/recurring_transactions_controller.rb`, vista modal con `<dialog>` existente
- [ ] Editar categoría/nombre/monto (charge) → solo ocurrencias futuras.
- [ ] Cancelar → `cancel!`; confirmación clara de qué se conserva.

**Accessibility check:** foco atrapado en el dialog y devuelto al cerrar; acción destructiva distinguible por texto.
**Verification:** editar no cambia filas pasadas; cancelar detiene futuras.

### Task C4: Línea en presupuesto (vista secundaria)
**Files:** `app/views/budgets/_budgeted_summary.html.erb` o `_actuals_summary.html.erb`, `app/models/budget.rb`
- [ ] "Committed from recurring payments: $X" para el ciclo actual (ocurrencias generadas + por generar dentro del ciclo).

**Accessibility check:** texto completo, no abreviado.
**Verification:** valor coincide con la vista de la tarjeta para ese ciclo.

---

## Fase D — Contenido y revisión

### Task D1: content-writer
- [ ] Validar nombres: "Recurring payment", "Monthly charge", "Installments (MSI)", "Months without interest", mensajes de error, confirmaciones.

### Task D2: Revisión
- [ ] design-critic + accessibility-reviewer + heuristic-evaluator en paralelo; reconciliación; ronda de fixes.
- [ ] verification-before-shipping: tests, rubocop, recorrido teclado/VoiceOver, prueba en escala de grises.

---

## Fuera de alcance (recordatorio)
Plaid, MSI con intereses, liquidación anticipada, frecuencias no mensuales, notificaciones, ingresos recurrentes, vista en dashboard.
