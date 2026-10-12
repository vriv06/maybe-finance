# Repeat Dropdown + Monthly Projection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "Recurring payment" radios with a "Repeat" select (None / Daily / Weekly / Monthly / Every 2 months / Quarterly / Every 6 months / Annually) plus an optional "Ends after N payments" field. An end count turns the entry into a purchase in installments on any manual account, and no end count makes it a recurring charge. Plans gain a stored `frequency`. The capture budget-impact block becomes a collapsed "Monthly projection" whose bars are always rounded and that includes category spending.

**Architecture:** One new column, `recurring_transactions.frequency`. `RecurringTransaction#occurrence_date` becomes frequency-aware, so generation, `upcoming`, the remaining figures, `end_date`, `Family::RecurringCommitments` and the budget numbers follow it without further change. `build_from_entry` derives `plan_type` from the end count and ignores anything the client sends for it. Installments on a credit card keep the MSI accounting. On other accounts the entry becomes payment 1 (rewritten to T/N) and the plan generates the N−1 standard rows, which are locked like installments (`Transaction#plan_locked?`). The projection gets category spend from one new model method, `Budget#category_spend_for_projection`: real non-plan spending for the current month and the per-category "avg" for future months. That method feeds `RecurringTransaction::BudgetImpact`. The parity test for the installments segment stays.

**Tech Stack:** Rails 7.2, Ruby 3.4, PostgreSQL, Hotwire (Turbo 8 / turbo-rails 2.0.16, Stimulus), ViewComponent DS components, Tailwind v4 design system, Minitest + fixtures + mocha, Docker/OrbStack.

**Design sources (read before any task):**
- `docs/superpowers/specs/2026-10-11-repeat-and-monthly-projection-design.md` (the approved spec)
- `design-state.md` (decisions dated 2026-10-11)
- `docs/HANDOFF-recurring-payments.md`
- `docs/designpowers/content/2026-10-08-pagos-recurrentes-msi-copy.md`. Its "Kept" tables plus the new §14, added in Task 7, are the source of truth for copy.
- The previous plan, `docs/superpowers/plans/2026-10-08-recurring-transactions-phases-b-c.md`, for context on Phases B and C.

## Global Constraints

**Repository and code**
- Branch: `feature/meses-sin-intereses`. Phases A, B and C are merged on it: `RecurringTransaction`, the kinds `msi_purchase` / `installment`, `Family::RecurringCommitments`, `RecurringTransaction::BudgetImpact`, the capture and convert flows, the plan dialog, the card tab and future budgets.
- Business logic lives in `app/models/` (concerns and POROs). No `app/services/`.
- Minitest + fixtures only, with minimal fixtures. Build edge cases inside the test. No RSpec, no FactoryBot. Stubs use `mocha`, and `stub(...)` / `OpenStruct` for mock instances.
- No new gems, no new npm packages.

**Copy and UI**
- Hardcoded English, no i18n for new strings. Copy every user-facing string **exactly** from the copy doc "Kept" tables or from the new §14 (Task 7). Ids are cited next to strings in this plan.
- Never use the word "MSI", "cycle", or "Cancel" in new UI. The only allowed "Cancel" is `b3.confirm_secondary`.
- Icons: always the `icon` helper (`app/helpers/application_helper.rb:9`), never `lucide_icon`.
- Functional tokens only: `text-primary`, `text-secondary`, `bg-container`, `bg-container-inset`, `bg-surface-inset`, `border-tertiary`, `border-divider`, `bg-inverse`, `bg-destructive`, and so on.
  - No new tokens, no new DS components, no edits to `app/assets/tailwind/*`.
  - The single exception is the category colour. It is an inline `background-color` taken from `Category#color`, the existing pattern in `app/views/budgets/_actuals_summary.html.erb:15`.
- Build defaults (design-state.md, 2026-10-08):
  - Red text in the projection block is `text-red-700 theme-dark:text-red-400`.
  - The "This purchase" segment is `bg-destructive` in every month.
  - The "Expenses in installments" segment is `bg-inverse`.
- Hotwire-first: native `<details>`/`<dialog>`, Turbo frames, and money/date formatting on the server. Stimulus controllers stay small (< 7 targets) with declarative `data-action`, and values pass through `data-*-value`.

**Data and safety**
- Use `Current.family` / `Current.user`, never `current_family` / `current_user`. Every lookup is scoped to `Current.family`.
- The schedule is **not editable** in v1 (D12): frequency, start date, number of payments and the installments total.
- **Never 500 on tampered input.**
  - An unknown `recurrence[frequency]` gives a 422 with `r.err.frequency`.
  - A non-hash `recurrence` param reads as "no recurrence".
  - Any end count other than 2–48 gives a 422 with `r.err.payments_range`.
- New code rescues only persistence errors (`ActiveRecord::RecordInvalid`, `ActiveRecord::RecordNotUnique`). Add no new broad `rescue StandardError`.
- Families with no recurring payments must look and behave exactly as today. Repeat = None saves an ordinary transaction exactly as before.

**Migrations and running things**
- **Exactly one migration** (Task 1). Claude never runs migrations. Task 1 STOPS and asks the user to run:
  `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails db:migrate` (test database `maybe_test`) and
  `docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rails db:migrate` (default database).
  Every later task needs the column.
- Do not run `rails server`, `touch tmp/restart.txt` or `rails credentials`. Local Ruby is broken, so everything runs through Docker.
- **Docker image:** never run `docker compose ... build` without `-f docs/dev/compose.test-db.yaml`. The override tags the image `maybe-finance:dev`. A plain build overwrites `maybe-finance:local`, which production uses. Tests do not need a build because the source is bind-mounted.

**Tests and lint**
- Tests (bind-mounted live source):
  `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test <path>`
  `The "PLAID_*" variable is not set` and `[SKYLIGHT] Unable to start` are expected noise.
- Lint:
  - `docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop <files> -a`
  - `docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint <files> -a`
  - Security: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec brakeman --no-pager`. `bin/brakeman` aborts because the installed version is outdated.
  - JS: `npm run lint` on the host.
- **Baseline:** `test/models test/jobs test/controllers test/helpers test/components` has **16 failures / 118 errors** that already existed. Most are `tailwind.css` not built in the bind mount, plus `Provider::PlaidTest`. Compare **by test name, never by count**. Task 1 Step 1 records the names in `.superpowers/sdd/2026-10-11-baseline-names.txt`.
  - Prefer model, helper and job tests.
  - A controller test that renders a view sends `headers: { "Turbo-Frame" => "<frame id>" }`. turbo-rails 2.0.16 then renders its frame layout, which does not link `tailwind.css`. A turbo-stream test sends `headers: { "Accept" => "text/vnd.turbo-stream.html" }`. Redirect-only assertions need neither.
  - When an assertion contains an apostrophe, compare against `ERB::Util.html_escape("...")`.
  - Views without an automated test are checked in Task 12's browser checklist.

**Commits**
- Commit messages end with: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Never commit `.superpowers/`. It is git-excluded, but always `git add` explicit paths and never `git add -A` / `git add -f .superpowers`.

## File Map

| File | Responsibility |
|---|---|
| `db/migrate/20261011120000_add_frequency_to_recurring_transactions.rb` (create), `db/schema.rb` (regenerated by the user's migrate) | `frequency` column |
| `app/models/recurring_transaction.rb` (modify) | `FREQUENCIES`, frequency validation, frequency-aware `occurrence_date`, `plan_type` derived from the end count, card vs other-account installments, `monthly_amount` per budget month, `next_payment_amount`, `credit_card?`, `source_is_first_payment?` |
| `app/models/transaction.rb`, `app/models/entry.rb` (modify) | `Transaction#plan_locked?` drives the kind and amount locks |
| `app/models/transfer.rb`, `app/models/family/auto_transfer_matchable.rb`, `app/controllers/transfer_matches_controller.rb` (modify) | Locked payments never become transfers |
| `app/models/income_statement.rb`, `app/models/income_statement/category_stats.rb` (modify) | `exclude_recurring:` option for category actuals and averages |
| `app/models/budget.rb` (modify) | `Budget::ProjectionCategory`, `#category_spend_for_projection` |
| `app/models/recurring_transaction/budget_impact.rb` (modify) | Next 3 budget months for any frequency, category segments, legend (top 4 + Other), totals |
| `app/controllers/concerns/recurrence_params.rb` (modify) | `recurrence[frequency, total_payments]`, tamper-safe, notices |
| `app/controllers/transactions/recurrences_controller.rb` (modify) | Initial convert step built with `frequency: nil` |
| `app/helpers/recurring_transactions_helper.rb` (modify) | Frequency labels, units, charge labels, summaries, row labels, dialog subtitle, projection subtitle and screen-reader summary |
| `app/helpers/custom_confirm.rb` (modify) | Stop confirm for installments off a card |
| `app/views/transactions/_recurrence_fields.html.erb` (rewrite), `_form.html.erb` (modify) | Repeat select + conditional "Ends after" under Date |
| `app/views/transactions/recurrences/_fields.html.erb`, `_confirm.html.erb` (modify) | Convert flow (B3) with the same fields |
| `app/javascript/controllers/recurring_form_controller.js` (rewrite) | Frequency switching, debounced preview, one live region, keeps the projection open state |
| `app/views/recurring_transactions/_preview.html.erb`, `_budget_impact.html.erb` (modify) | "Monthly projection" disclosure, rounded bars, segments, legend |
| `app/views/recurring_transactions/show.html.erb`, `app/views/credit_cards/tabs/_recurring.html.erb`, `app/views/transactions/show.html.erb` (modify) | Frequency wording, lock note, `plan_locked?` |
| `docs/designpowers/content/2026-10-08-pagos-recurrentes-msi-copy.md` (modify) | New §14 |

---

### Task 1: Baseline names and the `frequency` migration

**Files:**
- Create: `db/migrate/20261011120000_add_frequency_to_recurring_transactions.rb`
- Modify (by the user's migrate run): `db/schema.rb`
- Create (git-excluded, never committed): `.superpowers/sdd/2026-10-11-baseline.log`, `.superpowers/sdd/2026-10-11-baseline-names.txt`

**Interfaces:**
- Produces: column `recurring_transactions.frequency` (string, `null: false`, default `"monthly"`). Every existing plan reads as `"monthly"`. `.superpowers/sdd/2026-10-11-baseline-names.txt` holds one failing test name per line (`ClassName#test_name`). Task 12 compares against it.

- [ ] **Step 1: Record the baseline failing test names (before any change)**

```bash
mkdir -p .superpowers/sdd
docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models test/jobs test/controllers test/helpers test/components 2>&1 | tee .superpowers/sdd/2026-10-11-baseline.log | tail -3
grep -A1 -E "^(Failure|Error):$" .superpowers/sdd/2026-10-11-baseline.log | grep "#test_" | sed -E 's/( \[[^]]*\])?:$//' | sort -u > .superpowers/sdd/2026-10-11-baseline-names.txt
wc -l .superpowers/sdd/2026-10-11-baseline-names.txt
```

Expected: the summary line reads `... 16 failures, 118 errors, 5 skips`, and the names file has 134 lines. If the counts differ, write the actual numbers in the names file header and tell the orchestrator. Do not try to fix them.

- [ ] **Step 2: Write the migration**

`db/migrate/20261011120000_add_frequency_to_recurring_transactions.rb`:

```ruby
class AddFrequencyToRecurringTransactions < ActiveRecord::Migration[7.2]
  def change
    add_column :recurring_transactions, :frequency, :string, null: false, default: "monthly"
  end
end
```

- [ ] **Step 3: STOP. Ask the user to run the migration.**

Do not run it yourself (CLAUDE.md). Send exactly this and wait for the user's confirmation:

> The migration `db/migrate/20261011120000_add_frequency_to_recurring_transactions.rb` adds `recurring_transactions.frequency` (string, not null, default "monthly"; existing plans become monthly). Please run:
> ```bash
> docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails db:migrate
> docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rails db:migrate
> ```
> The first migrates the test database (`maybe_test`) and rewrites `db/schema.rb`. The second migrates the default database. Tell me when both are done.

- [ ] **Step 4: Verify the column and the schema**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails runner 'c = RecurringTransaction.columns_hash["frequency"]; puts [c.type, c.default, c.null].inspect'
git diff db/schema.rb
```

Expected:
- The runner prints `[:string, "monthly", false]`.
- The diff shows the version line `2026_10_06_120000` → `2026_10_11_120000`.
- The diff adds `t.string "frequency", default: "monthly", null: false` inside `create_table "recurring_transactions"`, and changes nothing else.

If the diff has anything else (adapter noise), run `git checkout db/schema.rb` and make only those two edits by hand.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/20261011120000_add_frequency_to_recurring_transactions.rb db/schema.rb
git commit -m "Add frequency to recurring transactions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Frequency-aware schedule

**Files:**
- Modify: `app/models/recurring_transaction.rb`. Add constants after line 5. Add the validation after line 34. Replace `occurrence_date` (lines 118-120) and `monthly_amount` (lines 157-162). Change `schedule_unchanged` (lines 263-267).
- Test: `test/models/recurring_transaction_test.rb`, `test/models/account/recurring_commitments_test.rb`, `test/models/family/recurring_commitments_test.rb`

**Interfaces:**
- Consumes: the `frequency` column (Task 1).
- Produces:
  - `RecurringTransaction::FREQUENCIES` (`Hash{String => ActiveSupport::Duration}`, keys in UI order: `daily weekly monthly bimonthly quarterly semiannual annual`).
  - Validation `frequency` inclusion, message `"Choose how often it repeats."`.
  - `#occurrence_date(number) -> Date` (frequency-aware, month-based ones clamp from the anchor).
  - `#monthly_amount -> BigDecimal`: every payment in the budget month of the next payment. This is unchanged for monthly plans.
  - `#next_payment_amount -> BigDecimal`: the amount of the next payment, or of the last payment once all are handled.
  - The schedule lock also covers `frequency`.

- [ ] **Step 1: Write the failing tests**

Append inside `test/models/recurring_transaction_test.rb` (before `private`):

```ruby
  test "occurrence dates follow the frequency and clamp to shorter months" do
    {
      "daily" => [ Date.new(2026, 1, 31), Date.new(2026, 2, 1), Date.new(2026, 2, 2) ],
      "weekly" => [ Date.new(2026, 1, 31), Date.new(2026, 2, 7), Date.new(2026, 2, 14) ],
      "monthly" => [ Date.new(2026, 1, 31), Date.new(2026, 2, 28), Date.new(2026, 3, 31) ],
      "bimonthly" => [ Date.new(2025, 12, 31), Date.new(2026, 2, 28), Date.new(2026, 4, 30) ],
      "quarterly" => [ Date.new(2025, 11, 30), Date.new(2026, 2, 28), Date.new(2026, 5, 30) ],
      "semiannual" => [ Date.new(2025, 8, 31), Date.new(2026, 2, 28), Date.new(2026, 8, 31) ],
      "annual" => [ Date.new(2024, 2, 29), Date.new(2025, 2, 28), Date.new(2026, 2, 28) ]
    }.each do |frequency, dates|
      plan = build_plan(frequency: frequency, start_date: dates.first)

      assert_equal dates, (1..3).map { |n| plan.occurrence_date(n) }, frequency
    end
  end

  test "a weekly plan ends on its last weekly payment" do
    assert_equal Date.new(2026, 10, 15), build_plan(frequency: "weekly", start_date: Date.new(2026, 10, 1)).end_date
  end

  test "frequency must be one of the supported ones" do
    plan = build_plan(frequency: "fortnightly")

    assert_not plan.valid?
    assert_equal [ "Choose how often it repeats." ], plan.errors[:frequency]
    assert build_plan(frequency: "weekly").valid?
  end

  test "a month of a weekly plan costs every payment in the month of the next one" do
    travel_to Date.new(2026, 10, 8)
    plan = build_plan(plan_type: "charge", frequency: "weekly", amount: 50, total_payments: nil, start_date: Date.new(2026, 10, 1))
    plan.save!

    assert_equal BigDecimal("250"), plan.monthly_amount # Oct 1, 8, 15, 22, 29
    assert_equal BigDecimal("50"), plan.next_payment_amount
  end
```

In the existing test `"the schedule can't change after the plan is created"`, add one line after `assert_not plan.update(total_payments: 6)`:

```ruby
    assert_not plan.reload.update(frequency: "weekly")
```

In the existing test `"ended_on and monthly_amount describe the plan"`, add after the `monthly_amount` assertion:

```ruby
    assert_equal BigDecimal("333.33"), plan.next_payment_amount
```

Append inside `test/models/account/recurring_commitments_test.rb` (before `private`, or before the final `end` if there is no `private`):

```ruby
  test "committed per month counts every payment a weekly plan makes in a month" do
    @family.recurring_transactions.create!(account: @card, name: "Cleaner", plan_type: "charge", frequency: "weekly",
                                           amount: 50, currency: "USD", start_date: Date.new(2026, 10, 1))

    assert_equal BigDecimal("1549"), @card.recurring_commitments.committed_per_month # 1,299 + 5 × 50
  end
```

In `test/models/family/recurring_commitments_test.rb`, give the private `create_charge` helper a `frequency:` keyword:

```ruby
    def create_charge(name:, amount:, start_date:, category: nil, frequency: "monthly")
      @family.recurring_transactions.create!(
        account: @card, name: name, plan_type: "charge", frequency: frequency, amount: amount, currency: "USD",
        start_date: start_date, category: category
      )
    end
```

and append before `private`:

```ruby
  test "a weekly charge commits every payment in a budget month" do
    create_charge(name: "Cleaner", amount: 50, start_date: Date.new(2026, 10, 1), frequency: "weekly")

    november = Budget.for_cycle(@family, Date.new(2026, 11, 1))

    assert_equal BigDecimal("200"), november.committed_spending # Nov 5, 12, 19, 26
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/recurring_transaction_test.rb test/models/account/recurring_commitments_test.rb test/models/family/recurring_commitments_test.rb`

Expected: FAIL.
- The daily/weekly/… dates come out monthly.
- `"fortnightly"` is valid.
- `NoMethodError: undefined method 'next_payment_amount'`.
- The weekly `monthly_amount` is 50, so committed per month is 1349.
- November commits 50 instead of 200, because `occurrence_date` is still monthly.
- The frequency update succeeds.

- [ ] **Step 3: Implement**

In `app/models/recurring_transaction.rb`, below `MAX_CHARGE_PAYMENTS = 600` (line 5):

```ruby
  # How far apart payments are, keyed by the stored value; the UI labels live in RecurringTransactionsHelper
  FREQUENCIES = {
    "daily" => 1.day,
    "weekly" => 1.week,
    "monthly" => 1.month,
    "bimonthly" => 2.months,
    "quarterly" => 3.months,
    "semiannual" => 6.months,
    "annual" => 1.year
  }.freeze
```

Below `validates :plan_type, inclusion: { in: PLAN_TYPES }` (line 34):

```ruby
  validates :frequency, inclusion: { in: FREQUENCIES.keys, message: "Choose how often it repeats." }
```

Replace `occurrence_date` (lines 118-120):

```ruby
  # Advances from the first payment, so month-based frequencies clamp without drifting
  # (monthly from Jan 31: Feb 28, then Mar 31)
  def occurrence_date(number)
    start_date + FREQUENCIES.fetch(frequency) * (number - 1)
  end
```

Replace `monthly_amount` (lines 157-162):

```ruby
  # What one budget month of this plan costs: every payment in the month of the next one
  # (a single payment for monthly and longer frequencies)
  def monthly_amount
    anchor = next_payment_number
    month_start, month_end = family.cycle_range_containing(occurrence_date(anchor))

    first = anchor
    first -= 1 while first > 1 && occurrence_date(first - 1) >= month_start
    last = anchor
    last += 1 while (total_payments.nil? || last < total_payments) && occurrence_date(last + 1) <= month_end

    (first..last).sum(BigDecimal("0")) { |number| occurrence_amount(number) }
  end

  # The next payment's amount (the last one's once every payment is handled)
  def next_payment_amount
    occurrence_amount(next_payment_number)
  end
```

Add as the first method under `private`:

```ruby
    def next_payment_number
      [ last_handled_number + 1, total_payments ].compact.min
    end
```

In `schedule_unchanged` (lines 263-267), make the condition:

```ruby
      changed_schedule = will_save_change_to_start_date? || will_save_change_to_total_payments? ||
                         will_save_change_to_frequency? || will_save_change_to_plan_type? ||
                         (installments? && will_save_change_to_amount?)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/recurring_transaction_test.rb test/models/account/recurring_commitments_test.rb test/models/family/recurring_commitments_test.rb test/models/budget_test.rb test/models/recurring_transaction/budget_impact_test.rb`

Expected: PASS. Every existing test still passes, because existing plans default to `"monthly"`.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/models/recurring_transaction.rb test/models/recurring_transaction_test.rb test/models/account/recurring_commitments_test.rb test/models/family/recurring_commitments_test.rb -a
git add app/models/recurring_transaction.rb test/models/recurring_transaction_test.rb test/models/account/recurring_commitments_test.rb test/models/family/recurring_commitments_test.rb
git commit -m "Make recurring schedules frequency-aware

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Capture rules: plan type from the end count, installments on any account

**Files:**
- Modify: `app/models/recurring_transaction.rb`
  - Validations block (lines 37-42).
  - Class methods `build_from_entry` / `create_from_entry!` / `first_payment_date` (lines 63-108).
  - `backfill_count`, and the private validations `total_payments_in_range`, `installment_amount_large_enough`, `installments_require_credit_card`, `first_payment_not_before_purchase`.
  - `create_occurrence` and `release_transactions`.
- Modify: `app/controllers/concerns/recurrence_params.rb` (whole file)
- Modify: `app/controllers/transactions/recurrences_controller.rb:13`
- Test: `test/models/recurring_transaction_test.rb`, `test/models/family/recurring_commitments_test.rb`, `test/controllers/transactions_controller_test.rb`, `test/controllers/transactions/recurrences_controller_test.rb`, `test/controllers/recurring_transactions_controller_test.rb`
- Test (call sites only): `test/models/recurring_transaction/budget_impact_test.rb`, `test/models/account/recurring_commitments_test.rb`, `test/controllers/credit_card_recurring_tab_test.rb`, `test/helpers/recurring_transactions_helper_test.rb`, `test/helpers/custom_confirm_test.rb`

**Interfaces:**
- Consumes: `FREQUENCIES`, frequency-aware `occurrence_date` (Task 2).
- Produces:
  - `RecurringTransaction.build_from_entry(entry, frequency:, total_payments: nil) -> RecurringTransaction`. It never takes `plan_type` or `start_date`. `plan_type` is `"installments"` when `total_payments.presence`, otherwise `"charge"`.
  - `RecurringTransaction.create_from_entry!(entry, frequency:, total_payments: nil)` with the same keywords.
  - `#credit_card? -> Boolean`.
  - `#source_is_first_payment? -> Boolean`. True for charges and for installments off a card. Card installments keep the purchase apart as `msi_purchase`.
  - `#first_payment_date_after(date) -> Date`. One interval after `date` for card installments, `date` otherwise.
  - Messages:
    - `"Enter 2 to 48 payments."` (installments range).
    - `"Too small to split into N payments. Use fewer."`
    - `"Enter a whole number, or leave it empty."` is kept for stored charges with an end.
  - Installments off a card:
    - The entry amount becomes `occurrence_amount(1)`. It stays `standard` and gets `installment_number: 1`.
    - Generated rows are `standard`.
    - Destroying the plan only unlinks the rows.
  - `RecurrenceParams#recurrence_params` permits only `:frequency, :total_payments`. A non-hash `recurrence` reads as empty.
  - `#recurrence_requested?` is true when `frequency` is present.
  - `#recurrence_attributes -> { frequency: String, total_payments: String | nil }`.

- [ ] **Step 1: Update existing call sites to the new keywords (mechanical)**

```bash
perl -pi -e 'if (/recurrence: \{|from_entry|\@installments = /) { s/plan_type: "installments", (total_payments: "?\d*"?), start_date: "[^"]*"/frequency: "monthly", $1/g; s/plan_type: "installments"/frequency: "monthly"/g; s/plan_type: "charge"/frequency: "monthly"/g; s/plan_type: ""/frequency: ""/g }' \
  test/models/recurring_transaction_test.rb test/models/recurring_transaction/budget_impact_test.rb \
  test/models/family/recurring_commitments_test.rb test/models/account/recurring_commitments_test.rb \
  test/controllers/credit_card_recurring_tab_test.rb test/controllers/transactions_controller_test.rb \
  test/controllers/transactions/recurrences_controller_test.rb test/controllers/recurring_transactions_controller_test.rb \
  test/helpers/recurring_transactions_helper_test.rb test/helpers/custom_confirm_test.rb
grep -rnE "plan_type" test | grep -E "recurrence: \{|from_entry|@installments ="
```

Expected: the final grep prints nothing. Direct `RecurringTransaction.new(... plan_type: ...)` / `.create!(... plan_type: ...)` calls are intentionally left alone, because the column stays.

- [ ] **Step 2: Rewrite the tests whose meaning changes, and add the new failing tests**

`test/models/recurring_transaction_test.rb`:

Replace the test `"installments require a credit card and at least two payments"` with:

```ruby
  test "installments need at least two payments, on any manual account" do
    assert build_plan.valid?
    assert build_plan(account: accounts(:depository)).valid?

    one_payment = build_plan(total_payments: 1)
    assert_not one_payment.valid?
    assert_includes one_payment.errors.attribute_names, :total_payments
  end
```

Replace the test `"validation messages are the interface copy"` with:

```ruby
  test "validation messages are the interface copy" do
    assert_equal [ "Enter 2 to 48 payments." ], build_plan(total_payments: 49).tap(&:validate).errors[:total_payments]
    assert_equal [ "Too small to split into 6 payments. Use fewer." ],
                 build_plan(amount: BigDecimal("0.05"), total_payments: 6).tap(&:validate).errors[:total_payments]
    assert_equal [ "Enter a whole number, or leave it empty." ],
                 build_plan(plan_type: "charge", total_payments: "abc").tap(&:validate).errors[:total_payments]
  end
```

Delete the test `"the first payment can't be missing or before the purchase"`. There is no first-payment field any more, and the start is derived.

Replace the test `"backfill_count counts past occurrences except a charge's own first payment"` with:

```ruby
  test "backfill_count leaves out the source transaction when it is payment 1" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: @credit_card, amount: 3000, date: Date.new(2026, 7, 8))
    other = create_transaction(account: accounts(:depository), amount: 3000, date: Date.new(2026, 7, 8))

    card_installments = RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: 6)
    charge = RecurringTransaction.build_from_entry(purchase, frequency: "monthly")
    other_installments = RecurringTransaction.build_from_entry(other, frequency: "monthly", total_payments: 6)

    assert_equal 3, card_installments.backfill_count  # Aug 8, Sep 8, Oct 8
    assert_equal 3, charge.backfill_count             # Jul 8 is the purchase itself
    assert_equal 3, other_installments.backfill_count # Jul 8 is payment 1
  end
```

Append before `private`:

```ruby
  test "an end count makes installments and no end makes a charge" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: @credit_card, amount: 1200, date: Date.new(2026, 10, 8))

    charge = RecurringTransaction.build_from_entry(purchase, frequency: "weekly")
    card_installments = RecurringTransaction.build_from_entry(purchase, frequency: "weekly", total_payments: "4")

    assert charge.charge?
    assert_equal Date.new(2026, 10, 8), charge.start_date
    assert card_installments.installments?
    assert_equal Date.new(2026, 10, 15), card_installments.start_date # one interval after the purchase
  end

  test "end counts must be 2 to 48 on any account" do
    purchase = create_transaction(account: accounts(:depository), amount: 1200, date: Date.new(2026, 10, 8))

    [ "1", "0", "-3", "49", "abc" ].each do |count|
      plan = RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: count)

      assert_equal [ "Enter 2 to 48 payments." ], plan.tap(&:validate).errors[:total_payments], count
    end
    assert RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: "3").valid?
  end

  test "an unknown frequency is a validation error, not an exception" do
    purchase = create_transaction(account: @credit_card, amount: 100, date: Date.new(2026, 10, 8))
    plan = RecurringTransaction.build_from_entry(purchase, frequency: "fortnightly", total_payments: "3")

    assert_not plan.valid?
    assert_equal [ "Choose how often it repeats." ], plan.errors[:frequency]
    assert_equal purchase.date, plan.start_date
  end

  test "installments off a card turn the purchase into payment 1 of standard payments" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: accounts(:depository), amount: 1000, name: "Sofa", date: Date.new(2026, 8, 20))

    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)

    purchase.reload
    assert_equal BigDecimal("333.33"), purchase.amount
    assert purchase.entryable.standard?
    assert_equal 1, purchase.entryable.installment_number
    assert_equal BigDecimal("1000"), plan.amount
    assert_equal Date.new(2026, 8, 20), plan.start_date
    assert_equal [ 1, 2 ], plan.transactions.order(:installment_number).pluck(:installment_number)
    assert plan.transactions.all?(&:standard?)
    assert_equal 1, plan.remaining_payments
    assert_equal BigDecimal("333.34"), plan.remaining_balance
    assert_equal Date.new(2026, 10, 20), plan.end_date
  end

  test "destroying an installments plan off a card keeps its payments" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: accounts(:depository), amount: 900, date: Date.new(2026, 8, 20))
    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)

    assert_no_difference -> { Entry.count } do
      plan.destroy!
    end
    assert_nil purchase.entryable.reload.recurring_transaction_id
  end
```

Append before `private` in `test/models/family/recurring_commitments_test.rb`:

```ruby
  test "installments off a card commit every payment, the purchase included" do
    purchase = create_transaction(account: accounts(:depository), amount: 900, name: "Sofa", date: Date.new(2026, 8, 20))
    RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3) # Aug 20 (the purchase), Sep 20, Oct 20

    commitments = @family.recurring_commitments(start_date: Date.new(2026, 8, 1), end_date: Date.new(2026, 10, 31))

    assert_equal [ 1, 2, 3 ], commitments.items.map(&:number)
    assert_equal BigDecimal("900"), commitments.total
  end
```

`test/controllers/transactions_controller_test.rb`:
- In `"an invalid plan saves nothing and explains why"`, change `"Enter 2 to 48 installments."` to `"Enter 2 to 48 payments."`. Its view assertions stay until Task 8.
- Replace the test `"an out-of-range monthly charge count is refused, not a 500"` with:

```ruby
  test "an out-of-range end count is refused, not a 500" do
    travel_to Date.new(2026, 10, 8)

    assert_no_difference [ "Entry.count", "RecurringTransaction.count" ] do
      post transactions_url, params: {
        entry: recurring_entry_params(accounts(:depository), amount: 50),
        recurrence: { frequency: "monthly", total_payments: "3000000000" }
      }, headers: { "Turbo-Frame" => "modal" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Enter 2 to 48 payments."
  end
```

- Replace the test `"installments are refused on accounts that aren't credit cards"` with these four:

```ruby
  test "installments on an account that isn't a card become ordinary payments" do
    travel_to Date.new(2026, 10, 8)

    assert_difference "RecurringTransaction.count", 1 do
      post transactions_url, params: {
        entry: recurring_entry_params(accounts(:depository), amount: 1200),
        recurrence: { frequency: "monthly", total_payments: "3" }
      }
    end

    entry = Entry.find_by!(name: "iPad Air")
    assert entry.transaction.standard?
    assert_equal BigDecimal("400"), entry.amount
    assert_equal 1, entry.transaction.installment_number
    assert_equal BigDecimal("1200"), entry.transaction.recurring_transaction.amount
  end

  test "a client plan type is ignored: no end count means a recurring charge" do
    travel_to Date.new(2026, 10, 8)

    post transactions_url, params: {
      entry: recurring_entry_params(accounts(:credit_card), amount: 300),
      recurrence: { frequency: "weekly", plan_type: "installments", start_date: "2027-01-01" }
    }

    plan = Entry.find_by!(name: "iPad Air").transaction.recurring_transaction
    assert plan.charge?
    assert_equal "weekly", plan.frequency
    assert_equal Date.new(2026, 10, 8), plan.start_date
  end

  test "an unknown frequency is refused, not a 500" do
    travel_to Date.new(2026, 10, 8)

    assert_no_difference [ "Entry.count", "RecurringTransaction.count" ] do
      post transactions_url, params: {
        entry: recurring_entry_params(accounts(:credit_card), amount: 300),
        recurrence: { frequency: "fortnightly" }
      }, headers: { "Turbo-Frame" => "modal" }
    end

    assert_response :unprocessable_entity
  end

  test "a tampered recurrence param creates an ordinary transaction" do
    assert_difference "Entry.count", 1 do
      assert_no_difference "RecurringTransaction.count" do
        post transactions_url, params: { entry: recurring_entry_params(accounts(:depository), amount: 50), recurrence: "foo" }
      end
    end

    assert_equal "Transaction created", flash[:notice]
  end
```

`test/controllers/transactions/recurrences_controller_test.rb`:
- In `setup`, change the entry date to `Date.new(2026, 7, 20)`. With the derived first payment of Aug 20, the purchase still backfills two installments (Aug 20, Sep 20), as the confirm and convert tests expect.
- In `"review shows field errors without saving"`, change `"Enter 2 to 48 installments."` to `"Enter 2 to 48 payments."`.
- Delete the test `"an unparseable start date renders the fields with 422 and saves nothing"`.

`test/controllers/recurring_transactions_controller_test.rb`: replace the test `"preview stays empty while data is missing"` with:

```ruby
  test "preview stays empty while data is missing" do
    get preview_recurring_transactions_url, params: {
      entry: { account_id: @card.id, amount: "", currency: "USD", date: "2026-10-08" },
      recurrence: { frequency: "monthly", total_payments: "12" }
    }, headers: @frame

    assert_response :success
    assert_includes response.body, %(<turbo-frame id="recurring_preview">)
    assert_not_includes response.body, "installments of"
    assert_not_includes response.body, "payments of"
  end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/recurring_transaction_test.rb test/models/family/recurring_commitments_test.rb test/controllers/transactions_controller_test.rb test/controllers/transactions/recurrences_controller_test.rb test/controllers/recurring_transactions_controller_test.rb`

Expected: FAIL.
- `ArgumentError: unknown keyword: :frequency` from `build_from_entry` / `create_from_entry!`.
- Controller posts with `frequency` are treated as "no recurrence".
- `recurrence: "foo"` raises `NoMethodError` (500).

- [ ] **Step 4: Implement the model**

In `app/models/recurring_transaction.rb`:

Validations block (lines 37-42) becomes. Remove `installments_require_credit_card` and `first_payment_not_before_purchase`:

```ruby
  validate :total_payments_in_range
  validate :installment_amount_large_enough
  validate :account_manual_and_active, on: :create
  validate :source_entry_eligible, on: :create
  validate :schedule_unchanged, on: :update
```

Replace `build_from_entry`, `create_from_entry!` and the private class method `first_payment_date` (lines 63-108, up to and including the `end` of `class << self`) with:

```ruby
    # The plan type follows the end count: an end means a purchase in installments (the amount entered is the
    # total), no end means a recurring charge (the amount is per payment). Clients never choose it.
    def build_from_entry(entry, frequency:, total_payments: nil)
      source = entry.entryable
      total_payments = total_payments.presence

      plan = new(
        source_entry: entry,
        family: entry.account.family,
        account: entry.account,
        name: entry.name,
        category: source.try(:category),
        merchant: source.try(:merchant),
        frequency: frequency,
        plan_type: total_payments ? "installments" : "charge",
        amount: entry.amount,
        currency: entry.currency,
        total_payments: total_payments
      )
      plan.start_date = plan.first_payment_date_after(entry.date)
      plan
    end

    def create_from_entry!(entry, **attributes)
      transaction do
        plan = build_from_entry(entry, **attributes)
        plan.save!

        source = entry.entryable
        if plan.source_is_first_payment?
          # Installments off a card: the purchase becomes payment 1, so it keeps only its share of the total
          if plan.installments?
            entry.update!(amount: plan.occurrence_amount(1))
            entry.sync_account_later
          end
          source.update!(recurring_transaction: plan, installment_number: 1)
        else
          source.update!(kind: "msi_purchase", recurring_transaction: plan)
        end

        plan.generate_due!
        plan
      end
    end
  end
```

Below `charge?` (after line 116), add:

```ruby
  def credit_card?
    account&.credit_card? || false
  end

  # Card installments keep the purchase apart (msi_purchase adds the debt); every other plan counts
  # its source transaction as payment 1
  def source_is_first_payment?
    charge? || !credit_card?
  end

  # Card installments start one interval after the purchase; otherwise the purchase is payment 1
  def first_payment_date_after(date)
    return date if date.nil? || source_is_first_payment? || !FREQUENCIES.key?(frequency)

    date + FREQUENCIES.fetch(frequency)
  end
```

`backfill_count` body becomes:

```ruby
  # Occurrences that saving this plan adds with past dates (payment 1 is the source transaction unless it's a card purchase)
  def backfill_count(as_of: family.today)
    upcoming(through: as_of).count { |occurrence| !source_is_first_payment? || occurrence.number > 1 }
  end
```

In `total_payments_in_range`, change the installments message:

```ruby
          errors.add(:total_payments, "Enter 2 to #{MAX_INSTALLMENTS} payments.")
```

In `installment_amount_large_enough`, change the message:

```ruby
      errors.add(:total_payments, "Too small to split into #{total_payments} payments. Use fewer.")
```

Delete the private methods `installments_require_credit_card` and `first_payment_not_before_purchase`.

In `create_occurrence`, the kind becomes:

```ruby
            kind: source_is_first_payment? ? "standard" : "installment",
```

`release_transactions` first line becomes:

```ruby
      return if source_is_first_payment? # charges and installments off a card: payments stay, unlinked (dependent: :nullify)
```

- [ ] **Step 5: Implement the params concern and the convert controller**

Replace `app/controllers/concerns/recurrence_params.rb` with:

```ruby
# The virtual `recurrence[...]` params of the capture and convert forms (kept out of entry params)
module RecurrenceParams
  extend ActiveSupport::Concern

  private
    # A tampered `recurrence=foo` (not a hash) reads as "no recurrence" instead of raising.
    # plan_type and start_date are derived by the model, never taken from the client.
    def recurrence_params
      raw = params[:recurrence]
      raw.is_a?(ActionController::Parameters) ? raw.permit(:frequency, :total_payments) : ActionController::Parameters.new.permit
    end

    # Repeat isn't None. An unknown frequency still counts, so the plan reports it (422, never a 500)
    def recurrence_requested?
      recurrence_params[:frequency].present?
    end

    def recurrence_attributes
      { frequency: recurrence_params[:frequency].to_s, total_payments: recurrence_params[:total_payments].presence }
    end

    def recurrence_notice(plan)
      plan.installments? ? "Split into #{plan.total_payments} installments." : "Monthly charge started."
    end
end
```

(`recurrence_notice` changes in Task 7.)

In `app/controllers/transactions/recurrences_controller.rb:13`:

```ruby
      @recurrence = RecurringTransaction.build_from_entry(@entry, frequency: nil)
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models test/controllers/transactions_controller_test.rb test/controllers/transactions/recurrences_controller_test.rb test/controllers/recurring_transactions_controller_test.rb test/controllers/credit_card_recurring_tab_test.rb test/helpers`

Expected: PASS for every test touched here. Other failures must be baseline names only:

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models test/controllers test/helpers 2>&1 | grep -A1 -E "^(Failure|Error):$" | grep "#test_" | sed -E 's/( \[[^]]*\])?:$//' | sort -u | comm -23 - .superpowers/sdd/2026-10-11-baseline-names.txt
```

This must print nothing.

- [ ] **Step 7: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/models/recurring_transaction.rb app/controllers/concerns/recurrence_params.rb app/controllers/transactions/recurrences_controller.rb test -a
git add app/models/recurring_transaction.rb app/controllers/concerns/recurrence_params.rb app/controllers/transactions/recurrences_controller.rb test
git commit -m "Derive the plan type from the end count and allow installments on any account

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Lock the payments of installments off a card

**Files:**
- Modify: `app/models/transaction.rb` (add `plan_locked?`, use it in `plan_kind_unchanged`, lines 57-62)
- Modify: `app/models/entry.rb:104-112` (`plan_amount_unchanged`)
- Modify: `app/models/transfer.rb:133-137` (`transfer_excludes_installment_plan_transactions`)
- Modify: `app/models/family/auto_transfer_matchable.rb:38`
- Modify: `app/controllers/transfer_matches_controller.rb:12`
- Modify: `app/views/transactions/show.html.erb:8`
- Test: `test/models/recurring_transaction_test.rb`, `test/models/family/auto_transfer_matchable_test.rb`, `test/controllers/transactions_controller_test.rb`

**Interfaces:**
- Consumes: installments off a card (Task 3). Their rows are `standard`, linked, and have an `installment_number`.
- Produces:
  - `Transaction#plan_locked? -> Boolean`. True for `msi_purchase` / `installment`, and for any plan-linked row (with an `installment_number`) of an installments plan.
  - Kind lock and amount lock (`"Set by the plan."`) cover those rows.
  - They are never matched as transfers.
  - The drawer hides Exclude / One-time / Transfer matcher on them, and shows the locked amount.
  - Charge rows stay editable.

- [ ] **Step 1: Write the failing tests**

Append before `private` in `test/models/recurring_transaction_test.rb`:

```ruby
  test "payments of installments off a card are locked like installments; charge rows are not" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: accounts(:depository), amount: 900, name: "Sofa", date: Date.new(2026, 8, 20))
    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)
    payment = plan.transactions.find_by(installment_number: 2).entry

    assert payment.entryable.plan_locked?
    assert purchase.reload.entryable.plan_locked?
    assert_not payment.update(amount: 5)
    assert_equal [ "Set by the plan." ], payment.errors[:amount]
    assert_not payment.reload.entryable.update(kind: "one_time")
    assert payment.reload.update(date: Date.new(2026, 9, 21))

    gym = create_transaction(account: accounts(:depository), amount: 50, name: "Gym", date: Date.new(2026, 10, 1))
    RecurringTransaction.create_from_entry!(gym, frequency: "monthly")
    assert_not gym.reload.entryable.plan_locked?
    assert gym.update(amount: 60)
  end
```

Append before the final `end` in `test/models/family/auto_transfer_matchable_test.rb`:

```ruby
  test "does not match payments of an installments plan off a card" do
    purchase = create_transaction(date: Date.current, account: @depository, amount: 1500, name: "Sofa")
    RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3) # becomes payment 1 of $500
    inflow = create_transaction(date: Date.current, account: @credit_card, amount: -500)

    assert_no_difference -> { Transfer.count } do
      @family.auto_match_transfers!
    end

    transfer = Transfer.new(inflow_transaction: inflow.entryable, outflow_transaction: purchase.reload.entryable)
    assert_not transfer.valid?
    assert_includes transfer.errors[:base], "This is part of a recurring payment, so it can't be a transfer."
  end
```

Append before `private` in `test/controllers/transactions_controller_test.rb`:

```ruby
  test "the drawer of a payment off a card locks it like an installment" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: accounts(:depository), amount: 900, name: "Sofa", date: Date.new(2026, 8, 20))
    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)
    payment = plan.transactions.find_by(installment_number: 2).entry

    get transaction_url(payment), headers: { "Turbo-Frame" => "drawer" }

    assert_response :success
    assert_includes response.body, "Set by the plan."
    assert_not_includes response.body, "One-time Expense"
    assert_not_includes response.body, "Open matcher"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/recurring_transaction_test.rb test/models/family/auto_transfer_matchable_test.rb test/controllers/transactions_controller_test.rb`

Expected: FAIL.
- `undefined method 'plan_locked?'`.
- The auto-matcher creates a transfer, so the count changes by 1.
- The drawer shows "One-time Expense".

- [ ] **Step 3: Implement**

`app/models/transaction.rb`. Add above `private`:

```ruby
  # Rows the plan owns: the card purchase and its installments, and every payment of an installments
  # plan on other accounts. Their kind and amount only change through the plan. Charge rows stay editable.
  def plan_locked?
    return true if PLAN_LOCKED_KINDS.include?(kind_in_database)
    return false if recurring_transaction_id_in_database.nil? || installment_number_in_database.nil?

    RecurringTransaction.where(id: recurring_transaction_id_in_database, plan_type: "installments").exists?
  end
```

`plan_kind_unchanged` becomes:

```ruby
    def plan_kind_unchanged
      return if @releasing_from_plan || !will_save_change_to_kind?
      return unless plan_locked?

      errors.add(:kind, "This is part of a recurring payment, so it can't be one-time.")
    end
```

`app/models/entry.rb`. `plan_amount_unchanged` becomes:

```ruby
    # Plan-owned rows (installments, the card purchase, payments of installments off a card) keep the amount the plan set
    def plan_amount_unchanged
      return unless transaction? && will_save_change_to_amount?

      if entryable.kind_in_database == "msi_purchase"
        errors.add(:amount, "To change it, delete this purchase and add it again.")
      elsif entryable.plan_locked?
        errors.add(:amount, "Set by the plan.")
      end
    end
```

`app/models/transfer.rb`. In `transfer_excludes_installment_plan_transactions`:

```ruby
      if [ inflow_transaction, outflow_transaction ].compact.any?(&:plan_locked?)
```

`app/models/family/auto_transfer_matchable.rb`. Right after the existing line 38 (`.where.not("inflow_transactions.kind IN (:kinds) ...`), add:

```ruby
      .where("
        NOT EXISTS (
          SELECT 1 FROM recurring_transactions locked_plans
          WHERE locked_plans.plan_type = 'installments'
            AND locked_plans.id IN (inflow_transactions.recurring_transaction_id, outflow_transactions.recurring_transaction_id)
        )
      ")
```

`IN (NULL, NULL)` is never true, so rows without a plan are unaffected.

`app/controllers/transfer_matches_controller.rb:12`:

```ruby
    if @entry.transaction.plan_locked?
```

`app/views/transactions/show.html.erb:8`:

```erb
    <% locked = @entry.transaction.plan_locked? %>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/recurring_transaction_test.rb test/models/family/auto_transfer_matchable_test.rb test/models/transfer_test.rb test/controllers/transactions_controller_test.rb test/controllers/transfer_matches_controller_test.rb`

Expected: PASS, apart from baseline names.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/models/transaction.rb app/models/entry.rb app/models/transfer.rb app/models/family/auto_transfer_matchable.rb app/controllers/transfer_matches_controller.rb test/models/recurring_transaction_test.rb test/models/family/auto_transfer_matchable_test.rb test/controllers/transactions_controller_test.rb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/transactions/show.html.erb -a
git add app/models/transaction.rb app/models/entry.rb app/models/transfer.rb app/models/family/auto_transfer_matchable.rb app/controllers/transfer_matches_controller.rb app/views/transactions/show.html.erb test/models/recurring_transaction_test.rb test/models/family/auto_transfer_matchable_test.rb test/controllers/transactions_controller_test.rb
git commit -m "Lock the payments of installment plans on accounts that aren't cards

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Category spend for the projection

**Files:**
- Modify: `app/models/income_statement.rb`: `expense_totals` (line 27), `median_expense` (line 35), `build_period_total` (line 69), `category_stats` (line 113).
- Modify: `app/models/income_statement/category_stats.rb`: `initialize` (line 2), the SQL `WHERE` (line 51).
- Modify: `app/models/budget.rb`. Add a constant after line 5, a public method after `commitments_percent` (line 364), and private methods.
- Test: `test/models/budget_test.rb`

**Interfaces:**
- Produces:
  - `IncomeStatement#expense_totals(period: nil, exclude_recurring: false)`.
  - `IncomeStatement#median_expense(interval: "month", category: nil, exclude_recurring: false)`.
  - `IncomeStatement::CategoryStats.new(family, interval:, cycle_offset:, exclude_recurring: false)`.
  - `exclude_recurring: true` drops rows with a `recurring_transaction_id`. Budget-excluded kinds are already dropped.
  - `Budget::ProjectionCategory = Data.define(:category, :amount, :estimated)`.
  - `Budget#category_spend_for_projection -> Array<Budget::ProjectionCategory>`, with amount > 0, sorted by amount descending, and top-level expense categories plus Uncategorized (a parent includes its subcategories).
  - Current month: real non-plan spending, with `estimated: false`.
  - Future month: the monthly median per category, with plan rows left out and `estimated: true`. This is the figure future budget rows label "avg" (`budget_categories/_budget_category.html.erb:40`).

- [ ] **Step 1: Write the failing tests**

Append before the final `end` of `test/models/budget_test.rb`. `@family` is `families(:empty)`, so the data is deterministic:

```ruby
  test "projection spend is real for the current month and leaves plan rows and excluded kinds out" do
    travel_to Date.new(2026, 10, 8)
    account = Account.create!(family: @family, accountable: Depository.new, name: "Checking", status: "active", currency: "USD", balance: 0)
    food = @family.categories.create!(name: "Food", color: "#e99537", lucide_icon: "utensils", classification: "expense")
    create_transaction(account: account, date: Date.new(2026, 10, 2), amount: 40, category: food)
    create_transaction(account: account, date: Date.new(2026, 10, 3), amount: 15)
    create_transaction(account: account, date: Date.new(2026, 10, 4), amount: 70, category: food, kind: "one_time")
    rent = create_transaction(account: account, date: Date.new(2026, 10, 5), amount: 900, category: food)
    RecurringTransaction.create_from_entry!(rent, frequency: "monthly")

    rows = Budget.for_cycle(@family, Date.new(2026, 10, 1)).category_spend_for_projection

    assert_equal [ "Food", "Uncategorized" ], rows.map { |row| row.category.name }
    assert_equal [ BigDecimal("40"), BigDecimal("15") ], rows.map(&:amount)
    assert rows.none?(&:estimated)
  end

  test "projection spend for a future month is each category's average without plan rows" do
    travel_to Date.new(2026, 10, 8)
    account = Account.create!(family: @family, accountable: Depository.new, name: "Checking", status: "active", currency: "USD", balance: 0)
    food = @family.categories.create!(name: "Food", color: "#e99537", lucide_icon: "utensils", classification: "expense")
    snacks = @family.categories.create!(name: "Snacks", color: "#4da568", lucide_icon: "cookie", classification: "expense", parent: food)
    create_transaction(account: account, date: Date.new(2026, 9, 10), amount: 60, category: food)
    create_transaction(account: account, date: Date.new(2026, 9, 12), amount: 20, category: snacks)
    gym = create_transaction(account: account, date: Date.new(2026, 9, 15), amount: 500, category: food)
    RecurringTransaction.create_from_entry!(gym, frequency: "monthly")

    rows = Budget.for_cycle(@family, Date.new(2026, 12, 1)).category_spend_for_projection

    assert_equal [ "Food" ], rows.map { |row| row.category.name }
    assert_equal [ BigDecimal("80") ], rows.map(&:amount) # 60 + its subcategory's 20; the gym charge is a commitment
    assert rows.all?(&:estimated)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/budget_test.rb`

Expected: FAIL with `NoMethodError: undefined method 'category_spend_for_projection'`.

- [ ] **Step 3: Implement**

`app/models/income_statement/category_stats.rb`:

```ruby
  def initialize(family, interval: "month", cycle_offset: nil, exclude_recurring: false)
    @family = family
    @interval = interval
    @cycle_offset = cycle_offset || 0
    @exclude_recurring = exclude_recurring
  end
```

and in `query_sql`, after `AND ae.excluded = false` (line 53):

```ruby
            #{"AND t.recurring_transaction_id IS NULL" if @exclude_recurring}
```

`app/models/income_statement.rb`:

```ruby
  def expense_totals(period: nil, exclude_recurring: false)
    build_period_total(classification: "expense", period: period || current_cycle_period, exclude_recurring: exclude_recurring)
  end
```

```ruby
  def median_expense(interval: "month", category: nil, exclude_recurring: false)
    if category.present?
      category_stats(interval: interval, exclude_recurring: exclude_recurring)
        .find { |stat| stat.classification == "expense" && stat.category_id == category.id }&.median || 0
    else
      family_stats(interval: interval).find { |stat| stat.classification == "expense" }&.median || 0
    end
  end
```

`build_period_total` signature and first line:

```ruby
    def build_period_total(classification:, period:, exclude_recurring: false)
      scope = family.transactions.visible.in_period(period)
      scope = scope.where(recurring_transaction_id: nil) if exclude_recurring
      totals = totals_query(transactions_scope: scope).select { |t| t.classification == classification }
```

The rest of the method is unchanged. `category_stats`:

```ruby
    def category_stats(interval: "month", exclude_recurring: false)
      @category_stats ||= {}
      @category_stats[[ interval, exclude_recurring ]] ||= Rails.cache.fetch([
        "income_statement", "category_stats", family.id, interval, family.cycle_end_day, exclude_recurring, family.entries_cache_version
      ]) { CategoryStats.new(family, interval:, cycle_offset: family.cycle_end_day, exclude_recurring:).call }
    end
```

`app/models/budget.rb`. Below `FUTURE_CYCLES_LIMIT = 12` (line 5):

```ruby
  ProjectionCategory = Data.define(:category, :amount, :estimated)
```

After `commitments_percent` (before `private`, line 365):

```ruby
  # =============================================================================
  # Monthly projection: category spending recurring payments don't already cover
  # =============================================================================
  # Current month: real spending per category. Future months: each category's monthly median, the
  # "avg" budget rows show. Rows linked to a plan are left out because they are commitments.
  def category_spend_for_projection
    @category_spend_for_projection ||= (future? ? average_category_spend : actual_category_spend)
      .select { |row| row.amount.positive? }
      .sort_by { |row| -row.amount }
  end
```

Under `private`:

```ruby
    def actual_category_spend
      income_statement.expense_totals(period: period, exclude_recurring: true).category_totals
        .reject { |category_total| category_total.category.subcategory? }
        .map { |category_total| ProjectionCategory.new(category: category_total.category, amount: category_total.total.to_d, estimated: false) }
    end

    # A parent includes its subcategories, like the budget's category rows
    def average_category_spend
      categories = family.categories.expenses.to_a

      [ *categories.reject(&:subcategory?), family.categories.uncategorized ].map do |category|
        children = category.id ? categories.select { |child| child.parent_id == category.id } : []
        amount = [ category, *children ].sum(BigDecimal("0")) do |member|
          income_statement.median_expense(category: member, exclude_recurring: true).to_d
        end

        ProjectionCategory.new(category: category, amount: amount, estimated: true)
      end
    end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/budget_test.rb test/models/income_statement_test.rb`

Expected: PASS. Existing income statement tests are unchanged because the default is `exclude_recurring: false`.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/models/income_statement.rb app/models/income_statement/category_stats.rb app/models/budget.rb test/models/budget_test.rb -a
git add app/models/income_statement.rb app/models/income_statement/category_stats.rb app/models/budget.rb test/models/budget_test.rb
git commit -m "Add category spend for the monthly projection

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Budget impact for any frequency, with category segments

**Files:**
- Modify: `app/models/recurring_transaction/budget_impact.rb` (whole file)
- Modify: `app/views/recurring_transactions/_budget_impact.html.erb:4` (one-line rename, so the old view keeps rendering until Task 10)
- Test: `test/models/recurring_transaction/budget_impact_test.rb`

**Interfaces:**
- Consumes:
  - `Budget#category_spend_for_projection` and `Budget::ProjectionCategory` (Task 5).
  - Frequency-aware `occurrence_date` (Task 2).
  - `build_from_entry(entry, frequency:, total_payments:)` (Task 3).
- Produces:
  - `BudgetImpact::Segment = Data.define(:label, :color, :amount, :other)`.
  - `BudgetImpact::Month = Data.define(:budget, :committed, :category_segments, :purchase, :basis_budget)`, with:
    - `#basis`
    - `#category_spend`
    - `#total` (committed + category spend + purchase)
    - `#over?`, `#overage`, `#percent`, `#reference?`
    - `#estimated?` (future month).
  - `#occurrences`: payments in the first 3 budget months that haven't ended, for any plan type and frequency.
  - `#payments_count`.
  - `#counts_months?`: true for daily/weekly.
  - `#months`.
  - `#legend_categories -> Array<Category>`: the top 4 by spend across the shown months. When there are more than 4, Uncategorized folds into Other.
  - `#category_legend -> Array<[label, color]>`, with `"Other"` last when used.
  - `#available?`, `#over_months`, `#scale`, `#width`, `#reference_budget` keep their signatures.
  - `#installments_count` is removed (renamed `payments_count`).

- [ ] **Step 1: Write the failing tests**

In `test/models/recurring_transaction/budget_impact_test.rb`:

In `setup`, add as the last line:

```ruby
    # Category spend has its own tests below; the others look at commitments and the purchase only
    Budget.any_instance.stubs(:category_spend_for_projection).returns([])
```

In `"flags the months a purchase puts over budget"`, change `impact.installments_count` to `impact.payments_count`.

In `"the preview total equals the committed amount once the plan is saved"`, change the `expected` line to compare the commitments segment only:

```ruby
    expected = preview.months.to_h { |month| [ month.budget.start_date, month.committed + month.purchase ] }
```

Append before the final `end`:

```ruby
  test "a monthly charge projects the month of the purchase and the next two" do
    purchase = create_transaction(account: @card, amount: 200, name: "Gym", date: Date.new(2026, 10, 8))
    impact = RecurringTransaction.build_from_entry(purchase, frequency: "monthly").budget_impact

    assert_equal [ "October 2026", "November 2026", "December 2026" ], impact.months.map { |m| m.budget.name }
    assert_equal [ BigDecimal("200") ] * 3, impact.months.map(&:purchase)
    assert_equal [ false, true, true ], impact.months.map(&:reference?)
    assert_not impact.counts_months?
  end

  test "a weekly plan shows the next three budget months with every payment in them" do
    purchase = create_transaction(account: @card, amount: 50, name: "Cleaner", date: Date.new(2026, 10, 8))
    impact = RecurringTransaction.build_from_entry(purchase, frequency: "weekly").budget_impact

    assert_equal [ BigDecimal("200"), BigDecimal("200"), BigDecimal("250") ], impact.months.map(&:purchase)
    assert_equal 13, impact.payments_count
    assert impact.counts_months?
  end

  test "category spend fills each month: actuals now, averages later, plan rows left out" do
    Budget.any_instance.unstub(:category_spend_for_projection)
    family = families(:empty)
    checking = Account.create!(family: family, accountable: Depository.new, name: "Checking", status: "active", currency: "USD", balance: 0)
    food = family.categories.create!(name: "Food", color: "#e99537", lucide_icon: "utensils", classification: "expense")
    family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                           currency: "USD", budgeted_spending: 600, expected_income: 0)
    create_transaction(account: checking, date: Date.new(2026, 9, 10), amount: 300, category: food)
    create_transaction(account: checking, date: Date.new(2026, 10, 2), amount: 100, category: food)
    gym = create_transaction(account: checking, date: Date.new(2026, 10, 3), amount: 50, category: food)
    RecurringTransaction.create_from_entry!(gym, frequency: "monthly")
    purchase = Entry.new(account: checking, name: "TV", date: Date.new(2026, 10, 8), amount: 1200, currency: "USD",
                         entryable: Transaction.new) # unsaved, as at capture

    impact = RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: 3).budget_impact

    assert_equal [ BigDecimal("50") ] * 3, impact.months.map(&:committed)
    assert_equal [ [ "Food", BigDecimal("100") ], [ "Food", BigDecimal("200") ], [ "Food", BigDecimal("200") ] ],
                 impact.months.map { |month| [ month.category_segments.first.label, month.category_segments.first.amount ] }
    assert_equal [ false, true, true ], impact.months.map(&:estimated?)
    assert_equal [ BigDecimal("550"), BigDecimal("650"), BigDecimal("650") ], impact.months.map(&:total)
    assert_equal [ "November 2026", "December 2026" ], impact.over_months.map { |month| month.budget.name }
  end

  test "the legend names the top four categories and folds the rest, Uncategorized included, into Other" do
    rows = [ [ "Rent", 500 ], [ "Food", 400 ], [ "Fun", 300 ], [ "Travel", 200 ], [ "Pets", 100 ] ].map do |name, amount|
      Budget::ProjectionCategory.new(category: Category.new(id: SecureRandom.uuid, name: name, color: "#e99537"),
                                     amount: BigDecimal(amount.to_s), estimated: true)
    end
    rows << Budget::ProjectionCategory.new(category: Category.new(name: "Uncategorized", color: Category::UNCATEGORIZED_COLOR),
                                           amount: BigDecimal("50"), estimated: true)
    Budget.any_instance.stubs(:category_spend_for_projection).returns(rows)
    purchase = create_transaction(account: @card, amount: 300, name: "Lamp", date: Date.new(2026, 10, 8))

    impact = RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: 3).budget_impact
    other = impact.months.first.category_segments.last

    assert_equal [ "Rent", "Food", "Fun", "Travel", "Other" ], impact.category_legend.map(&:first)
    assert other.other
    assert_equal BigDecimal("150"), other.amount
    assert_equal BigDecimal("1550"), impact.months.first.category_spend
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/recurring_transaction/budget_impact_test.rb`

Expected: FAIL.
- `undefined method 'payments_count'`.
- The charge and weekly plans return no months, because only installments project today.
- `undefined method 'category_segments'`.

- [ ] **Step 3: Implement**

Replace `app/models/recurring_transaction/budget_impact.rb` with:

```ruby
# Capture-time "Monthly projection": the budget months of the next payments of a (usually unsaved)
# plan, with what recurring payments already commit, the category spending they don't cover and
# this purchase, compared with the same basis budget as the budget screen.
class RecurringTransaction::BudgetImpact
  MAX_MONTHS = 3
  LEGEND_CATEGORIES = 4
  OTHER_LABEL = "Other"
  SHORT_FREQUENCIES = %w[daily weekly].freeze

  Segment = Data.define(:label, :color, :amount, :other)

  Month = Data.define(:budget, :committed, :category_segments, :purchase, :basis_budget) do
    def basis
      basis_budget.budgeted_spending
    end

    def category_spend
      category_segments.sum(BigDecimal("0"), &:amount)
    end

    def total
      committed + category_spend + purchase
    end

    def over?
      total > basis
    end

    def overage
      total - basis
    end

    # Whole percent; rounded up once over so it never reads "100%" while over budget
    def percent
      ratio = total / basis * 100
      over? ? ratio.ceil : ratio.floor
    end

    def reference?
      basis_budget != budget
    end

    # Future months show category averages instead of real spending
    def estimated?
      budget.future?
    end
  end

  attr_reader :plan

  def initialize(plan)
    @plan = plan
  end

  # Every payment in the first MAX_MONTHS budget months that haven't ended
  def occurrences
    @occurrences ||= next_occurrences
  end

  def payments_count
    occurrences.size
  end

  # Daily and weekly plans put many payments in a month, so the subtitle counts months
  def counts_months?
    plan.frequency.in?(SHORT_FREQUENCIES)
  end

  def months
    @months ||= begin
      rows = occurrences.group_by { |occurrence| family.cycle_range_containing(occurrence.date).first }.filter_map do |start_date, group|
        budget = Budget.for_cycle(family, start_date)
        basis_budget = budget.basis_budget
        next unless basis_budget&.budgeted_spending&.positive?

        [ budget, basis_budget, group.sum(BigDecimal("0"), &:amount) ]
      end

      @legend_categories = rank_categories(rows.flat_map { |budget, _, _| budget.category_spend_for_projection })

      rows.map do |budget, basis_budget, purchase|
        Month.new(budget: budget, committed: budget.committed_spending,
                  category_segments: segments_for(budget.category_spend_for_projection),
                  purchase: purchase, basis_budget: basis_budget)
      end
    end
  end

  def legend_categories
    months
    @legend_categories
  end

  # [label, color] for each category segment colour, in bar order, "Other" last when used
  def category_legend
    entries = legend_categories.map { |category| [ category.name, category.color ] }
    entries << [ OTHER_LABEL, Category::UNCATEGORIZED_COLOR ] if months.any? { |month| month.category_segments.any?(&:other) }
    entries
  end

  def available?
    months.any?
  end

  def over_months
    months.select(&:over?)
  end

  # Shared bar scale for every month: the budget mark sits at 83.3% and nothing overflows
  def scale
    [ *months.map { |month| month.basis * BigDecimal("1.2") }, *months.map(&:total) ].max
  end

  def width(amount)
    (amount / scale * 100).round(1).to_f
  end

  def reference_budget
    months.find(&:reference?)&.basis_budget
  end

  private
    def family
      plan.family
    end

    def next_occurrences
      return [] unless plan.start_date && RecurringTransaction::FREQUENCIES.key?(plan.frequency)

      today = family.today
      month_starts = []
      result = []

      (1..).each do |number|
        break if plan.total_payments && number > plan.total_payments

        date = plan.occurrence_date(number)
        month_start, month_end = family.cycle_range_containing(date)
        next if month_end < today

        unless month_starts.include?(month_start)
          break if month_starts.size == MAX_MONTHS

          month_starts << month_start
        end

        result << RecurringTransaction::Occurrence.new(number: number, date: date, amount: plan.occurrence_amount(number))
      end

      result
    end

    # Top categories by spend across the months shown. With more than LEGEND_CATEGORIES, Uncategorized joins "Other"
    def rank_categories(rows)
      ranked = rows.group_by { |row| row.category.id }
        .map { |_, group| [ group.first.category, group.sum(BigDecimal("0"), &:amount) ] }
        .sort_by { |_, amount| -amount }
        .map(&:first)

      ranked.size > LEGEND_CATEGORIES ? ranked.reject { |category| category.id.nil? }.first(LEGEND_CATEGORIES) : ranked
    end

    def segments_for(rows)
      legend_ids = @legend_categories.map(&:id)

      shown = @legend_categories.filter_map do |category|
        row = rows.find { |candidate| candidate.category.id == category.id }
        Segment.new(label: category.name, color: category.color, amount: row.amount, other: false) if row
      end

      rest = rows.reject { |row| legend_ids.include?(row.category.id) }.sum(BigDecimal("0"), &:amount)
      return shown unless rest.positive?

      shown + [ Segment.new(label: OTHER_LABEL, color: Category::UNCATEGORIZED_COLOR, amount: rest, other: true) ]
    end
end
```

In `app/views/recurring_transactions/_budget_impact.html.erb:4`:

```erb
<% count = impact.payments_count %>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/recurring_transaction/budget_impact_test.rb test/controllers/recurring_transactions_controller_test.rb`

Expected: PASS.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/models/recurring_transaction/budget_impact.rb test/models/recurring_transaction/budget_impact_test.rb -a
git add app/models/recurring_transaction/budget_impact.rb app/views/recurring_transactions/_budget_impact.html.erb test/models/recurring_transaction/budget_impact_test.rb
git commit -m "Project any frequency over the next three budget months with category spend

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Labels, summaries, notices, confirms and the copy doc

**Files:**
- Modify: `app/helpers/recurring_transactions_helper.rb`
  - Add constants and new helpers.
  - Change `recurring_icon` (15-17), `recurring_summary` (20-60), `recurring_occurrence_label` (63-71), `recurring_status_text` (82-89) and `recurring_plan_subtitle_parts` (139-148).
- Modify: `app/controllers/concerns/recurrence_params.rb` (`recurrence_notice`)
- Modify: `app/helpers/custom_confirm.rb:15-26` (`for_plan_stop`)
- Modify: `docs/designpowers/content/2026-10-08-pagos-recurrentes-msi-copy.md` (append §14)
- Test: `test/helpers/recurring_transactions_helper_test.rb`, `test/helpers/custom_confirm_test.rb`, `test/controllers/recurring_transactions_controller_test.rb`, `test/controllers/transactions_controller_test.rb`

**Interfaces:**
- Consumes: `#frequency`, `#credit_card?`, `#source_is_first_payment?` (Tasks 2-3).
- Produces (helpers):
  - `RecurringTransactionsHelper::FREQUENCY_LABELS`, `FREQUENCY_UNITS`, `CHARGE_LABELS`.
  - `recurring_frequency_options -> [[label, value], ...]`, with `["None", ""]` first.
  - `recurring_every(plan) -> "every week"`.
  - `recurring_charge_label(plan) -> "Weekly charge"`.
  - `recurring_payments_noun(plan, count = 2)`. It gives `"installments"` / `"installment"` on a card and `"payments"` / `"payment"` elsewhere. It is meant for installment plans.
  - `recurring_icon(plan)`. It gives `"credit-card"` only for card installments, otherwise `"repeat"`.
  - `recurring_summary` line 1 is `"N payments of $X"` / `"$X every {unit}"`.
  - `recurring_occurrence_label` gives `"Installment n of N"` (card), `"Payment n of N"` (others, and stored charges with an end), or the charge label.
  - `recurring_status_text` gives `"Payments · n of N"` off a card.
  - `recurring_plan_subtitle_parts` gives `["N payments of $X", "every {unit}", state]` / `["$X every {unit}", state]`.
  - `recurrence_notice` gives `"Split into N installments."` (card), `"Split into N payments."` (others), or `"{Charge label} started."`.
  - `CustomConfirm.for_plan_stop` off a card gives `"The N payments left ($X) won't be added."`.

- [ ] **Step 1: Write the failing tests**

Replace `test/helpers/recurring_transactions_helper_test.rb` tests `"summarizes even installments in two lines"`, `"summarizes charges and past payments"` and `"labels occurrences and plan states with interface copy"` with:

```ruby
  test "summarizes installments in two lines" do
    plan = build(amount: 15000, total_payments: 12, start_date: Date.new(2026, 11, 8))
    summary = recurring_summary(plan, as_of: Date.new(2026, 10, 8))

    assert_equal "credit-card", summary.icon
    assert_equal "12 payments of $1,250.00", summary.line1
    assert_equal "Last on Oct 8, 2027", summary.line2
    assert_nil summary.past_due
    assert_equal "12 payments of $1,250.00, last on Oct 8, 2027", summary.announcement
  end

  test "summarizes charges per frequency and past payments" do
    open_charge = build(plan_type: "charge", amount: 199, total_payments: nil, start_date: Date.new(2026, 6, 30))
    summary = recurring_summary(open_charge, as_of: Date.new(2026, 10, 8))

    assert_equal "repeat", summary.icon
    assert_equal "$199.00 every month", summary.line1
    assert_equal "No end date", summary.line2
    assert_equal "3 already due. They'll be added with their original dates.", summary.past_due

    { "daily" => "every day", "weekly" => "every week", "bimonthly" => "every 2 months", "quarterly" => "every 3 months",
      "semiannual" => "every 6 months", "annual" => "every year" }.each do |frequency, every|
      charge = build(plan_type: "charge", amount: 50, total_payments: nil, frequency: frequency, start_date: Date.new(2026, 10, 8))
      assert_equal "$50.00 #{every}", recurring_summary(charge, as_of: Date.new(2026, 10, 8)).line1
    end

    ending = build(plan_type: "charge", amount: 199, total_payments: 12, start_date: Date.new(2026, 10, 15))
    assert_equal "$199.00 every month, 12 payments, last on Sep 15, 2027", recurring_summary(ending, as_of: Date.new(2026, 10, 8)).announcement
  end

  test "labels occurrences, charges and plan states with interface copy" do
    card_installments = build(amount: 6000, total_payments: 6, start_date: Date.new(2026, 11, 8))
    other_installments = build(amount: 6000, total_payments: 12, account: accounts(:depository))

    assert_equal "Installment 2 of 6", recurring_occurrence_label(card_installments, 2)
    assert_equal "Payment 3 of 12", recurring_occurrence_label(other_installments, 3)
    assert_equal "repeat", recurring_icon(other_installments)
    assert_equal "Payment 3 of 12", recurring_occurrence_label(build(plan_type: "charge", total_payments: 12), 3)
    assert_equal [ "Monthly charge", "Weekly charge", "Charge every 2 months", "Annual charge" ],
                 %w[monthly weekly bimonthly annual].map { |frequency| recurring_occurrence_label(build(plan_type: "charge", total_payments: nil, frequency: frequency), 3) }
    assert_equal [ "None", "Daily", "Weekly", "Monthly", "Every 2 months", "Quarterly", "Every 6 months", "Annually" ],
                 recurring_frequency_options.map(&:first)
    assert_equal [ "", "daily", "weekly", "monthly", "bimonthly", "quarterly", "semiannual", "annual" ],
                 recurring_frequency_options.map(&:last)
    assert_equal [ nil, "Active" ], recurring_plan_state(card_installments)
    assert_equal "Today", recurring_group_label(Date.new(2026, 10, 8), today: Date.new(2026, 10, 8))
    assert_equal "Tomorrow", recurring_group_label(Date.new(2026, 10, 9), today: Date.new(2026, 10, 8))
    assert_equal "Oct 12", recurring_group_label(Date.new(2026, 10, 12), today: Date.new(2026, 10, 8))
    assert_equal "Jan 8, 2027", recurring_group_label(Date.new(2027, 1, 8), today: Date.new(2026, 10, 8))
  end

  test "plan subtitles name the frequency" do
    installments = build(amount: 15000, total_payments: 12)
    charge = build(plan_type: "charge", amount: 600, total_payments: nil, frequency: "weekly")

    assert_equal [ "12 payments of $1,250.00", "every month", "Active" ], recurring_plan_subtitle_parts(installments)
    assert_equal [ "$600.00 every week", "Active" ], recurring_plan_subtitle_parts(charge)
  end

  test "the drawer status of a payment off a card counts payments" do
    purchase = create_transaction(account: accounts(:depository), amount: 1200, name: "Desk", date: Date.new(2026, 8, 20))
    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 12)

    assert_equal "Payment 1 of 12", recurring_provenance_label(purchase.reload.entryable)
    assert_equal "Payments · , 1 of 12", strip_tags(recurring_status_text(purchase.entryable)).squish
    assert_equal "Payment 2 of 12", recurring_provenance_label(plan.transactions.find_by(installment_number: 2))
  end
```

Replace the private `build` helper with:

```ruby
    def build(plan_type: "installments", amount: 1000, total_payments: 3, start_date: Date.new(2026, 11, 8), frequency: "monthly", account: @card)
      RecurringTransaction.new(family: @family, account: account, name: "Plan", plan_type: plan_type, frequency: frequency,
                               amount: amount, currency: "USD", total_payments: total_payments, start_date: start_date)
    end
```

In `test/helpers/custom_confirm_test.rb`, append before the final `end`:

```ruby
  test "stopping installments off a card says the payments left won't be added" do
    purchase = create_transaction(account: accounts(:depository), amount: 1200, name: "Desk", date: Date.new(2026, 7, 20))
    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 12) # Jul 20 (the purchase), Aug 20, Sep 20

    assert_equal "The 9 payments left ($900.00) won't be added.", CustomConfirm.for_plan_stop(plan).to_data_attribute[:body]
  end
```

In `test/controllers/recurring_transactions_controller_test.rb`:
- `"preview summarizes installments for a new purchase"`: change `"12 installments of $1,250.00"` to `"12 payments of $1,250.00"`.
- `"preview refuses another family's entry and account"`: change `assert_not_includes response.body, "installments of"` to `assert_not_includes response.body, "payments of"`.

In `test/controllers/transactions_controller_test.rb`:
- In `"installments on an account that isn't a card become ordinary payments"`, add at the end: `assert_equal "Split into 3 payments.", flash[:notice]`.
- In `"a client plan type is ignored: no end count means a recurring charge"`, add at the end: `assert_equal "Weekly charge started.", flash[:notice]`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/helpers test/controllers/recurring_transactions_controller_test.rb test/controllers/transactions_controller_test.rb`

Expected: FAIL.
- `"12 installments of"` is still shown.
- `undefined method 'recurring_frequency_options'`.
- `"Monthly charge"` appears for a weekly plan.
- The stop confirm mentions the card balance.
- The notices are `"Split into 3 installments."` and `"Monthly charge started."`.

- [ ] **Step 3: Implement the helper**

In `app/helpers/recurring_transactions_helper.rb`, below `RecurringSummary = ...`:

```ruby
  # r.daily … r.annual (Repeat select), keyed by RecurringTransaction::FREQUENCIES
  FREQUENCY_LABELS = {
    "daily" => "Daily", "weekly" => "Weekly", "monthly" => "Monthly", "bimonthly" => "Every 2 months",
    "quarterly" => "Quarterly", "semiannual" => "Every 6 months", "annual" => "Annually"
  }.freeze

  # r2.units: "every {unit}"
  FREQUENCY_UNITS = {
    "daily" => "day", "weekly" => "week", "monthly" => "month", "bimonthly" => "2 months",
    "quarterly" => "3 months", "semiannual" => "6 months", "annual" => "year"
  }.freeze

  # r.charge_label
  CHARGE_LABELS = {
    "daily" => "Daily charge", "weekly" => "Weekly charge", "monthly" => "Monthly charge", "bimonthly" => "Charge every 2 months",
    "quarterly" => "Quarterly charge", "semiannual" => "Charge every 6 months", "annual" => "Annual charge"
  }.freeze

  # Repeat select options: None first, then each frequency
  def recurring_frequency_options
    [ [ "None", "" ], *FREQUENCY_LABELS.map { |value, label| [ label, value ] } ]
  end

  def recurring_every(plan)
    "every #{FREQUENCY_UNITS.fetch(plan.frequency)}"
  end

  def recurring_charge_label(plan)
    CHARGE_LABELS.fetch(plan.frequency)
  end

  # Installment plans: "installments" on a card (the purchase stays whole on it), "payments" elsewhere
  def recurring_payments_noun(plan, count = 2)
    noun = plan.credit_card? ? "installment" : "payment"
    count == 1 ? noun : noun.pluralize
  end
```

`recurring_icon`:

```ruby
  def recurring_icon(plan)
    plan.installments? && plan.credit_card? ? "credit-card" : "repeat"
  end
```

In `recurring_summary`, change the two `line1` assignments:

```ruby
      line1 = "#{plan.total_payments} payments of #{first_amount}"
```

```ruby
      line1 = "#{first_amount} #{recurring_every(plan)}"
```

`recurring_occurrence_label`:

```ruby
  # c1.installment_line (card installments) / r.payment_line (other installments, charges with an end) / r.charge_label
  def recurring_occurrence_label(plan, number)
    if plan.installments? && plan.credit_card?
      "Installment #{number} of #{plan.total_payments}"
    elsif plan.total_payments
      "Payment #{number} of #{plan.total_payments}"
    else
      recurring_charge_label(plan)
    end
  end
```

`recurring_status_text`:

```ruby
  # b3.status_* / r.status_payments under "Recurring payment" in the drawer
  def recurring_status_text(transaction)
    plan = transaction.recurring_transaction
    return "One time" unless plan
    return recurring_charge_label(plan) if plan.charge?

    number = transaction.installment_number || plan.last_handled_number
    label = plan.credit_card? ? "Installments" : "Payments"
    safe_join([ label, tag.span("·", aria: { hidden: true }), tag.span(",", class: "sr-only"), "#{number} of #{plan.total_payments}" ], " ")
  end
```

`recurring_plan_subtitle_parts`, the `if` branch:

```ruby
    if plan.installments?
      [ "#{plan.total_payments} payments of #{recurring_money(plan.occurrence_amount(1), plan.currency)}", recurring_every(plan), state ]
    else
      [ "#{recurring_money(plan.amount, plan.currency)} #{recurring_every(plan)}", state ]
    end
```

Leave `recurring_credit_account_ids` in place. Task 8 deletes it together with its last caller.

- [ ] **Step 4: Implement the notice and the stop confirm**

`app/controllers/concerns/recurrence_params.rb`. `recurrence_notice` becomes:

```ruby
    # b3.success_installments / r3.success_payments / r3.success_charge
    def recurrence_notice(plan)
      if plan.installments?
        "Split into #{plan.total_payments} #{helpers.recurring_payments_noun(plan)}."
      else
        "#{helpers.recurring_charge_label(plan)} started."
      end
    end
```

`app/helpers/custom_confirm.rb`. In `for_plan_stop`, the `body` becomes:

```ruby
      body = if plan.installments? && plan.credit_card?
        left = plan.remaining_payments
        "The #{left} #{"installment".pluralize(left)} left (#{money(plan.remaining_balance, plan.currency)}) " \
          "won't count in future budgets. The full purchase stays on your card balance."
      elsif plan.installments?
        left = plan.remaining_payments
        "The #{left} #{"payment".pluralize(left)} left (#{money(plan.remaining_balance, plan.currency)}) won't be added."
      else
        added = plan.last_handled_number
        "No new payments will be added. The #{added} already added #{added == 1 ? "stays" : "stay"}."
      end
```

- [ ] **Step 5: Add §14 to the copy doc**

Append to `docs/designpowers/content/2026-10-08-pagos-recurrentes-msi-copy.md`:

```markdown

## 14. Repeat + Monthly projection (Victor, 2026-10-11)

Source: `docs/superpowers/specs/2026-10-11-repeat-and-monthly-projection-design.md`. Ids marked _(default)_ were chosen at plan time and need content-writer review.

### 14.1 Capture (B1 / B3 fields)

| id | String | Context |
|---|---|---|
| `r.repeat_label` | Repeat | Label of the select, under Date |
| `r.none` | None | First option, default |
| `r.daily` / `r.weekly` / `r.monthly` | Daily / Weekly / Monthly | Options |
| `r.bimonthly` | Every 2 months | Option (stored `bimonthly`) |
| `r.quarterly` / `r.semiannual` / `r.annual` | Quarterly / Every 6 months / Annually | Options |
| `r.ends_after_label` | Ends after | Number, optional, shown only when Repeat ≠ None; empty = no end |
| `r.ends_after_suffix` | payments | Inside the label |
| `r.err.payments_range` | Enter 2 to 48 payments. | End count other than 2–48 |
| `r.err.frequency` | Choose how often it repeats. | Unknown frequency (tampered) _(default)_ |
| `r.err.amount_too_small` | Too small to split into {6} payments. Use fewer. | Payment < 0.01 _(default: "installments" → "payments")_ |

`b.err.payments_range_charge` ("Enter a whole number, or leave it empty.") stays for charges stored with an end before 2026-10-11.

### 14.2 Live summary (B2)

| id | String | Context |
|---|---|---|
| `r2.line1_installments` | {12} payments of {$1,250.00} | Line 1 with an end; the amount entered is the total. Line 2 is `b2.line2_last_on` / `b2.line2_last_one` |
| `r2.line1_charge` | {$600.00} every {unit} | Line 1 without an end; line 2 `b2.line2_no_end` |
| `r2.units` | day · week · month · 2 months · 3 months · 6 months · year | `{unit}` |

### 14.3 Convert (B3)

Card installments keep `b3.confirm_heading_installments`, `b3.confirm_point_debt`, `b3.confirm_primary_installments`, `b3.success_installments`.

| id | String | Context |
|---|---|---|
| `r3.confirm_heading_payments` | Split {$3,000.00} into {3} payments | Installments off a card |
| `r3.confirm_point_first_payment` | This transaction becomes payment 1 ({$1,000.00}). | Installments off a card: its amount changes _(default)_ |
| `r3.confirm_primary_payments` | Split into {3} payments | |
| `r3.success_payments` | Split into {3} payments. | Notice (also after New transaction) |
| `r3.confirm_heading_charge` | Repeat {$199.00} every {unit} | Replaces `b3.confirm_heading_charge` |
| `r3.confirm_primary_charge` | Start {weekly charge} | `r.charge_label`, first letter lowercased; replaces `b3.confirm_primary_charge` |
| `r3.success_charge` | {Weekly charge} started. | Replaces `b3.success_charge` |
| `b3.confirm_point_backfill` | Adds {3} past {installments/payments} … | "installments" only for card installments |

### 14.4 Labels on other surfaces

| id | String | Context |
|---|---|---|
| `r.charge_label` | Daily charge · Weekly charge · Monthly charge · Charge every 2 months · Quarterly charge · Charge every 6 months · Annual charge | Rows, B3 status, card tab past plans; replaces `c1.charge_line_open` / `b3.status_charge` _(default for the last three)_ |
| `r.payment_line` | Payment {3} of {12} | Rows of installments off a card (card keeps `c1.installment_line`) |
| `r.status_payments` | Payments · {3} of {12} | B3 status off a card. A11y "Payments, 3 of 12" |
| `c3.subtitle_installments` | {12} payments of {$1,250.00} · every {month} · {Active} | Replaces the 2026-10-08 string |
| `c3.subtitle_charge` | {$600.00} every {week} · {Active} | Replaces the 2026-10-08 string |
| `c3.schedule_locked_payments` | To change payments or dates, stop this plan and add a new one. | Plan dialog, installments off a card _(default)_ |
| `r.confirm_stop_body_payments` | The {9} payments left ({$900.00}) won't be added. | Stop confirm, installments off a card _(default)_ |
| `c2.col_payment` | Payment | Replaces "Per month" in both card tables _(default)_ |
| `c2.every_line` | every {week} | Second line under the payment amount |
| `c2.charges_caption` | Charges | Replaces "Monthly charges" _(default)_ |

### 14.5 Monthly projection (replaces the BI header and legend)

| id | String | Context | A11y |
|---|---|---|---|
| `pm.title` | Monthly projection | `DS::Disclosure`, closed by default, only when Repeat ≠ None | `<summary>` |
| `bi.subtitle` | Budget impact of the next {3} payments | Singular "next payment" | |
| `bi.subtitle_months` | Budget impact of the next {3} months | Daily and weekly plans; singular "next month" _(default)_ | |
| `pm.legend_installments` | Expenses in installments | `bg-inverse`; replaces `bi.legend_committed` | Legend is read |
| `pm.legend_other` | Other | Categories beyond the top 4 (Uncategorized included) | |
| `pm.month_detail_avg` | {$7,801.00} of {$7,500.00} budgeted · categories avg | Future months (category averages) _(default)_ | `aria-hidden` |
| `pm.month_sr` | {November 2026}: {$7,801.00} of {$7,500.00}, {$301.00} over / {$199.00} left | `sr-only` per bar | |

Kept: `bi.title_over`, `bi.title_over_multi`, `bi.month_over`, `bi.month_percent`, `bi.month_detail`, `bi.legend_purchase`, `bi.legend_budget`, `bi.reference`.

### 14.6 Removed (2026-10-11)

`b1.disclosure_title` (capture), `b1.type_label`, `b1.type_none`, `b1.type_charge`, `b1.type_installments`, `b1.payments_label_installments`, `b1.payments_label_charge` (now `r.ends_after_label`), `b1.first_payment_label`, `b.err.installments_credit_only`, `b.err.first_payment_missing`, `b.err.first_payment_before_purchase`, `b.err.payments_range_installments` (now `r.err.payments_range`), `bi.legend_committed`, `c2.msi_col_monthly` / `c2.charges_col_amount` ("Per month").
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/helpers test/controllers/recurring_transactions_controller_test.rb test/controllers/transactions_controller_test.rb test/controllers/transactions/recurrences_controller_test.rb test/controllers/credit_card_recurring_tab_test.rb`

Expected: PASS, apart from baseline names.

- [ ] **Step 7: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/helpers/recurring_transactions_helper.rb app/helpers/custom_confirm.rb app/controllers/concerns/recurrence_params.rb test/helpers test/controllers/recurring_transactions_controller_test.rb test/controllers/transactions_controller_test.rb -a
git add app/helpers/recurring_transactions_helper.rb app/helpers/custom_confirm.rb app/controllers/concerns/recurrence_params.rb test/helpers test/controllers/recurring_transactions_controller_test.rb test/controllers/transactions_controller_test.rb docs/designpowers/content/2026-10-08-pagos-recurrentes-msi-copy.md
git commit -m "Name frequencies in summaries, rows, notices and confirms

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Repeat select under Date, and the simplified `recurring-form` controller

**Files:**
- Rewrite: `app/views/transactions/_recurrence_fields.html.erb`
- Modify: `app/views/transactions/_form.html.erb` (lines 1-55)
- Modify: `app/views/transactions/recurrences/_fields.html.erb` (whole file)
- Rewrite: `app/javascript/controllers/recurring_form_controller.js`
- Modify: `app/helpers/recurring_transactions_helper.rb` (delete `recurring_credit_account_ids`, currently lines 121-124)
- Test: `test/controllers/transactions_controller_test.rb`, `test/controllers/transactions/recurrences_controller_test.rb`

**Interfaces:**
- Consumes: `recurring_frequency_options` (Task 7), `RecurringTransaction::MAX_INSTALLMENTS`, and the `frequency` / `total_payments` errors (Tasks 2-3).
- Produces:
  - Partial `transactions/_recurrence_fields`, locals `(recurrence:, show_base_error: true, autofocus: false)`. It renders:
    - `select#recurrence_frequency[name="recurrence[frequency]"]`
    - `div[data-recurring-form-target="endsAfter"]` containing `input#recurrence_total_payments[name="recurrence[total_payments]"]` (min 2, max 48)
    - `turbo-frame#recurring_preview`
  - Stimulus `recurring-form`:
    - targets `endsAfter preview status review`
    - values `previewUrl unavailableText`
    - actions `schedulePreview`, `frequencyChanged`, `previewLoaded`, `previewFailed`, `projectionToggled`
  - Task 10 relies on `projectionToggled` and on the `[data-recurring-form-projection]` wrapper convention.

- [ ] **Step 1: Write the failing tests**

In `test/controllers/transactions_controller_test.rb`, replace the test `"an invalid plan saves nothing and explains why"` with:

```ruby
  test "an invalid end count saves nothing and explains why" do
    travel_to Date.new(2026, 10, 8)

    assert_no_difference [ "Entry.count", "RecurringTransaction.count" ] do
      post transactions_url, params: {
        entry: recurring_entry_params(accounts(:credit_card), amount: 15000),
        recurrence: { frequency: "monthly", total_payments: "1" }
      }, headers: { "Turbo-Frame" => "modal" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Enter 2 to 48 payments."
    assert_select "select#recurrence_frequency option[selected][value='monthly']"
    assert_select "input#recurrence_total_payments[autofocus][aria-invalid='true']"
  end
```

In `"an unknown frequency is refused, not a 500"`, add at the end:

```ruby
    assert_includes response.body, "Choose how often it repeats."
    assert_select "select#recurrence_frequency[autofocus][aria-invalid='true']"
```

Append before `private`:

```ruby
  test "the expense form offers Repeat under Date with None selected" do
    get new_transaction_url(nature: "outflow"), headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_select "select#recurrence_frequency option", 8
    assert_select "select#recurrence_frequency option[selected]", text: "None"
    assert_select "[data-recurring-form-target='endsAfter'][hidden] input#recurrence_total_payments[disabled]"
    assert_not_includes response.body, "Recurring payment"
    assert_not_includes response.body, "First payment"
    assert_not_includes response.body, "Number of installments"
  end

  test "the income form has no Repeat" do
    get new_transaction_url(nature: "inflow"), headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_select "select#recurrence_frequency", 0
  end
```

In `test/controllers/transactions/recurrences_controller_test.rb`, replace `"opens the fields with Doesn't repeat selected"` with:

```ruby
  test "opens the fields with Repeat set to None" do
    get new_transaction_recurrence_url(@entry), headers: @frame

    assert_response :success
    assert_select "select#recurrence_frequency option[selected]", text: "None"
    assert_select "select#recurrence_frequency[autofocus]"
    assert_includes response.body, "Review"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/transactions_controller_test.rb test/controllers/transactions/recurrences_controller_test.rb`

Expected: FAIL. There is no `select#recurrence_frequency`, the form still shows the "Recurring payment" disclosure, and the radios render.

- [ ] **Step 3: Rewrite the fields partial**

`app/views/transactions/_recurrence_fields.html.erb`:

```erb
<%# locals: (recurrence:, show_base_error: true, autofocus: false) %>

<% frequency = recurrence&.frequency.to_s %>
<% errors = recurrence&.errors %>
<% frequency_error = errors&.[](:frequency)&.first %>
<% payments_error = errors&.[](:total_payments)&.first %>
<% base_error = show_base_error && errors && (errors[:base] + errors[:account]).first %>
<% first_invalid = if frequency_error || base_error then :frequency elsif payments_error then :total_payments end %>
<% frequency_described_by = [ ("recurrence_frequency_error" if frequency_error), ("recurrence_base_error" if base_error) ].compact.join(" ").presence %>

<div class="space-y-2">
  <div class="flex flex-col gap-1">
    <div class="<%= class_names("form-field", "border-destructive": frequency_error) %>">
      <div class="form-field__body">
        <label class="form-field__label" for="recurrence_frequency">Repeat</label>
        <%= select_tag "recurrence[frequency]",
              options_for_select(recurring_frequency_options, frequency),
              id: "recurrence_frequency",
              class: "form-field__input",
              autofocus: first_invalid == :frequency || (autofocus && first_invalid.nil?),
              "aria-invalid": frequency_error.present?,
              "aria-describedby": frequency_described_by,
              data: { action: "change->recurring-form#frequencyChanged" } %>
      </div>
    </div>
    <% if frequency_error %>
      <%= render "transactions/recurrence_error", id: "recurrence_frequency_error", message: frequency_error %>
    <% end %>
    <% if base_error %>
      <%= render "transactions/recurrence_error", id: "recurrence_base_error", message: base_error %>
    <% end %>
  </div>

  <%= tag.div class: "flex flex-col gap-1", hidden: frequency.blank?, data: { recurring_form_target: "endsAfter" } do %>
    <label class="<%= class_names("form-field", "border-destructive": payments_error) %>" for="recurrence_total_payments">
      <span class="form-field__label">Ends after</span>
      <span class="flex items-center gap-2">
        <%= number_field_tag "recurrence[total_payments]", recurrence&.total_payments_before_type_cast,
              id: "recurrence_total_payments",
              class: "form-field__input tabular-nums w-16",
              autocomplete: "off", inputmode: "numeric", min: 2, max: RecurringTransaction::MAX_INSTALLMENTS, step: 1, placeholder: "—",
              disabled: frequency.blank?,
              autofocus: first_invalid == :total_payments,
              "aria-invalid": payments_error.present?,
              "aria-describedby": ("recurrence_total_payments_error" if payments_error) %>
        <span class="text-sm text-secondary">payments</span>
      </span>
    </label>
    <% if payments_error %>
      <%= render "transactions/recurrence_error", id: "recurrence_total_payments_error", message: payments_error %>
    <% end %>
  <% end %>

  <%= turbo_frame_tag "recurring_preview",
        class: "block transition-opacity duration-150 motion-reduce:transition-none",
        data: {
          recurring_form_target: "preview",
          action: "turbo:frame-load->recurring-form#previewLoaded turbo:frame-missing->recurring-form#previewFailed turbo:fetch-request-error->recurring-form#previewFailed"
        } %>
</div>
```

- [ ] **Step 4: Update the new-transaction form**

In `app/views/transactions/_form.html.erb`, replace lines 1-16 (locals through the end of `recurring_data`) with:

```erb
<%# locals: (entry:, income_categories:, expense_categories:, recurrence: nil) %>

<% outflow = params[:nature] != "inflow" && params.dig(:entry, :nature) != "inflow" %>
<% recurring_data = if outflow
     {
       controller: "recurring-form",
       recurring_form_preview_url_value: preview_recurring_transactions_path(impact: 1),
       recurring_form_unavailable_text_value: "We couldn't calculate this. You can still save.",
       action: "input->recurring-form#schedulePreview change->recurring-form#schedulePreview"
     }
   else
     {}
   end %>
```

The account select (line 36) loses its `data:` option:

```erb
      <%= f.collection_select :account_id, Current.family.accounts.manual.active.alphabetically, :id, :name, { prompt: t(".account_prompt"), label: t(".account") }, required: true, class: "form-field__input text-ellipsis" %>
```

Replace from the date field (line 44) through the status paragraph and its `<% end %>` (line 55) with:

```erb
    <%= f.date_field :date, label: t(".date"), required: true, min: Entry.min_supported_date, max: Date.current, value: entry.date || Date.current %>

    <% if outflow %>
      <%= render "transactions/recurrence_fields", recurrence: recurrence %>
    <% end %>
  </section>

  <% if outflow %>
    <p class="sr-only" role="status" aria-live="polite" aria-atomic="true" data-recurring-form-target="status"></p>
  <% end %>
```

The `DS::Disclosure "Recurring payment"` is gone. The `Details` disclosure and the submit section are unchanged.

In `app/helpers/recurring_transactions_helper.rb`, delete `recurring_credit_account_ids` (the comment line and the method). It has no callers left.

- [ ] **Step 5: Update the convert fields**

Replace `app/views/transactions/recurrences/_fields.html.erb` with:

```erb
<%# locals: (entry:, recurrence:, error: nil, autofocus: false) %>

<% block_error = error || (recurrence && (recurrence.errors[:base] + recurrence.errors[:account]).first) %>

<div class="p-3">
  <h4 class="text-sm text-primary">Recurring payment</h4>

  <%= form_with url: new_transaction_recurrence_path(entry), method: :get,
        class: "mt-3 rounded-lg bg-container-inset p-3 space-y-3",
        data: {
          controller: "recurring-form",
          recurring_form_preview_url_value: preview_recurring_transactions_path(entry_id: entry.id),
          recurring_form_unavailable_text_value: "We couldn't calculate this. You can still save.",
          action: "input->recurring-form#schedulePreview change->recurring-form#schedulePreview"
        } do %>
    <% if block_error %>
      <div role="alert">
        <%= render DS::Alert.new(message: block_error, variant: :error) %>
      </div>
    <% end %>

    <%= render "transactions/recurrence_fields", recurrence: recurrence, show_base_error: false, autofocus: autofocus %>

    <div class="flex flex-col-reverse sm:flex-row sm:justify-end gap-2">
      <%= render DS::Link.new(text: "Cancel", variant: "ghost", href: transaction_recurrence_path(entry)) %>
      <%= render DS::Button.new(
        text: "Review",
        type: "submit",
        disabled: recurrence&.frequency.blank?,
        aria: { label: "Review recurring payment" },
        data: { recurring_form_target: "review" }
      ) %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 6: Rewrite the Stimulus controller**

The rewrite keeps the fixes from earlier reviews:
- One live region, written only when its text changes.
- A 500 ms debounce.
- Only watched fields trigger a preview.
- An unchanged `src` is never refetched.
- Stale responses after Repeat returns to None are cleared.
- A failure removes `src` and announces the unavailable text once.

`app/javascript/controllers/recurring_form_controller.js`:

```js
import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="recurring-form"
// Shows "Ends after" once Repeat has a frequency and asks the server for a live summary
// 500 ms after the last change. It never formats money or computes payments.
export default class extends Controller {
  static targets = ["endsAfter", "preview", "status", "review"];
  static values = {
    previewUrl: String,
    unavailableText: String,
  };

  connect() {
    this.#applyFrequency();
    if (this.#frequency) this.schedulePreview();
  }

  disconnect() {
    clearTimeout(this.previewTimeout);
  }

  frequencyChanged() {
    this.#applyFrequency();
    this.#announce("");
    this.schedulePreview();
  }

  schedulePreview(event) {
    if (!this.hasPreviewTarget) return;
    if (event?.target && !this.#watched(event.target.name)) return;
    clearTimeout(this.previewTimeout);

    if (!this.#frequency) {
      this.#clearPreview();
      return;
    }

    this.previewTarget.setAttribute("aria-busy", "true");
    this.previewTarget.classList.add("opacity-60");
    this.previewTimeout = setTimeout(() => this.#loadPreview(), 500);
  }

  previewLoaded() {
    this.#finishLoading();

    // A response that arrives after Repeat went back to None is stale
    if (!this.#frequency) {
      this.#clearPreview();
      return;
    }

    this.#restoreProjection();

    const announcement = this.previewTarget.querySelector(
      "[data-recurring-form-announcement]",
    );
    this.#announce(announcement ? announcement.textContent.trim() : "");
  }

  previewFailed(event) {
    event.preventDefault();
    this.#finishLoading();
    this.previewTarget.removeAttribute("src");

    if (this.previewTarget.textContent.trim() === "") {
      const box = document.createElement("div");
      box.className = "rounded-lg bg-container-inset px-3 py-2";
      const message = document.createElement("p");
      message.className = "text-sm text-secondary";
      message.textContent = this.unavailableTextValue;
      box.append(message);
      this.previewTarget.replaceChildren(box);
    }

    this.#announce(this.unavailableTextValue);
  }

  // The Monthly projection disclosure is re-rendered with every summary; keep it as the person left it
  projectionToggled(event) {
    if (event.target instanceof HTMLDetailsElement) {
      this.projectionOpen = event.target.open;
    }
  }

  get #frequency() {
    const select = this.#form.elements.namedItem("recurrence[frequency]");
    return select ? select.value : "";
  }

  get #form() {
    return this.element.closest("form") || this.element;
  }

  #watched(name) {
    return (
      typeof name === "string" &&
      (name.startsWith("recurrence[") ||
        [
          "entry[account_id]",
          "entry[amount]",
          "entry[currency]",
          "entry[date]",
        ].includes(name))
    );
  }

  #applyFrequency() {
    const repeats = this.#frequency !== "";

    if (this.hasEndsAfterTarget) {
      this.endsAfterTarget.hidden = !repeats;
      this.endsAfterTarget.querySelectorAll("input").forEach((input) => {
        input.disabled = !repeats;
      });
    }

    if (this.hasReviewTarget) this.reviewTarget.disabled = !repeats;
  }

  #restoreProjection() {
    if (!this.projectionOpen) return;

    const details = this.previewTarget.querySelector(
      "[data-recurring-form-projection] details",
    );
    if (details) details.open = true;
  }

  #loadPreview() {
    const url = new URL(this.previewUrlValue, window.location.origin);
    const data = new FormData(this.#form);

    [
      "entry[account_id]",
      "entry[amount]",
      "entry[currency]",
      "entry[date]",
      "recurrence[frequency]",
      "recurrence[total_payments]",
    ].forEach((name) => {
      const value = data.get(name);
      if (value !== null) url.searchParams.set(name, value);
    });

    const src = url.toString();
    if (this.previewTarget.getAttribute("src") === src) {
      this.#finishLoading();
      return;
    }

    this.previewTarget.src = src;
  }

  #clearPreview() {
    this.previewTarget.removeAttribute("src");
    this.previewTarget.replaceChildren();
    this.#finishLoading();
  }

  #finishLoading() {
    this.previewTarget.removeAttribute("aria-busy");
    this.previewTarget.classList.remove("opacity-60");
  }

  #announce(text) {
    if (this.hasStatusTarget && this.statusTarget.textContent !== text) {
      this.statusTarget.textContent = text;
    }
  }
}
```

- [ ] **Step 7: Run the tests and lint**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/transactions_controller_test.rb test/controllers/transactions/recurrences_controller_test.rb test/controllers/recurring_transactions_controller_test.rb
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/transactions/_recurrence_fields.html.erb app/views/transactions/_form.html.erb app/views/transactions/recurrences/_fields.html.erb -a
npm run lint
grep -rn "recurring_credit_account_ids\|installmentsOption\|firstPayment\|syncFirstPayment\|accountChanged\|selectType\|plan_type" app/views app/javascript app/helpers
```

Expected:
- The tests PASS, apart from baseline names.
- erb_lint and Biome are clean.
- The final grep prints nothing.

- [ ] **Step 8: Commit**

```bash
git add app/views/transactions/_recurrence_fields.html.erb app/views/transactions/_form.html.erb app/views/transactions/recurrences/_fields.html.erb app/javascript/controllers/recurring_form_controller.js app/helpers/recurring_transactions_helper.rb test/controllers/transactions_controller_test.rb test/controllers/transactions/recurrences_controller_test.rb
git commit -m "Capture recurring payments with a Repeat select and an optional end count

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Convert confirmation (B3) per plan type

**Files:**
- Modify: `app/views/transactions/recurrences/_confirm.html.erb` (whole file)
- Test: `test/controllers/transactions/recurrences_controller_test.rb`

**Interfaces:**
- Consumes:
  - `recurring_every`, `recurring_charge_label`, `recurring_payments_noun` (Task 7).
  - `#credit_card?`, `#occurrence_amount`, `#backfill_count` (Tasks 2-3).
  - The convert controller with `frequency` params (Task 3).
- Produces: the confirm step posts `recurrence[frequency]` and `recurrence[total_payments]` as hidden fields.
  - Card installments: unchanged copy.
  - Installments off a card: `r3.confirm_heading_payments`, `r3.confirm_point_first_payment`, `r3.confirm_primary_payments`.
  - Charges: `r3.confirm_heading_charge`, `r3.confirm_primary_charge`.

- [ ] **Step 1: Write the failing tests**

Append before the final `end` of `test/controllers/transactions/recurrences_controller_test.rb`:

```ruby
  test "review of a weekly charge names its frequency" do
    get new_transaction_recurrence_url(@entry), params: { recurrence: { frequency: "weekly" } }, headers: @frame

    assert_response :success
    assert_includes response.body, "Repeat $3,000.00 every week"
    assert_includes response.body, "Start weekly charge"
    assert_select "input[type=hidden][name='recurrence[frequency]'][value='weekly']"
  end

  test "review of installments off a card says the transaction becomes payment 1" do
    entry = create_transaction(account: accounts(:depository), amount: 1200, name: "Desk", date: Date.new(2026, 10, 1))
    frame = { "Turbo-Frame" => dom_id(entry, :recurrence) }

    get new_transaction_recurrence_url(entry), params: { recurrence: { frequency: "monthly", total_payments: "3" } }, headers: frame

    assert_response :success
    assert_includes response.body, "Split $1,200.00 into 3 payments"
    assert_includes response.body, "This transaction becomes payment 1 ($400.00)."
    assert_includes response.body, "Split into 3 payments"
    assert_not_includes response.body, "Your card balance stays the same."
  end

  test "converting installments off a card rewrites the transaction as payment 1" do
    entry = create_transaction(account: accounts(:depository), amount: 1200, name: "Desk", date: Date.new(2026, 10, 1))

    post transaction_recurrence_url(entry), params: { recurrence: { frequency: "monthly", total_payments: "3" } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_equal BigDecimal("400"), entry.reload.amount
    assert_includes response.body, "Split into 3 payments."
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/transactions/recurrences_controller_test.rb`

Expected: FAIL.
- The heading reads "Repeat $3,000.00 every month".
- The button reads "Start monthly charge".
- There is no hidden `recurrence[frequency]`.
- The non-card heading says "installments".

- [ ] **Step 3: Implement**

Replace `app/views/transactions/recurrences/_confirm.html.erb` with:

```erb
<%# locals: (entry:, recurrence:, error: nil) %>

<% total = recurring_money(entry.amount.abs, entry.currency) %>
<% backfill = recurrence.backfill_count %>
<% card_installments = recurrence.installments? && recurrence.credit_card? %>
<% backfill_noun = card_installments ? "installment" : "payment" %>

<div class="p-3">
  <h4 class="text-sm text-primary">Recurring payment</h4>

  <%= form_with url: transaction_recurrence_path(entry), method: :post, class: "mt-3 rounded-lg border border-tertiary p-3 space-y-3" do %>
    <% if error %>
      <div role="alert">
        <%= render DS::Alert.new(message: error, variant: :error) %>
      </div>
    <% end %>

    <%= hidden_field_tag "recurrence[frequency]", recurrence.frequency, id: nil %>
    <%= hidden_field_tag "recurrence[total_payments]", recurrence.total_payments, id: nil %>

    <h4 tabindex="-1" autofocus class="text-sm font-medium text-primary tabular-nums rounded outline-none focus-visible:ring-4 focus-visible:ring-alpha-black-200">
      <% if recurrence.installments? %>
        Split <%= total %> into <%= recurrence.total_payments %> <%= recurring_payments_noun(recurrence) %>
      <% else %>
        Repeat <%= total %> <%= recurring_every(recurrence) %>
      <% end %>
    </h4>

    <ul class="list-disc pl-5 space-y-1 text-sm text-secondary tabular-nums">
      <% if card_installments %>
        <li>Your card balance stays the same.</li>
      <% elsif recurrence.installments? %>
        <li>This transaction becomes payment 1 (<%= recurring_money(recurrence.occurrence_amount(1), recurrence.currency) %>).</li>
      <% end %>
      <% if backfill.positive? %>
        <li>Adds <%= backfill %> past <%= backfill_noun.pluralize(backfill) %> with their original dates. Past budgets will change.</li>
      <% end %>
    </ul>

    <div class="flex flex-col-reverse sm:flex-row sm:justify-end gap-2">
      <%= render DS::Link.new(text: "Cancel", variant: "outline", href: transaction_recurrence_path(entry)) %>
      <%= render DS::Button.new(
        text: recurrence.installments? ? "Split into #{recurrence.total_payments} #{recurring_payments_noun(recurrence)}" : "Start #{recurring_charge_label(recurrence).downcase_first}",
        type: "submit"
      ) %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/transactions/recurrences_controller_test.rb`

Expected: PASS. This includes the card tests "review confirms what will change" and "a failed conversion shows the error on the confirm step", which still read "Split $3,000.00 into 3 installments".

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/transactions/recurrences/_confirm.html.erb -a
git add app/views/transactions/recurrences/_confirm.html.erb test/controllers/transactions/recurrences_controller_test.rb
git commit -m "Confirm conversions per plan type and frequency

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Monthly projection block

**Files:**
- Modify: `app/views/recurring_transactions/_preview.html.erb` (lines 6, 26-28)
- Rewrite: `app/views/recurring_transactions/_budget_impact.html.erb`
- Modify: `app/helpers/recurring_transactions_helper.rb` (add `budget_impact_subtitle`, `budget_impact_month_summary` after `budget_impact_title`)
- Test: `test/helpers/recurring_transactions_helper_test.rb`, `test/controllers/recurring_transactions_controller_test.rb`

**Interfaces:**
- Consumes:
  - `BudgetImpact#months`, `#category_legend`, `#payments_count`, `#counts_months?`, `Month#category_segments`, `Month#estimated?`, `Month#total` (Task 6).
  - `recurring-form#projectionToggled` (Task 8).
- Produces:
  - `budget_impact_subtitle(impact) -> String` (`bi.subtitle` / `bi.subtitle_months`).
  - `budget_impact_month_summary(month) -> String` (`pm.month_sr`).
  - The preview renders `<div data-recurring-form-projection data-action="toggle->recurring-form#projectionToggled:capture">` around a closed `DS::Disclosure` titled "Monthly projection" whenever Repeat ≠ None and the impact is available.

- [ ] **Step 1: Write the failing tests**

Append before `private` in `test/helpers/recurring_transactions_helper_test.rb`:

```ruby
  test "the projection subtitle counts payments, or months for daily and weekly plans" do
    assert_equal "Budget impact of the next 3 payments", budget_impact_subtitle(stub(counts_months?: false, payments_count: 3))
    assert_equal "Budget impact of the next payment", budget_impact_subtitle(stub(counts_months?: false, payments_count: 1))
    assert_equal "Budget impact of the next 3 months", budget_impact_subtitle(stub(counts_months?: true, months: [ 1, 2, 3 ]))
    assert_equal "Budget impact of the next month", budget_impact_subtitle(stub(counts_months?: true, months: [ 1 ]))
  end

  test "each projection bar has a spoken summary" do
    budget = stub(name: "November 2026", currency: "USD")
    over = stub(budget: budget, total: BigDecimal("7801"), basis: BigDecimal("7500"), over?: true, overage: BigDecimal("301"))
    under = stub(budget: budget, total: BigDecimal("7301"), basis: BigDecimal("7500"), over?: false, overage: BigDecimal("-199"))

    assert_equal "November 2026: $7,801.00 of $7,500.00, $301.00 over", budget_impact_month_summary(over)
    assert_equal "November 2026: $7,301.00 of $7,500.00, $199.00 left", budget_impact_month_summary(under)
  end
```

In `test/controllers/recurring_transactions_controller_test.rb`, replace the three assertions at the end of `"preview shows the budget impact when asked"` with:

```ruby
    assert_includes response.body, "This puts 3 budgets over. The first is November 2026."
    assert_includes response.body, "Budget impact of the next 3 payments"
    assert_includes response.body, "Months without a budget use your October 2026 budget."
    assert_includes response.body, "Expenses in installments"
    assert_includes response.body, "November 2026: "
    assert_select "details:not([open]) summary", text: /Monthly projection/
    assert_select "[data-recurring-form-projection] div.overflow-hidden.rounded-full", 3
  end
```

Append before `private` (or before the final `end`):

```ruby
  test "a recurring charge gets the monthly projection too" do
    family = families(:dylan_family)
    family.budgets.destroy_all
    family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                           currency: "USD", budgeted_spending: 1000, expected_income: 3000)

    get preview_recurring_transactions_url, params: {
      impact: "1",
      entry: { account_id: @card.id, amount: "50", currency: "USD", date: "2026-10-08" },
      recurrence: { frequency: "weekly" }
    }, headers: @frame

    assert_includes response.body, "$50.00 every week"
    assert_includes response.body, "Monthly projection"
    assert_includes response.body, "Budget impact of the next 3 months"
  end

  test "the convert preview never shows the projection" do
    entry = create_transaction(account: @card, amount: 199, name: "Spotify", date: Date.new(2026, 10, 1))

    get preview_recurring_transactions_url, params: { entry_id: entry.id, recurrence: { frequency: "monthly" } }, headers: @frame

    assert_not_includes response.body, "Monthly projection"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/helpers/recurring_transactions_helper_test.rb test/controllers/recurring_transactions_controller_test.rb`

Expected: FAIL.
- `undefined method 'budget_impact_subtitle'`.
- There is no "Monthly projection" and no "Expenses in installments".
- The weekly charge shows no projection.

- [ ] **Step 3: Implement the helpers**

In `app/helpers/recurring_transactions_helper.rb`, after `budget_impact_title`:

```ruby
  # bi.subtitle / bi.subtitle_months
  def budget_impact_subtitle(impact)
    if impact.counts_months?
      count = impact.months.size
      count == 1 ? "Budget impact of the next month" : "Budget impact of the next #{count} months"
    else
      count = impact.payments_count
      count == 1 ? "Budget impact of the next payment" : "Budget impact of the next #{count} payments"
    end
  end

  # pm.month_sr: what one bar says to a screen reader
  def budget_impact_month_summary(month)
    currency = month.budget.currency
    state = month.over? ? "#{recurring_money(month.overage, currency)} over" : "#{recurring_money(month.basis - month.total, currency)} left"

    "#{month.budget.name}: #{recurring_money(month.total, currency)} of #{recurring_money(month.basis, currency)}, #{state}"
  end
```

- [ ] **Step 4: Implement the views**

`app/views/recurring_transactions/_preview.html.erb`. Line 6 becomes:

```erb
    <% impact = plan.budget_impact if show_impact %>
```

and lines 26-28 (`<% if impact %> … <% end %>`) become:

```erb
      <% if impact %>
        <%# Closed by default; recurring-form keeps it open across refreshes once the person opens it %>
        <div data-recurring-form-projection data-action="toggle->recurring-form#projectionToggled:capture">
          <%= render DS::Disclosure.new(title: "Monthly projection") do %>
            <%= render "recurring_transactions/budget_impact", impact: impact, title: impact_title %>
          <% end %>
        </div>
      <% end %>
```

Replace `app/views/recurring_transactions/_budget_impact.html.erb` with:

```erb
<%# locals: (impact:, title:) %>

<% over_text = "text-red-700 theme-dark:text-red-400" %>
<% subtitle = budget_impact_subtitle(impact) %>

<section aria-labelledby="recurring-impact-title" class="rounded-lg border border-tertiary p-3 flex flex-col gap-3">
  <% if title %>
    <div class="flex items-start gap-2">
      <%= icon "alert-triangle", size: "sm", color: "current", class: "mt-0.5 #{over_text}" %>
      <div class="text-sm tabular-nums min-w-0">
        <p id="recurring-impact-title" class="font-medium <%= over_text %>"><%= title %></p>
        <p class="text-secondary"><%= subtitle %></p>
      </div>
    </div>
  <% else %>
    <p id="recurring-impact-title" class="text-sm font-medium text-primary"><%= subtitle %></p>
  <% end %>

  <ul class="flex flex-col gap-3">
    <% impact.months.each do |month| %>
      <% currency = month.budget.currency %>
      <li class="flex flex-col gap-1.5">
        <p class="sr-only"><%= budget_impact_month_summary(month) %></p>

        <div class="flex items-center justify-between text-sm tabular-nums" aria-hidden="true">
          <span class="text-primary font-medium"><%= month.budget.name %></span>
          <% if month.over? %>
            <span class="font-medium <%= over_text %>"><%= recurring_money(month.overage, currency) %> over</span>
          <% else %>
            <span class="text-secondary"><%= month.percent %>% of budget</span>
          <% end %>
        </div>

        <%# The track clips the segments, so the bar is always rounded at both ends; the budget mark sits outside it %>
        <div class="relative" aria-hidden="true">
          <div class="flex h-2 overflow-hidden rounded-full bg-surface-inset">
            <div class="h-full bg-inverse" style="width: <%= impact.width(month.committed) %>%"></div>
            <% month.category_segments.each do |segment| %>
              <div class="h-full" style="width: <%= impact.width(segment.amount) %>%; background-color: <%= segment.color %>"></div>
            <% end %>
            <div class="h-full bg-destructive" style="width: <%= impact.width(month.purchase) %>%"></div>
          </div>
          <div class="absolute -top-1 h-4 w-0.5 rounded-sm bg-current text-secondary" style="left: <%= impact.width(month.basis) %>%"></div>
        </div>

        <p class="text-xs text-secondary tabular-nums" aria-hidden="true">
          <%= recurring_money(month.total, currency) %> of <%= recurring_money(month.basis, currency) %> budgeted<% if month.estimated? %> <span>·</span> categories avg<% end %>
        </p>
      </li>
    <% end %>
  </ul>

  <ul class="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs text-secondary">
    <li class="flex items-center gap-1.5"><span class="size-2 rounded-sm bg-inverse" aria-hidden="true"></span>Expenses in installments</li>
    <% impact.category_legend.each do |label, color| %>
      <li class="flex items-center gap-1.5"><span class="size-2 rounded-sm" style="background-color: <%= color %>" aria-hidden="true"></span><%= label %></li>
    <% end %>
    <li class="flex items-center gap-1.5"><span class="size-2 rounded-sm bg-destructive" aria-hidden="true"></span>This purchase</li>
    <li class="flex items-center gap-1.5"><span class="h-2.5 w-0.5 bg-current" aria-hidden="true"></span>Budget</li>
  </ul>

  <% if (reference = impact.reference_budget) %>
    <p class="text-xs text-secondary">Months without a budget use your <%= reference.name %> budget.</p>
  <% end %>
</section>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/helpers/recurring_transactions_helper_test.rb test/controllers/recurring_transactions_controller_test.rb test/models/recurring_transaction/budget_impact_test.rb`

Expected: PASS.

- [ ] **Step 6: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/helpers/recurring_transactions_helper.rb test/helpers/recurring_transactions_helper_test.rb test/controllers/recurring_transactions_controller_test.rb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/recurring_transactions/_preview.html.erb app/views/recurring_transactions/_budget_impact.html.erb -a
git add app/helpers/recurring_transactions_helper.rb app/views/recurring_transactions/_preview.html.erb app/views/recurring_transactions/_budget_impact.html.erb test/helpers/recurring_transactions_helper_test.rb test/controllers/recurring_transactions_controller_test.rb
git commit -m "Show the budget impact as a collapsed Monthly projection with category spend

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Frequency wording on the card tab and the plan dialog

**Files:**
- Modify: `app/views/credit_cards/tabs/_recurring.html.erb`: lines 70 and 87 (installments table), 105, 109 and 125 (charges table), 153 (past plans).
- Modify: `app/views/recurring_transactions/show.html.erb:56-61` (lock note)
- Test: `test/controllers/credit_card_recurring_tab_test.rb`, `test/controllers/recurring_transactions_controller_test.rb`

**Interfaces:**
- Consumes:
  - `#next_payment_amount`, frequency-aware `#monthly_amount` (Task 2).
  - `recurring_every`, `recurring_charge_label`, and the subtitle parts (Task 7).
- Produces:
  - Card tab:
    - The KPI "Committed per month" (unchanged label) sums monthly amounts per budget month.
    - Both tables show a "Payment" column with the per-payment amount and an "every {unit}" second line.
    - The charges caption is "Charges".
    - Past plans show "Installments" or the charge label.
  - Plan dialog: installments off a card show `c3.schedule_locked_payments`.

- [ ] **Step 1: Write the failing tests**

In `test/controllers/credit_card_recurring_tab_test.rb`, `"shows the card's commitments"`:
- Change `assert_includes response.body, "Monthly charges"` to `assert_includes response.body, "Charges"`.
- Add:

```ruby
    assert_not_includes response.body, "Per month"
    assert_not_includes response.body, "Monthly charges"
    assert_includes response.body, "every month"
```

Append before the final `end`:

```ruby
  test "a weekly charge shows its payment and frequency" do
    families(:dylan_family).recurring_transactions.create!(account: @card, name: "Cleaner", plan_type: "charge", frequency: "weekly",
                                                           amount: 50, currency: "USD", start_date: Date.new(2026, 10, 1))

    get account_url(@card, tab: "recurring"), headers: { "Turbo-Frame" => "account" }

    assert_includes response.body, "$250.00" # Committed per month: Oct 1, 8, 15, 22, 29
    assert_includes response.body, "$50.00"
    assert_includes response.body, "every week"
    assert_includes response.body, "Weekly charge"
  end
```

Append before `private` in `test/controllers/recurring_transactions_controller_test.rb`:

```ruby
  test "the dialog of a weekly charge names its frequency" do
    plan = families(:dylan_family).recurring_transactions.create!(
      account: @card, name: "Cleaner", plan_type: "charge", frequency: "weekly", amount: 600, currency: "USD", start_date: Date.new(2026, 10, 12)
    )

    get recurring_transaction_url(plan), headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_includes response.body, "$600.00 every week"
  end

  test "the dialog of installments off a card says how to change the schedule" do
    purchase = create_transaction(account: accounts(:depository), amount: 1200, name: "Desk", date: Date.new(2026, 10, 1))
    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)

    get recurring_transaction_url(plan), headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_includes response.body, "3 payments of $400.00"
    assert_includes response.body, "every month"
    assert_includes response.body, "To change payments or dates, stop this plan and add a new one."
    assert_not_includes response.body, "delete the purchase"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/credit_card_recurring_tab_test.rb test/controllers/recurring_transactions_controller_test.rb`

Expected: FAIL.
- "Per month" and "Monthly charges" are still present.
- There is no "every week".
- Past plans and the dialog lock note use the card copy.

- [ ] **Step 3: Implement the card tab**

In `app/views/credit_cards/tabs/_recurring.html.erb`:
- Line 70 (installments header): `<th scope="col" class="text-right font-medium px-4 py-2">Payment</th>`
- Line 87 (installments amount cell) becomes:

```erb
              <td class="px-4 py-3 align-top text-right">
                <p class="text-primary"><%= recurring_money(plan.next_payment_amount, plan.currency) %></p>
                <p class="text-xs text-secondary whitespace-nowrap"><%= recurring_every(plan) %></p>
              </td>
```

- Line 105 (caption): `<caption class="text-left text-sm font-medium text-primary mb-2">Charges</caption>`
- Line 109 (charges header): `<th scope="col" class="text-right font-medium px-4 py-2">Payment</th>`
- Line 125 (charges amount cell) becomes:

```erb
              <td class="px-4 py-3 align-top text-right">
                <p class="text-primary"><%= recurring_money(plan.amount, plan.currency) %></p>
                <p class="text-xs text-secondary whitespace-nowrap"><%= recurring_every(plan) %></p>
              </td>
```

- Line 153 (past plans): `<p class="text-xs text-secondary"><%= plan.installments? ? "Installments" : recurring_charge_label(plan) %></p>`

- [ ] **Step 4: Implement the dialog lock note**

In `app/views/recurring_transactions/show.html.erb`, the `<p>` inside the installments lock block (line 59) becomes:

```erb
              <p class="text-sm text-secondary"><%= plan.credit_card? ? "To change installments or dates, delete the purchase and add it again." : "To change payments or dates, stop this plan and add a new one." %></p>
```

The subtitle already uses `recurring_plan_subtitle_parts` (Task 7).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/credit_card_recurring_tab_test.rb test/controllers/recurring_transactions_controller_test.rb test/models/account/recurring_commitments_test.rb`

Expected: PASS.

- [ ] **Step 6: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/credit_cards/tabs/_recurring.html.erb app/views/recurring_transactions/show.html.erb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop test/controllers/credit_card_recurring_tab_test.rb test/controllers/recurring_transactions_controller_test.rb -a
git add app/views/credit_cards/tabs/_recurring.html.erb app/views/recurring_transactions/show.html.erb test/controllers/credit_card_recurring_tab_test.rb test/controllers/recurring_transactions_controller_test.rb
git commit -m "Use frequency wording on the card tab and in the plan dialog

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Final verification

**Files:** none. Fixes go into the task they belong to, as new commits.

**Interfaces:** Consumes everything above. Produces the evidence that the change is done.

- [ ] **Step 1: Full suite vs baseline, by name**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models test/jobs test/controllers test/helpers test/components 2>&1 | tee .superpowers/sdd/2026-10-11-final.log | tail -3
grep -A1 -E "^(Failure|Error):$" .superpowers/sdd/2026-10-11-final.log | grep "#test_" | sed -E 's/( \[[^]]*\])?:$//' | sort -u > .superpowers/sdd/2026-10-11-final-names.txt
comm -23 .superpowers/sdd/2026-10-11-final-names.txt .superpowers/sdd/2026-10-11-baseline-names.txt
```

Expected:
- `comm` prints nothing: no failing test that wasn't failing in the baseline.
- Every test added by this plan passes.
- The summary line shows the same 16 F / 118 E, unless a baseline test was deleted on purpose by this plan. Check `comm -13` and confirm any name that disappeared belongs to a deleted test: `"the first payment can't be missing or before the purchase"` or `"an unparseable start date renders the fields with 422 and saves nothing"`.

Fix any new failure with superpowers:systematic-debugging before continuing.

- [ ] **Step 2: Lint and security**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop -f github -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint ./app/**/*.erb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec brakeman --no-pager
npm run lint
```

Expected:
- rubocop and erb_lint are clean.
- brakeman shows no new warnings. The preview, convert and plan controllers scope every lookup to `Current.family`, and the inline `background-color` comes from `Category#color`, as in `budgets/_actuals_summary`.
- Biome is clean for `recurring_form_controller.js`.

Commit any autocorrections with explicit paths:

```bash
git add <changed files> && git commit -m "Apply lint fixes" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Copy check**

```bash
grep -rn "MSI\|(MSI)\|Months without interest\|Doesn't repeat\|Number of installments\|First payment\|Installments only work on credit cards\|Already committed\|Per month\|Monthly charges\| cycle" app/views app/helpers/recurring_transactions_helper.rb app/helpers/custom_confirm.rb app/controllers/concerns/recurrence_params.rb app/javascript/controllers/recurring_form_controller.js
```

Expected: no matches in UI strings. Code identifiers like `msi_purchase` are fine, and the grep is case-sensitive on purpose.

- [ ] **Step 4: Browser checklist (the orchestrator runs it)**

The orchestrator builds **only with the override**:

```bash
docker compose -f compose.yaml -f docs/dev/compose.test-db.yaml build web
docker compose -f compose.yaml -f docs/dev/compose.test-db.yaml up -d --no-deps web worker
```

Then it opens http://localhost:3001 as `bob@bobdylan.com` (password in `test/test_helper.rb`). Check each item at 375 / 768 / 1280 px, in light and dark.

**Capture form**
- New transaction → Expense:
  - "Repeat" sits right under Date, with "None" selected.
  - There is no "Recurring payment" disclosure, no radios, no "First payment" and no credit-only note.
  - The Income tab has no Repeat.
- Choose each frequency:
  - "Ends after [ ] payments" appears, with an empty "—" placeholder.
  - Back to None: it hides, its value is not submitted, and the summary clears.
  - Switching account never resets Repeat.
- Summary wording (~500 ms after typing stops, dimmed while recalculating, instant with reduced motion):
  - Weekly, no end: "$600.00 every week" / "No end date".
  - Every 2 months: "every 2 months". Annually: "every year".
  - With an end of 12: "12 payments of $1,250.00" / "Last on …", or "Last one $… on …" when rounding.
  - Past dates add "N already due…".
  - With the server stopped: "We couldn't calculate this. You can still save."
- Ends after 1 / 49 / 0 → 422 with "Enter 2 to 48 payments." under the field, `aria-invalid`, and focus on it.

**Saving**
- A credit card with an end of 3:
  - The purchase row reads "Paid in 3 installments".
  - The installment rows read "Installment 1 of 3".
  - The card balance is unchanged.
  - Notice: "Split into 3 installments."
- Checking with an end of 3:
  - The row amount becomes T/3, and the row reads "Payment 1 of 3".
  - Later rows read "Payment 2 of 3".
  - Their drawer shows a disabled amount with "Set by the plan.", with no Exclude, no One-time and no Transfer matcher.
  - Notice: "Split into 3 payments."
- Weekly charge: rows read "Weekly charge". Notice: "Weekly charge started."
- Repeat None saves an ordinary transaction exactly as before.

**Monthly projection**
- It is visible with any Repeat ≠ None when a budget exists, and closed by default.
- Once opened, it stays open while typing changes the summary.
- It is absent without a budget, and absent in Convert.
- Each bar is rounded at both ends whichever segment is at the edge. The budget mark is outside the clipped track and is not cut off.
- Segments, in order: "Expenses in installments" (inverse), the category colours, then "This purchase" (red).
- Future months end their detail line with "· categories avg".
- The legend shows at most 4 categories plus "Other".
- The red header ("This puts … over budget") appears when the total, category spend included, exceeds the budget.
- The subtitle reads "Budget impact of the next 3 payments", or "… next 3 months" for weekly and daily plans.
- VoiceOver reads one spoken summary per bar ("November 2026: $… of $…, $… over") and the legend. It does not read the segments.

**Convert (B3)**
- Drawer → Edit: the Repeat select has focus, and Review is disabled until a frequency is chosen.
- Weekly → Review: "Repeat $X every week" / "Start weekly charge".
- Checking with an end of 3: "Split $X into 3 payments" / "This transaction becomes payment 1 ($…)." / "Split into 3 payments".
- Card with an end of 3: unchanged copy.

**Other surfaces**
- Plan dialog:
  - Subtitles "12 payments of $1,250.00 · every month · Active" and "$600.00 every week · Active".
  - The lock note for payments off a card reads "To change payments or dates, stop this plan and add a new one."
  - Stopping it says "The N payments left ($…) won't be added."
- Card tab:
  - "Committed per month" counts a weekly charge's month (≈ 4–5 payments).
  - Both tables show a "Payment" column with an "every …" line.
  - The caption reads "Charges".
  - Past plans show the charge label.
  - No overflow at 375 px.
- Families without plans: transactions, budgets and credit cards look exactly as before.

- [ ] **Step 5: Record and hand off**

Add a `design-state.md` decision row dated 2026-10-11 ("Repeat + Monthly projection built", commit range, defaults from "Spec ambiguities resolved" below), and update "Status / Pending". Then commit:

```bash
git add design-state.md
git commit -m "Record Repeat and Monthly projection completion in design state

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Spec coverage (self-review)

| Spec item | Task |
|---|---|
| §1 Repeat select under Date, 8 options in order, None default; conditional "Ends after" (optional, 2–48) | 7 (options), 8 |
| §1 Type rule table (no end → charge per payment; N ≥ 2 → installments on the total; 1 → error) | 3 |
| §1 First payment: charge = the transaction; installments = one interval later (cards) | 3 |
| §1 Credit card MSI flow unchanged | 3 (existing tests kept) |
| §1 Other accounts: entry rewritten to T/N as payment 1, N−1 standard rows, plan keeps T, locks | 3, 4 |
| §1 Live summary per frequency, same frame and debounce | 7, 8 |
| §1 Copy: new §14 strings, removals | 7 |
| §2 Collapsed "Monthly projection", only when Repeat ≠ None and available | 10 |
| §2 Months = budget months of the next 3 payments; short frequencies = next 3 months with a payment | 6 |
| §2 Segments: installments (`committed_spending`), category spend (current actuals / future averages, no plan rows or excluded kinds), this purchase | 5, 6, 10 |
| §2 Always-rounded bar (`overflow-hidden rounded-full`), no per-segment radius, marker as overlay | 10 |
| §2 Legend order, top 4 + Other, "avg" marking | 6, 10 |
| §2 Over-budget compares the full total; subtitle "next 3 payments" | 6, 10 |
| §2 Accessibility: sr-only per bar, segments `aria-hidden`, legend carries meaning | 10 |
| §3 Migration `frequency` (user runs it) | 1 |
| §3 `FREQUENCIES`, `occurrence_date` with clamping, derived `plan_type`, ranges, credit-card rule removed | 2, 3 |
| §3 `create_from_entry!` / `build_from_entry` accept `frequency` / `total_payments`, ignore `plan_type` | 3 |
| §3 Lock rules (card kinds + plan-linked standard rows of installments elsewhere; charge rows editable) | 4 |
| §3 `Budget#category_spend_for_projection`, `Month#category_segments`, parity kept | 5, 6 |
| §3 `RecurrenceParams` permits `frequency, total_payments` only | 3 |
| §4 Plan dialog subtitle with frequency; schedule stays locked | 2 (lock), 7, 11 |
| §4 Card tab wording; committed per month per budget month; row labels | 2, 7, 11 |
| §5 Errors: end count → 422; unknown frequency → 422, never 500 | 3, 8 |
| §5 Daily plans generate lazily, one row per day | 2 (unchanged generation, frequency-aware dates) |
| §5 Rounding: last payment absorbs the remainder | unchanged (`occurrence_amount`) |
| §6 Model, BudgetImpact, controller, browser tests | 2–11, 12 |

## Spec ambiguities resolved in this plan

1. **First payment of installments off a card.** §1 makes the captured entry payment 1, but §3 says "installments `start_date` = entry date + 1 interval".
   - Plan: one interval after the purchase only on credit cards, where the purchase is the `msi_purchase` and not a payment.
   - Off a card, `start_date` = the entry date, so `occurrence_date(1)` is the entry itself and the last payment is N−1 intervals later.
2. **Which "average".** Future budget rows label `median_monthly_expense` as "avg" (`_budget_category.html.erb:40`). The projection uses that same median per category, so the figure matches what the person sees on the budget.
3. **Averages without double counting.** The existing median includes plan-linked rows, which would count recurring charges twice next to "Expenses in installments". A new `exclude_recurring:` option drops them, in both actuals and averages, and is cached separately.
4. **"Recurring (empty): up to 600".** Any end count now means installments (2–48), so 49–600 gives "Enter 2 to 48 payments.". The 600 cap and its message remain only for charges stored with an end before this change.
5. **Card tab "Per month".**
   - "Committed per month" sums every payment in the budget month of each plan's next payment, as `committed_spending` does. Weekly ≈ 4–5 payments, and an annual charge counts in full in its month.
   - The tables show a "Payment" column (per-payment amount + "every {unit}"), and "Monthly charges" becomes "Charges".
6. **"{Frequency} charge" labels.** Labels for frequencies whose name isn't an adjective: "Charge every 2 months", "Charge every 6 months", "Annual charge".
7. **"payments" vs "installments".** Following the spec examples:
   - The summary and the dialog subtitle say "payments" for every plan.
   - Rows, Convert, notices and the card tab keep "installments" for credit cards and say "payments" elsewhere.
8. **Projection subtitle for daily/weekly plans.** These would read "next 13 payments", so they count months: "Budget impact of the next 3 months".
9. **Legend overflow.**
   - With more than 4 categories, the bars show the top 4 and one "Other" segment, so every colour is in the legend.
   - "Other" uses the uncategorized grey, and Uncategorized folds into it so there aren't two greys.
10. **"Future months mark them avg".** The legend is shared across months, so each future month's detail line ends with "· categories avg".
11. **Collapsed but stable.** The disclosure lives inside the refreshed frame. `recurring-form` remembers it was opened (the `toggle` event is caught in the capture phase) and re-opens it after each refresh.
12. **New copy the spec didn't write**, all marked _(default)_ in §14:
    - `r.err.frequency`
    - `r3.confirm_point_first_payment` (the convert confirm warns that the amount changes)
    - `c3.schedule_locked_payments`
    - `r.confirm_stop_body_payments`
    - `bi.subtitle_months`
    - `pm.month_detail_avg`
    - the `c2` column and caption
13. **Projection for charges.** Previously only installments got the impact block. Per §2 ("Repeat ≠ None"), charges get it too. Payment 1 of a charge, and of installments off a card, falls in the current month.
14. **Plan destroy off a card.** Only an account deletion reaches it in v1. It unlinks the payments (they are real spending) instead of deleting them as card installments do.
15. **Transfers.** Payments of installments off a card are excluded from auto-matching and refused by `Transfer` and the matcher. Otherwise an auto-match would raise on the kind lock.
16. **Icon.** `credit-card` only for card installments, `repeat` for everything else.
17. **Tampered `recurrence=foo`.** It now reads as "no recurrence" (`RecurrenceParams`), which also closes deferred minor m-"tampered recurrence param 500" from the Phase B/C review.
18. **First-payment validation removed.** The start date is always derived, so it can't precede the purchase. The "Choose a date for the first payment." presence message stays as an internal guard.

**Migration required:** one, `20261011120000_add_frequency_to_recurring_transactions` (Task 1, run by the user).
