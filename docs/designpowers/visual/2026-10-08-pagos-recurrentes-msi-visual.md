# Visual design: Pagos recurrentes y cuotas

_2026-10-08 · design-lead (visual) · Modo directo · **Rev 3 — sincronizado con el canvas de Victor.**_
_**Fuente de verdad visual:** canvas https://claude.ai/artifact/1gVBYF2NsiBFS45AoPC1JT, copiado en [canvas/](canvas/) (un `.dc.html` por pantalla + `canvas.json`); diff contra rev 2 en [canvas/CHANGES-from-rev2.md](canvas/CHANGES-from-rev2.md). Los mockups de rev 2 ([mockups/index.html](mockups/index.html)) quedan **superados**._
_Insumos: taste aprobado, interacción (rev con impacto en captura), copy (3ª pasada + ediciones de canvas), código Maybe (`transactions/*`, `entries/_entry_group`, `UI::AccountPage`, `budgets/*`, `budget_categories/*`, `DS::*`)._

Strings por id del copy doc, textuales. **Cero tokens nuevos, cero componentes nuevos.** Las medidas del canvas escritas como `style=""` se traducen aquí a utilidades Tailwind equivalentes (mismo valor en px); los anchos porcentuales de barras siguen como `style="width: …%"`, igual que hoy en `_budgeted_summary`.

---

## 0. Decisiones visuales

| # | Decisión | Por qué |
|---|---|---|
| V1 | Listas nuevas = anatomía de `entries/_entry_group` y una sola **fila de compromiso** (Upcoming C2, "See details" C4, drawer de categoría futura) | Indistinguible de Maybe |
| V2 | **C4** (presupuesto): en exceso se mantiene la cabecera neutra (cifra + barra + %) y debajo un `DS::Alert :warning` **solo con título y "Review budget"** | Canvas de Victor |
| V3 | El número es la alerta: cifras `text-xl`/`text-2xl font-medium text-primary tabular-nums` | Taste |
| V4 | Mes futuro = chip `f.starts` + "Committed" con `repeat` + sin tabs | Forma y palabra, no gris |
| V5 | Procedencia (C1) visible en todo ancho; en `lg` la cuenta va **primero** | Canvas de Victor |
| V6 | Barras de % neutras (`bg-inverse`/`bg-surface-inset`); **en exceso** la barra de C4 es `bg-destructive` al 100 % | Canvas de Victor |
| V7 | `tabular-nums` en toda cifra; montos `text-right` | |
| V8 | "Doesn't repeat" marcado por defecto (B1, B3) | Victor |
| V9–V14 | Reglas de alineación de rev 2 (pares con `@container` + `@sm:grid-cols-2`, inputs `h-5`, resumen B2 en 2 líneas, icono+texto con `items-start` y un solo span, sin `px-1`, KPIs 1 columna bajo `md`) | Siguen vigentes; el canvas no las cambia |
| **V15** | **La advertencia se mueve a la captura**: bloque "budget impact" bajo el resumen de B1 cuando se elige Installments; proyecta los presupuestos de las próximas 3 cuotas con la compra incluida | Decisión de Victor vía canvas: avisar cuando aún se puede decidir, no después |
| **V16** | **C2 ya no advierte**: la tarjeta solo muestra cifras, Upcoming, tablas y pasados | Canvas |
| **V17** | **B3 cerrado muestra el estado actual** ("One time" / "Monthly charge" / "Installments · 3 of 12") con botón `outline` "Edit" + `pencil` | Canvas |
| **V18** | Rojo (`destructive`) en el bloque de impacto en lugar de amarillo | Victor aceptó rojo aquí: es "te pasas", no "atención" |
| **V19** | Texto rojo pequeño: el canvas usa `text-destructive` (red-600, **4.36:1** sobre blanco, falla AA por poco). **Propuesta para el build:** texto en `text-red-700 theme-dark:text-red-400` (5.86:1 / 4.95:1) — el mismo par que ya usa `DS::Alert :error`; las barras siguen en `bg-destructive`. **Decisión pendiente de Victor** | AA sin token nuevo |

---

## 1. Fundaciones

| Rol | Clase | Claro | Oscuro |
|---|---|---|---|
| Texto | `text-primary` / `text-secondary` / `text-subdued` | gray-900 / gray-500 / gray-400 | white / gray-400 / gray-600 |
| Tarjeta | `bg-container shadow-border-xs rounded-xl` | white | gray-900 |
| Inset / chip | `bg-container-inset` / `bg-surface-inset` | gray-50 / gray-100 | gray-800 / gray-800 |
| Bordes | `border-secondary` · `border-tertiary` · `border-divider` | | |
| Exceso | `bg-destructive` (barras) · texto ver V19 | red-600 | red-400 |
| Advertencia C4 | `DS::Alert :warning` | yellow-50 / yellow-700 | yellow-900@20% / yellow-400 |
| Iconos | `repeat` · `credit-card` · `calendar-clock` · `alert-triangle` · `pencil` · `lock` · `check` · `circle-stop` | | |

Tamaños de icono: 12 px en `text-xs` · 16 px en `text-sm` · 20 px como icono de caja.

---

## 2. B1 + B2 — Captura

- `DS::Disclosure` "Recurring payment", contenido `mt-2 space-y-3` sin padding lateral.
- Radios: `<fieldset>` + `legend text-xs text-secondary mb-1` "Repeat"; opciones `flex items-center gap-2 min-h-11 text-sm text-primary` + radio 16 px + `<span>`; "Doesn't repeat" **checked**.
- Installments: par `@container` → `grid grid-cols-1 @sm:grid-cols-2 gap-2`, inputs `class: "form-field__input h-5"`.
- **Resumen:** `rounded-lg bg-container-inset px-3 py-2 flex items-start gap-2` + icono 16 px `mt-0.5`; línea 1 cifras `text-primary font-medium`, línea 2 **`b2.summary_*_line2`** en `text-secondary` con mayúscula inicial ("Last on Oct 8, 2027"); `b2.summary_past_due` `mt-1`.
- **Bloque de impacto (nuevo, V15)** — justo debajo del resumen, solo con Installments y presupuesto de base disponible:

```
<section aria-labelledby="impact-title" class="rounded-lg border border-tertiary p-3 flex flex-col gap-3">
  <div class="flex items-start gap-2">                                  ← cabecera
    icon "alert-triangle" 16 px, mt-0.5, color del texto rojo (V19)       (solo si hay exceso)
    <div class="text-sm tabular-nums min-w-0">
      <p id="impact-title" class="font-medium {rojo V19}">bi.title_over</p>
      <p class="text-secondary">bi.subtitle</p>
    </div>
  </div>
  <ul class="flex flex-col gap-3">                                      ← un <li> por mes (máx. 3)
    <li class="flex flex-col gap-1.5">
      <div class="flex items-center justify-between text-sm tabular-nums">
        <span class="text-primary font-medium">{Budget#name}</span>
        <span class="font-medium {rojo V19}">bi.month_over</span>   |  <span class="text-secondary">bi.month_percent</span>
      </div>
      <div class="relative flex h-2 rounded bg-surface-inset" aria-hidden="true">
        <div class="h-2 rounded-l bg-inverse"     style="width: {committed/scale}%"></div>
        <div class="h-2 rounded-r bg-destructive" style="width: {installment/scale}%"></div>
        <div class="absolute -top-1 h-4 w-0.5 rounded-sm bg-current text-secondary" style="left: {budget/scale}%"></div>
      </div>
      <p class="text-xs text-secondary tabular-nums">bi.month_detail</p>
    </li>
  </ul>
  <div class="flex flex-wrap items-center gap-4 text-xs text-secondary" aria-hidden="true">   ← leyenda
    <span class="flex items-center gap-1.5"><span class="size-2 rounded-sm bg-inverse"></span>bi.legend_committed</span>
    <span class="flex items-center gap-1.5"><span class="size-2 rounded-sm bg-destructive"></span>bi.legend_purchase</span>
    <span class="flex items-center gap-1.5"><span class="h-2.5 w-0.5 bg-current"></span>bi.legend_budget</span>
  </div>
</section>
```
  - **Escala** común a los 3 meses: `scale = max(budget × 1.2, mayor total)`, así la marca de presupuesto cae en 83.3 % (como en el canvas) y nada se sale.
  - El segmento "This purchase" es **siempre** `bg-destructive` (canvas), también en meses que no se pasan.
  - Sin exceso: no hay icono; la cabecera es solo `bi.subtitle` en `text-sm font-medium text-primary`.
  - Sin presupuesto de base (nunca configuró uno): el bloque no se renderiza.
  - Mes sin presupuesto propio: `bi.month_detail` usa el presupuesto de referencia y se añade `bi.reference` (`text-xs text-secondary`) bajo la lista, una vez.
  - Contraste: barra roja vs pista 3.82:1 (oscuro 4.29:1), marca 4.16:1 (oscuro 5.79:1), `bg-inverse` 13.6:1 → ≥ 3:1 como componente gráfico. Las barras son `aria-hidden`; el texto de cada `<li>` lleva la información.
- Errores: igual que rev 2.

## 3. B3 — Convertir / editar (drawer, Settings)

- **Cerrado (V17):** `flex items-center justify-between gap-4 p-3` → `<div class="text-sm space-y-1"><h4 class="text-primary">Recurring payment</h4><p class="text-secondary">{b3.status_*}</p></div>` + `DS::Button outline` icono `pencil` "Edit" (`aria-label` "Edit recurring payment").
- **Abierto:** sin cambios respecto a rev 2 (radios con "Doesn't repeat" checked, "Review" `disabled` hasta elegir tipo, panel `bg-container-inset`).
- **Confirmación:** el `h4` recibe foco (`tabindex="-1"`) **sin anillo dibujado fijo**: usar el foco visible del navegador (`focus-visible:ring-4 focus-visible:ring-alpha-black-200`, solo aparece con teclado). La línea 2 del resumen aquí también va "Last on…" (el canvas aún dice "last on" en este frame; se unifica).
- Toggle de Exclude: el canvas lo dibuja 23×23 con radio 6 px; es el placeholder del `DS::Toggle` existente. **El build no toca `DS::Toggle`.**

## 4. C1 — Filas generadas y drawer

- **Línea de procedencia** (`flex items-start gap-1`, icono 12 px `mt-0.5`, un `<span class="min-w-0">`): orden **cuenta · procedencia · View plan**:
  `<span class="hidden lg:inline"><a class="hover:underline">{cuenta}</a> <span aria-hidden="true">·</span> </span>{c1.*_line} <a class="text-primary font-medium hover:underline">View plan</a>`
  - El `·` tras la cuenta va **dentro** del `hidden lg:inline` (en el canvas quedó fuera y en móvil se vería un `·` suelto al inicio).
  - Entre procedencia y "View plan" **no** hay `·` (filas 1 y 2 del canvas); la fila de compra del canvas aún lo tiene → se unifica sin punto. Separación = un espacio normal (no `&nbsp;` dobles).
- **Drawer de cuota:** una sola fila `flex items-center justify-between gap-3 rounded-lg border border-tertiary p-3`: izquierda `flex items-center gap-3` icono 20 px + `<p class="text-sm text-primary font-medium">` `c1.installment_line`; derecha `DS::Link outline sm` "View plan". **Sin** `c1.drawer_installment`.
- **Drawer de compra:** sin cambios (caja con `c1.drawer_msi_purchase` + "View plan").
- **Type / Amount bloqueados:** apilados a ancho completo (`flex flex-col gap-2`, cada `.form-field` `w-full`), luego la ayuda `lock`.

## 5. C2 — Tab "Recurring payments"

Panel `bg-container p-5 shadow-border-xs rounded-xl space-y-5`: `h2` → KPIs (`grid-cols-1 md:grid-cols-3`) → **Upcoming** (sin advertencia, V16) → "See later months" → tablas → pasados. Vacío y "Nothing left to pay" sin cambios.

## 6. C3 — Plan y confirmaciones

Sin cambios salvo: botón destructivo del confirm de borrar compra = **"Delete"** (`c3.delete_msi_primary`, variante `destructive`). El título y el cuerpo del diálogo ya dicen qué se borra.

## 7. C4 — Bloque en presupuesto

- **Normal:** igual que rev 2 (cabecera `repeat` + cifra `text-xl` + "committed to recurring payments" + barra neutra + `c4.line_percent`/`_reference` + "See details").
- **Exceso (canvas):** misma cabecera; barra = un solo segmento `rounded-md h-1.5 bg-destructive` al 100 %; `c4.line_percent` en `text-sm text-primary font-medium` (ahora también > 100 %, p. ej. "123% of your budget"; en un mes sin presupuesto propio se usa `c4.line_percent_reference`). Debajo, `DS::Alert :warning` con `<p class="font-medium text-pretty tabular-nums">` `w.ba.title` + `DS::Link outline sm mt-3` "Review budget". Sin cuerpo ni referencia dentro del Alert. Luego "See details".
- Se retiran los frames "over its own budget" y "stress": el título ya se verificó sin truncar en rev 2 (3 líneas a 300 px).
- Vacío futuro: igual.

## 8. Mes futuro

Sin cambios salvo setup: la caja de autofill dice `f.autofill_title` + **`f.autofill_body`** ("Copies October 2026's budget").

## 9. Contraste

| Par | Ratio | Resultado |
|---|---|---|
| `text-destructive` red-600 / white (bloque de impacto, canvas) | 4.36 | ✗ texto pequeño → V19 |
| red-700 / white (propuesta V19) | 5.86 | ✓ |
| Oscuro: red-400 / gray-900 | 4.95 | ✓ |
| `bg-destructive` / `bg-surface-inset` (barra) | 3.82 (oscuro 4.29) | ✓ gráfico |
| Marca de presupuesto gray-500 / gray-100 | 4.16 (oscuro 5.79) | ✓ gráfico |
| yellow-700 / yellow-50 (Alert C4) | 5.20 | ✓ |
| text-secondary / white | 4.74 | ✓ |
| text-secondary / container-inset | 4.43 | ⚠ existente (DD-4) |
| `outline-destructive` | 4.36 | ⚠ existente (DD-5) |

## 10. Para el plan

- `@container` / `@sm:` nativos en Tailwind v4. `h-5` con `class: "form-field__input h-5"` completo.
- El bloque de impacto es parte de la respuesta del preview (mismo frame, ver interacción §2.4b); no es componente nuevo.
- La línea de procedencia cambia el `hidden lg:block` de `_transaction` solo en filas con plan.
- Deuda: DD-4, DD-5 (existentes); DD-6 propuesta si Victor no acepta V19.
