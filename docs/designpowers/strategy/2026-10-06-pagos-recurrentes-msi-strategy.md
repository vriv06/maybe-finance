# Estrategia: Pagos recurrentes y MSI

_Fecha: 2026-10-06 · Autor: design-strategist · Insumo: brief aprobado + código de `feature/meses-sin-intereses`_

## 1. Principios de diseño

| # | Principio | En la práctica | Lo que NO haremos | Cómo se prueba |
|---|---|---|---|---|
| 1 | **Reusar antes de crear.** Cada capacidad nueva entra como campo o fila en una pantalla que ya existe. | Campos extra en el `DS::Disclosure` de `transactions/_form`; la lista de compromisos usa el layout de filas de entries; la caja de configuración copia el patrón icono + `DS::Toggle` de `budgets/edit`. | Wizard propio, pantalla nueva de "Recurring", componentes DS nuevos. | Lista de archivos de vista nuevos: solo parciales, ningún componente nuevo. |
| 2 | **El sistema calcula, la persona confirma.** Cuota, pagos restantes y fecha de fin se derivan del total y los meses. | Al escribir "6 months" aparece "6 payments of $500.00, last on Mar 27", dentro de una región `aria-live="polite"`. | Pedir la cuota y el total por separado; que el usuario sume fechas. | Capturar un MSI sin calcular nada a mano; lector de pantalla anuncia la cuota. |
| 3 | **Una verdad por número.** Deuda, gasto y compromiso son tres cifras distintas, cada una calculada en un solo lugar. | La lista de tipos excluidos de gasto vive en una constante de `Transaction` usada por las 4 queries; los calculadores de saldo usan un solo scope. | Copiar `NOT IN (...)` en cada query; que Search y Budget discrepen. | Test: mismo dataset da el mismo gasto en income statement, family stats, category stats y Search. |
| 4 | **Lo generado se ve y se explica.** Una cuota automática nunca parece capturada a mano ni aparece sin origen. | Cada ocurrencia muestra "Installment 2 of 6" (texto + icono) y enlaza a su regla; campos que no se pueden editar sin romper cuentas se muestran deshabilitados con motivo. | Cuotas "invisibles", ni toggles que permitan duplicar deuda (ocultar `one_time`/`excluded` en filas generadas). | Desde cualquier cuota se llega a la regla en 1 clic; ningún toggle riesgoso visible. |
| 5 | **Cero estado solo por color.** (Inclusivo) | "MSI" / "Recurring" siempre como texto + icono; "Upcoming" no depende de color de fecha; estados de error con texto; foco visible y orden de tab lógico en el formulario. | Badges de color como único diferenciador; mensajes de error solo en rojo. | Revisión en escala de grises + recorrido con teclado y VoiceOver sin pérdida de información. |

Tensión nombrada: P1 (reusar) vs P4 (explicar): reusar filas implica meter metadatos extra en una fila ya densa. Resolución: una sola línea secundaria de texto ("Installment 2 of 6") bajo el nombre, sin columnas nuevas.

## 2. Nota competitiva (breve)

- **Dime:** reglas recurrentes que se materializan perezosamente al abrir la app y una lista "Upcoming" calculada al vuelo. Lo tomamos. Lo que no hace: terminar por número de pagos. Ahí está nuestra diferencia (MSI).
- **Apps bancarias mexicanas** (BBVA, Banamex, Nu): muestran "MSI pendientes" con pagos restantes y saldo por liquidar, pero por tarjeta y sin ver el efecto en el presupuesto mensual. El modelo mental del usuario es: "compré X a N meses, me faltan K pagos, debo $Y". Nuestra vista debe responder exactamente eso y sumar el cruce con presupuesto, que el banco no da.

## 3. Análisis de alternativas

### a. Cómo marcar la compra original MSI (suma deuda, no es gasto)

| Opción | Pros | Contras |
|---|---|---|
| **A1. `kind: msi_purchase` nuevo** | Semántica explícita; no choca con toggles del usuario; se puede ocultar toggles en show. | Hay que agregarlo a 3 queries + Search (ya lo haremos con constante compartida). |
| A2. Reusar `one_time` | Ya excluido en las 3 queries de presupuesto; cero cambios SQL. | `one_time` es un toggle visible: el usuario lo apaga y la compra cuenta completa + cuotas = doble gasto. Search no lo excluye (inconsistencia ya existente). Semántica mezclada ("una vez" vs "MSI"). |
| A3. Reusar `excluded` | Existe y se respeta en las queries. | `excluded` también oculta la fila de reportes/listados para el usuario y es toggle manual; mismo riesgo de apagarlo; pierde la diferencia "gasto repartido" vs "ignorado". |

**Recomendación: A1**, con refactor mínimo: `Transaction::BUDGET_EXCLUDED_KINDS = %w[funds_movement one_time cc_payment msi_purchase]` consumido por `totals.rb`, `family_stats.rb`, `category_stats.rb`; y `Search#totals` pasa a usar la misma constante (corrige la inconsistencia actual; riesgo: cambia totales de Search para `one_time`, decisión a validar por el usuario, es corrección esperable). Ocultar los toggles `one_time`/`excluded` en filas `msi_purchase` e `installment`.

### b. Cómo las cuotas no mueven el saldo

| Opción | Pros | Contras |
|---|---|---|
| **B1. Filas `kind: installment` que los calculadores ignoran** | Cuotas visibles, editables, con categoría y fecha; presupuestos casi sin cambio. | 3 calculadores (`base`, `forward`, `reverse`) deben filtrar igual; olvidar uno desincroniza saldo. |
| B2. Flag booleano aparte | Ortogonal al kind. | Dos conceptos para lo mismo; fácil que un `kind` y un flag se contradigan. |
| B3. No crear filas; calcular virtualmente | Saldo nunca en riesgo. | No hay gasto por mes en presupuestos sin reescribir las 4 queries con UNION virtual; no se pueden editar/categorizar; contradice decisión aprobada. |

**Recomendación: B1.** Riesgos a vigilar: (1) un único scope (`Entry.affecting_balance`) usado por los 3 calculadores, con test de paridad; (2) el valor de `entries.amount` de la cuota sigue positivo para gasto, por eso el filtro es por kind y no por signo; (3) reverse calculator en cuentas no manuales: fuera de alcance, pero el scope lo cubre igual; (4) sincronizar `balances` tras generar ocurrencias (el job debe disparar `sync_later` de la cuenta una vez al final).

### c. Dónde vive la regla

| Opción | Pros | Contras |
|---|---|---|
| **C1. Tabla `recurring_transactions` + `recurring_transaction_id` y `installment_number` en `transactions`** | Una fila por regla; el índice único (regla, fecha) es limpio; editar/cancelar sin tocar historial. | Una tabla y una migración más. |
| C2. Solo columnas en `transactions` | "Solo campos extra" literal. | La "regla" sería la primera ocurrencia; cancelar/editar futuras exige consultas raras; no hay dónde guardar "último generado". |

**Recomendación: C1, mínima.** Columnas de la regla: `family`, `account`, `kind_type` (charge/msi), `name`, `amount` (total para MSI, monto para charge), `currency`, `category`, `start_date`, `day_of_month`, `total_payments` (null = sin fin), `status` (active/cancelled), `last_generated_on`. En `transactions`: `recurring_transaction_id` + `occurrence_date`, índice único. Para el usuario sigue siendo "campos extra en el formulario": la tabla es invisible para él.

### d. Dónde vive "compromisos / próximos"

| Opción | Pros | Contras |
|---|---|---|
| **D1. Sección en la cuenta de tarjeta de crédito** (`credit_cards/_overview` / pestaña de la cuenta) | MSI es por tarjeta: es donde el banco ya enseña "MSI pendientes"; reusa tabs y listas de la cuenta. | No ve suscripciones de varias cuentas juntas. |
| D2. Pestaña/filtro en Transactions index | Un solo lugar para todo; reusa search/filtros. | Mezcla pasado y futuro; la lista es de entries reales, los próximos no existen aún. |
| D3. Card en dashboard | Visibilidad máxima. | Pantalla ya cargada; más trabajo de diseño nuevo. |
| D4. Página de presupuesto | Responde "¿cuánto del ciclo está comprometido?". | El presupuesto es por ciclo, no por regla; mezcla conceptos. |

**Recomendación: primaria D1 (tarjeta), secundaria D4 en forma mínima** (una línea en el resumen del presupuesto: "Committed from installments: $X"). Se descartan D2/D3 en v1. La vista agrupa por mes: pagos restantes, cuota, saldo MSI pendiente = suma de cuotas futuras, y total comprometido por mes del ciclo.

### e. Flujo de captura

| Opción | Pros | Contras |
|---|---|---|
| **E1. Campos extra en `DS::Disclosure` del form de nueva transacción** | Mismo número de pasos + 1 campo; reuso total. | Disclosure se vuelve más larga; hay que mantenerla escaneable. |
| E2. Formulario separado "New recurring payment" | Más espacio, más claro. | Pantalla nueva; contradice P1. |

**Recomendación: E1 + conversión desde show.** En el form: selector "Repeat" (No / Every month) y, solo en cuentas de crédito, "Pay in installments" con número de meses. En `transactions/show` (donde vive el toggle `one_time`) se agrega el mismo bloque "Make recurring / Pay in installments", que convierte la transacción existente: cambia su kind (a `msi_purchase`) y genera las cuotas futuras (y pasadas con su fecha original si la compra fue hace meses). Confirmación previa con resumen de lo que cambiará.

## 4. Mapa de experiencia

| Momento | Qué pasa | Estado emocional | Consideraciones inclusivas |
|---|---|---|---|
| **Entrada** | Victor está pagando en caja con su celular, o revisa el estado de cuenta. | Prisa / ansiedad financiera | Campos grandes, táctiles; un solo campo extra sobre el flujo normal. |
| **Captura** | Escribe monto, elige tarjeta, "6 months"; ve "6 payments of $500.00". Guarda. | Confianza al ver el cálculo | Etiquetas explícitas, resultado en `aria-live`; error de meses inválidos en texto junto al campo. |
| **Mes a mes** | Contenedor estuvo apagado 3 semanas; al abrir, el job genera las cuotas pendientes con sus fechas originales. | Tranquilidad si no hay sorpresas | Mensaje discreto "2 installments were added" (no modal); sin dependencia de color. |
| **Revisar compromisos** | En la tarjeta ve MSI pendientes y compromiso por mes. | Control / claridad | Tabla semántica con encabezados; orden por fecha; resumen en texto además de números. |
| **Editar / cancelar** | Desde cualquier cuota o desde la regla: editar monto/categoría afecta solo futuras; cancelar detiene futuras, conserva las generadas. | Miedo a romper cuentas | Confirmación con texto claro de qué cambia; botón destructivo diferenciado por texto, no solo color. |
| **Fin del plan** | Última cuota generada; la regla pasa a "Completed" y sale de próximos. | Alivio | Estado anunciado en texto; el histórico sigue accesible. |

## 5. Métricas de éxito

| Métrica | Meta | Cómo medir |
|---|---|---|
| Pasos para capturar un MSI vs transacción normal | +1 campo, 0 pantallas extra | Recorrido manual |
| Cuotas generadas con fecha correcta tras apagar contenedor N semanas | 100% | Test del job de catch-up |
| Duplicados por (regla, fecha) | 0 | Índice único + test de reintento |
| Saldo tarjeta = deuda total desde día de compra | Diferencia $0 | Test de paridad de calculadores |
| Gasto idéntico en las 4 queries | Igual en todas | Test cruzado |
| Tiempo para responder "¿cuánto comprometido?" | < 5 s | Prueba con usuario |
| Trabajo en ocio atribuible | 0 jobs fuera del check diario | Log de Sidekiq |
| **Accesibilidad:** captura y revisión completables con teclado y VoiceOver; cuota calculada anunciada; sin información solo por color | 100% de tareas completables | Recorrido con teclado + VoiceOver, revisión en escala de grises |
| Familias sin recurrentes | Comportamiento idéntico | Suite existente verde |

## 6. Restricciones y trade-offs

- **Reuso sobre claridad ideal:** al meter todo en un disclosure se pierde el espacio de un formulario dedicado; lo aceptamos por P1.
- **Nuevo kind = tocar 4 queries + 3 calculadores.** Costo único; se mitiga con constante y scope compartidos y tests de paridad.
- **Corregir `Transaction::Search`** cambia totales visibles de esa pantalla para transacciones `one_time`. Se prefiere consistencia.
- **Editar solo futuras** significa que corregir una cuota ya generada se hace a mano sobre esa fila (monto bloqueado salvo fuerza); simple y predecible, a cambio de menos flexibilidad.
- **Solo mensual y cuentas manuales** en v1; el modelo (`day_of_month`, `status`) no impide ampliar.
- **Hardcode en inglés**, sin i18n (CLAUDE.md).
- **Sin liquidación anticipada ni intereses** (fuera de alcance).

## 7. Preguntas abiertas: resolución propuesta

| Pregunta | Propuesta |
|---|---|
| Nombre en UI | "Recurring payment" como concepto; "Monthly charge" y "Installments (MSI)" como tipos. Texto de apoyo: "Months without interest". Valida content-writer. |
| Dónde vive la vista | Ficha de tarjeta de crédito (primaria) + una línea en presupuesto (secundaria). |
| Editar/cancelar | Solo afecta futuras; cuotas generadas se editan individualmente. Propuesta confirmada, a validar con el usuario. |
| Convertir transacción existente | Sí, desde `transactions/show`, con confirmación y generación retroactiva con fechas originales. |
| Marcar la compra original | `kind: msi_purchase` nuevo (alternativa A1). |
| Pregunta nueva (usuario) | Al convertir una compra pasada, ¿generar retroactivamente las cuotas ya vencidas? Propuesta: sí, con su fecha original. |
