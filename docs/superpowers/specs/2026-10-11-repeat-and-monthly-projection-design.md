# Repeat dropdown + Monthly projection — Design

_Date: 2026-10-11. Branch: `feature/meses-sin-intereses`. Approved by Victor in chat (brainstorming, 2026-10-11)._

Builds on Phases A–C (see `docs/HANDOFF-recurring-payments.md`). This changes **capture** and the **budget impact block**. The model gains a frequency. Everything else stays as it is: card tab, budget block, future budgets, plan dialog, locks, generation, and the parity rules.

## Decisions (Victor)
1. **Installments merge into Repeat.** There is no separate "Installments" option and no credit-card-only rule.
   - "Ends after" empty → recurring payment.
   - "Ends after" N ≥ 2 → purchase in installments.
2. **With an end, the amount entered is the full purchase** and is split into N payments (option A).
3. **"Bimonthly" means every 2 months.** The UI label is "Every 2 months".
4. **Projection expenses:**
   - The current month uses real expenses, grouped by category.
   - Future months use each category's average spend.
   - Recurring items appear as one "Expenses in installments" segment.

## 1. Capture

Applies to the new-transaction form (`transactions/_form`, `_recurrence_fields`) and to "Convert existing" in the drawer (`transactions/recurrences/*`).

**Removed:**
- the "Recurring payment" `DS::Disclosure` and its radios (Doesn't repeat / Monthly charge / Installments);
- the credit-only note;
- the separate "Number of installments" and "First payment" fields.

**Added under "Date":** a **"Repeat"** select. Options, in order:
`None` (default), `Daily`, `Weekly`, `Monthly`, `Every 2 months`, `Quarterly`, `Every 6 months`, `Annually`.

When Repeat ≠ None, show **"Ends after [ ] payments"**. It is optional, accepts an integer, and has an upper bound:
- Recurring (empty): up to the existing charge cap of 600.
- With an end: 2–48.

**Type rule (server and client agree):**

| Repeat | Ends after | Plan | Amount means | Summary line 1 | Summary line 2 |
|---|---|---|---|---|---|
| None | — | no plan | as today | — | — |
| X | empty | `charge` | per payment | "$600.00 every {unit}" | "No end date" |
| X | N ≥ 2 | `installments` | **total purchase** | "N payments of $T/N" (last payment absorbs rounding: "last one $… on …") | "Last on {date}" |
| X | 1 | invalid | — | error "Enter 2 to 48 payments." | — |

`{unit}` values: day, week, month, 2 months, 3 months, 6 months, year. Wording: "every day", "every week", "every month", "every 2 months", "every 3 months", "every 6 months", "every year".

**First payment:**
- Recurring: the transaction itself is payment 1, on the transaction date.
- Installments: payment 1 falls one interval after the transaction date (monthly → +1 month, weekly → +1 week, and so on). There is no separate First payment field.

**Installments by account type:**
- **Credit card (manual, active):** keep the MSI accounting unchanged. The entry becomes `msi_purchase` (adds the full debt, excluded from spending), and N `installment` rows count as spending without moving the balance.
- **Any other manual, active account:**
  - The captured entry becomes **payment 1**: its amount is rewritten to the first occurrence amount (T/N), it stays kind `standard`, and it is linked with `installment_number: 1`.
  - The remaining N−1 payments are generated as `standard` rows (ordinary spending that moves the balance).
  - The plan keeps `amount = T` and `plan_type = installments`, so "Left to pay" and the remaining balance are correct.
  - Generated rows on these accounts are locked like charges: kind locked, amount editable only through the plan. They follow the same lock rules as `installment` rows. Only the credit-card variant uses the `installment` / `msi_purchase` kinds.

**Live summary:** server-rendered, same frame and debounce as today (`RecurringTransactionsController#preview`), with the new wording per frequency.

**Copy:**
- "Repeat", "None", the frequency labels, "Ends after", "payments" and the summaries above are new copy-doc strings (section §14).
- Remove `b1.type_*`, `b1.credit_only_note`, and the installments-only field labels.
- Validation messages:
  - "Enter 2 to 48 payments." for the ends-after range.
  - The existing charge-cap message.

## 2. Monthly projection

Replaces the budget-impact block in capture.

- Wrap it in a collapsible group titled **"Monthly projection"**. Same disclosure style as the old "Recurring payment" group, **closed by default**. It renders only when Repeat ≠ None and the preview is available.
- **Months shown:** the budget months of the next 3 payments still ahead (same rule as today, frequency-aware). For frequencies shorter than a month, show the next 3 budget months that contain a payment.
- **Bar per month**, sharing one scale. Segments from left to right:
  1. **"Expenses in installments":** all recurring commitments for that month (`Budget#committed_spending`, unchanged definition), in one neutral color (`bg-inverse`).
  2. **Category spend:**
     - The current budget month uses actual expenses per category.
     - Future months use each category's average monthly spend, taken from the existing budget average (the "avg" shown on future budgets).
     - Excludes rows linked to a plan (`recurring_transaction_id` present) and budget-excluded kinds, so nothing is counted twice.
     - One segment per category with spend, colored with the category's color. Uncategorized uses the neutral uncategorized color.
  3. **"This purchase"** (`bg-destructive`).
- **Bar shape:**
  - The bar container has `overflow-hidden rounded-full`, so the bar is **always rounded** at both ends whichever segment sits at the edge.
  - Segments have no per-segment radius.
  - The budget marker stays as a separate overlay outside the clipped track.
- **Legend:**
  - "Expenses in installments", then each category shown (future months mark them "avg"), then "This purchase", then "Budget".
  - With many categories, show the top 4 by amount plus "Other".
- **Header:** the red over-budget title and the subtitle stay. Over-budget now compares the total (installments + category spend + this purchase) with the basis budget.
  - Subtitle: "Budget impact of the next 3 payments".
  - Rename "installments" to "payments" in the bi.* copy where it refers to generic payments.
- Accessibility:
  - Each bar keeps an sr-only text summary: "{month}: {total} of {budget}, {over/left}".
  - Category segments are `aria-hidden`; the legend carries the meaning.

## 3. Data and model

**Migration** (Victor runs it):
- `add_column :recurring_transactions, :frequency, :string, null: false, default: "monthly"`.
- No data change: existing plans are monthly.

**`RecurringTransaction`:**
- `FREQUENCIES = { "daily" => 1.day, "weekly" => 1.week, "monthly" => 1.month, "bimonthly" => 2.months, "quarterly" => 3.months, "semiannual" => 6.months, "annual" => 1.year }`, keyed by stored value. The labels live in a helper.
- `occurrence_date(n)` advances from `start_date` by `(n-1) × interval`.
  - Month-based intervals keep the current clamping (`advance(months:)` from the anchor).
  - Day and week intervals use `advance(days:/weeks:)`.
- `plan_type` is derived at creation: `total_payments.present?` → `installments`, else `charge`. The stored column stays. Validation ranges:
  - installments: 2–48;
  - charge: blank or ≤ 600.
- `create_from_entry!` / `build_from_entry`:
  - accept `frequency` and `total_payments`, and ignore any client `plan_type`;
  - credit card vs other account as described in §1;
  - installments `start_date` = entry date + 1 interval on a credit card (the purchase stays whole); on other accounts the entry date (the purchase is payment 1);
  - charge `start_date` = entry date.
- Remove the installments-require-credit-card validation and the `:installments_credit_only` error. Eligibility rules otherwise unchanged: transfer, linked, not standard, income, manual account, foreign currency.
- `upcoming(through:)`, `generate_due!`, `remaining_*` and `end_date` all work through `occurrence_date`, so they become frequency-aware automatically. `Family::RecurringCommitments` and the budget calculations need no change beyond that.
- Lock rules: `Entry#plan_amount_unchanged` and the kind lock cover:
  - `msi_purchase` and `installment` (credit card);
  - plan-linked `standard` rows of an installments plan on other accounts (amount locked).

  Charge rows stay editable as today.

**Shared calculation for the projection:**
- Add `Budget#category_spend_for_projection` (or a small `RecurringTransaction::BudgetImpact` collaborator), returning `[{category:, amount:, estimated:}]`:
  - current month: actual non-plan expense totals per category;
  - future month: category averages (reuse the existing average query used by future budget category rows).
- `BudgetImpact::Month` gains `category_segments`, and `total` includes them. Parity with `Budget#committed_spending` for the installments segment is unchanged and stays tested.

**Params:** `RecurrenceParams` permits `recurrence[frequency, total_payments]`. `start_date` and `plan_type` are no longer client-supplied for capture.

## 4. Other surfaces
- **Plan dialog:** the subtitle shows the frequency ("12 payments of $1,250.00 · every month" / "$600.00 every week · Active"). Schedule fields stay locked (v1).
- **Card tab, budget block, rows:** wording uses the frequency where it shows "/ month" or "Per month".
  - The card tab's "Committed per month" counts the monthly-equivalent amount of non-monthly plans (weekly × occurrences in the month, as `committed_spending` already does per budget month).
  - Row labels "Installment 3 of 12" and "Monthly charge" become:
    - "Payment 3 of 12" for non-card installments;
    - "{Frequency} charge" (e.g. "Weekly charge") for charges;
    - credit-card installments keep "Installment 3 of 12".

## 5. Errors and edge cases
- Ends after = 1, 0 or negative → 422 with "Enter 2 to 48 payments." No 500 from any tampered `frequency` value: unknown frequencies are rejected with a validation error.
- A daily plan with no end can generate many rows. Generation stays lazy (once a day) and only creates due rows, so a daily plan adds one row per day.
- Rounding: the last payment absorbs the remainder. This is unchanged and applies to every frequency.

## 6. Testing
- Model:
  - `occurrence_date` for each frequency, including month-end clamping for monthly, bimonthly, quarterly, semiannual and annual;
  - plan_type derivation and ranges;
  - the non-card installments flow (entry rewritten to T/N, N−1 standard rows, remaining balance);
  - the credit-card flow unchanged;
  - weekly committed spending per budget month.
- `BudgetImpact`:
  - category segments for the current month (actuals, excluding plan rows) and for future months (averages);
  - totals and over-budget;
  - parity of the installments segment.
- Controller:
  - capture with each type;
  - Repeat None saves an ordinary transaction exactly as before;
  - invalid ends-after → 422;
  - unknown frequency → 422.
- Browser:
  - Repeat select and the conditional Ends-after field;
  - summary wording per frequency;
  - Monthly projection collapsed by default, bars always rounded, category colors and legend.
