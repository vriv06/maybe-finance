# Design Brief: Pagos recurrentes y Meses Sin Intereses (MSI)

_Fecha: 2026-10-06 · Rama: `feature/meses-sin-intereses` · Estado: aprobado (dirección)_

## Problem Statement

En México es común comprar a **meses sin intereses** con tarjeta de crédito: una compra de $3,000 a 3 MSI se cobra $1,000 por mes. Hoy Maybe no tiene ningún concepto de pagos recurrentes ni de cuotas, así que el usuario:

1. **Captura cada cuota a mano** cada mes cuando aparece en el estado de cuenta ("pago 1 de 6", "pago 2 de 6"…). Repetitivo y fácil de olvidar.
2. **No ve cuánto debe a MSI** ni cuánto de su flujo de los próximos meses ya está comprometido — la pregunta real es "¿qué tan cargado tengo mi flujo mensual?".

El mismo hueco aplica a **suscripciones** (Netflix, Spotify, gym): cargos que se repiten y hoy se capturan uno por uno.

## Users

- **Usuario principal:** Victor — single user, self-hosted (Docker/OrbStack, pronto servidor 24/7), cuentas **manuales** (Plaid no soporta bancos mexicanos), presupuesto por ciclo personalizado (día 27).
- **Situaciones:** captura una compra el día que la hace (a veces desde el celular); revisa presupuesto y flujo al cierre de ciclo; quiere responder rápido "¿cuánto me queda comprometido?".
- **Espectro de capacidades a respetar:**
  - **Carga cognitiva:** varias compras MSI simultáneas con distintos plazos son difíciles de llevar mentalmente — la UI debe hacer el cálculo (cuota, pagos restantes, fecha de fin), no el usuario.
  - **Lector de pantalla / teclado:** formulario con etiquetas explícitas; el monto de cuota calculado debe anunciarse, no solo mostrarse.
  - **Daltonismo / sol directo:** "MSI" y "recurrente" no pueden distinguirse solo por color — siempre texto o ícono + texto.
  - **Uso móvil con prisa:** capturar una compra MSI no debe tomar más pasos que una transacción normal + 1 campo.

## Design Direction

**Camino B refinado — modelo de pago recurrente con generación perezosa** (inspirado en cómo lo resuelve la app Dime, con soporte real de fin por número de pagos).

### Concepto único: "Pago recurrente"
Un `RecurringTransaction` (nombre tentativo) con: cuenta, monto, categoría, nombre/comercio, frecuencia (mensual en v1), día de cobro, fecha de inicio, **número de pagos** (vacío = sin fin), y **tipo**:

| Tipo | Ejemplo | Deuda (saldo de la cuenta) | Gasto del mes (presupuestos/reportes) |
|---|---|---|---|
| **Cargo recurrente** | Suscripción $299 | +$299 cada mes | $299 cada mes |
| **MSI** | $3,000 a 3 meses | **+$3,000 el día de la compra** | $1,000 cada mes |

- **Cargo recurrente:** cada ocurrencia genera una transacción normal (`standard`) — cuenta como deuda y gasto, igual que si se capturara a mano.
- **MSI:** la compra original se registra por el total (suma deuda completa) pero **no** cuenta como gasto; cada cuota generada **sí** cuenta como gasto pero **no** mueve el saldo (si no, la deuda se duplica). Requiere un `kind` nuevo en transacción (p. ej. `installment`) que las queries de gasto incluyen y los calculadores de saldo ignoran, y que la compra original se marque para excluirse de gasto.

### Generación perezosa (CPU ≈ cero)
- Nada corre en segundo plano. En cada request, una comparación barata de fecha ("¿ya generé hoy?"); si no, se encola **una vez** un job que se pone al corriente.
- Las ocurrencias pendientes se crean **con su fecha original**, no con la fecha de hoy — apagar el contenedor semanas no altera los presupuestos de cada mes.
- Idempotente: índice único (regla + fecha de ocurrencia) — reintentos o apagones a mitad no duplican.
- No depende de `auto_sync_on_login` (está desactivado en `app/controllers/concerns/auto_sync.rb`).

### Vista de compromisos (calculada, no guardada)
- "Próximos pagos" y "deuda a MSI pendiente / flujo comprometido por mes" se calculan al vuelo desde las reglas, como el `FutureListView` de Dime.

## Constraints

- **Stack y convenciones del repo (CLAUDE.md):** Rails + Hotwire, lógica en modelos (no `app/services`), Minitest + fixtures, sin dependencias nuevas, no correr migraciones automáticamente, strings de UI hardcodeados en inglés (sin i18n) — término "MSI" a validar en contenido.
- **Reusar UI existente:** formulario de transacción (`app/views/transactions/_form.html.erb`), toggles `DS::Toggle`, `DS::Disclosure`, patrón de cajas con ícono del setup de presupuesto, componentes DS. Nada desde cero.
- **Sin CPU constante:** nada de cron frecuente ni polling.
- **Cuentas manuales únicamente:** Plaid fuera de alcance (sobrescribe `amount`/`date` en cada sync).
- **Gasto se calcula en 4 queries SQL independientes** (`income_statement/totals.rb`, `family_stats.rb`, `category_stats.rb`, `transaction/search.rb`) — los filtros por `kind` deben quedar consistentes en las 4 (hoy `Transaction::Search` ya difiere de las otras).
- **Saldos:** los calculadores (`balance/base_calculator.rb`, `forward_calculator.rb`, `reverse_calculator.rb`) suman todas las entradas sin mirar `kind` — las cuotas MSI deben excluirse ahí.
- **Compatible con el ciclo personalizado** (`cycle_end_day`) ya en `main`.

## Existing Design System

- `app/assets/tailwind/maybe-design-system.css` (tokens funcionales: `text-primary`, `bg-container`, `border-tertiary`…)
- Componentes `app/components/DS/*` (Toggle, Disclosure, Link, Menu, Tabs)
- Helper `icon` (nunca `lucide_icon` directo)

## Taste Direction (Early Signal)

- Reutilizar patrones ya existentes antes que inventar UI — mismo estilo que la caja "Autosuggest" / "Autofill budget from previous month".
- Referencia funcional: **Dime** (lista "Upcoming", recurrentes con fecha) — por cómo funciona, no por su estética.

## Success Criteria

1. Capturar una compra MSI toma **una sola captura** (transacción + "¿a cuántos meses?"), no N capturas.
2. Cada mes del plazo, la cuota aparece sola en transacciones y en el presupuesto del ciclo correcto, **sin abrir la app ese día**.
3. El saldo de la tarjeta refleja la **deuda total** desde el día de la compra; nunca se duplica.
4. Una pantalla responde en < 5 segundos: "¿cuánto debo a MSI y cuánto tengo comprometido en los próximos meses?".
5. Suscripciones funcionan con el mismo mecanismo (sin fin).
6. Con la app ociosa 24/7, **cero** trabajo en segundo plano atribuible a la feature.
7. Familias sin pagos recurrentes: comportamiento idéntico al actual.

## Out of Scope (v1)

- Plaid / cuentas conectadas.
- MSI **con** intereses, comisiones o tasas.
- Liquidar anticipadamente un MSI (pagar el resto de golpe) — v2.
- Frecuencias distintas a mensual (semanal, anual) — v2, el modelo debe permitirlo sin migración grande.
- Notificaciones/recordatorios de cobro.
- Conciliación automática contra estado de cuenta.
- Ingresos recurrentes (sueldo) — el modelo lo permitiría, pero no se diseña la UI ahora.

## Open Questions

- Nombre del concepto en UI (inglés): "Recurring payment", "Installments", "MSI"? → content-writer.
- ¿Dónde vive la lista de "próximos / compromisos": pestaña en transacciones, card en dashboard, sección en la tarjeta de crédito, o en presupuesto? → strategy.
- ¿Editar/cancelar una regla afecta cuotas ya generadas? (Propuesta: no — solo futuras.)
- ¿Convertir una transacción existente en MSI (ej. ya capturada hoy por el total)? Probablemente sí — es el flujo natural.
