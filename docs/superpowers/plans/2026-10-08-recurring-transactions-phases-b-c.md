# Recurring Payments & Installments — Phases B + C (Capture, View, Manage) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the UI for recurring payments on top of the Phase A model: capture a monthly charge or an installment purchase from "New transaction" (with a server-rendered live summary and a budget-impact projection), convert an existing transaction from its drawer, explain generated rows, show commitments on the credit card and in budgets, manage plans (view / edit / stop / delete) with safe confirms, and plan budgets up to 12 months ahead.

**Architecture:** One shared calculation, `Family::RecurringCommitments` (generated plan rows in a date range + not-yet-generated occurrences of active plans), feeds `Budget#committed_spending` / `Budget#budget_basis` (C4 block, warning, future months), `RecurringTransaction::BudgetImpact` (capture preview) and `Account::RecurringCommitments` (credit-card tab); parity tests pin them together. Future months reuse the budget screen: `Budget#actual_spending` returns the committed amount when `future?` (single decision point), views only swap labels. UI is Hotwire: Turbo frames for the live summary and the convert flow, one small Stimulus controller (`recurring-form`), the global confirm dialog gains a safe secondary button.

**Tech Stack:** Rails 7.2, Ruby 3.4, PostgreSQL, Hotwire (Turbo 8 / turbo-rails 2.0.16, Stimulus), ViewComponent DS components, Tailwind v4 design system, Minitest + fixtures, Docker/OrbStack.

**Design sources (read before any view task):** `design-state.md` · `docs/designpowers/interaction/2026-10-08-pagos-recurrentes-msi-interaction.md` · `docs/designpowers/visual/2026-10-08-pagos-recurrentes-msi-visual.md` (rev 3) · `docs/designpowers/content/2026-10-08-pagos-recurrentes-msi-copy.md` ("Kept" tables are the source of truth) · `docs/designpowers/visual/canvas/*.dc.html` (final visual reference: `Main` = B1/B2, `Convert` = B3, `Rows` = C1, `Card` = C2, `Dialogs` = C3, `Budget` = C4, `Future` = future months).

## Global Constraints

- Branch: `feature/meses-sin-intereses`. Phase A is merged on it (`RecurringTransaction`, kinds `msi_purchase` / `installment`, `Transaction::PLAN_LOCKED_KINDS`, `GenerateRecurringTransactionsJob`, `RecurringGeneration`).
- Business logic lives in `app/models/` (concerns and POROs). No `app/services/`.
- Minitest + fixtures only, minimal fixtures (build edge cases inside the test). No RSpec, no FactoryBot. Stubs with `mocha` only if needed.
- No new gems, no new npm packages.
- Hardcoded English, no i18n for new strings. Every user-facing string is copied **exactly** from the copy doc "Kept" tables (ids are cited next to each string in this plan). Never use the word "MSI", "cycle", "Cancel" (except `b3.confirm_secondary`) in new UI.
- Icons: always the `icon` helper (`app/helpers/application_helper.rb:9`), never `lucide_icon`.
- Functional tokens only (`text-primary`, `text-secondary`, `bg-container`, `bg-container-inset`, `bg-surface-inset`, `border-tertiary`, `border-divider`, `bg-inverse`, `bg-destructive`…). No new tokens, no new DS components, no edits to `app/assets/tailwind/*`.
- Orchestrator build defaults (design-state.md, 2026-10-08): red text in the budget-impact block = `text-red-700 theme-dark:text-red-400` (bars stay `bg-destructive`); the "This purchase" bar segment is `bg-destructive` in every month.
- Hotwire-first: native `<details>`/`<dialog>`, Turbo frames/streams, server-side money/date formatting. Stimulus controllers stay small (< 7 targets) with declarative `data-action`, values via `data-*-value`.
- Use `Current.family` / `Current.user` (never `current_family` / `current_user`).
- Schedule (start date, number of payments, installment total) is **not editable** in v1 (D12).
- **Do not run migrations.** None is needed by this plan. If a task ever finds it needs one, stop and ask the user, giving: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails db:migrate` and `docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rails db:migrate`.
- Do not run `rails server`, `touch tmp/restart.txt` or `rails credentials`. Local Ruby is broken: everything runs through Docker.
- Tests (bind-mounted live source):
  `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test <path>`
  (`The "PLAID_*" variable is not set` and `[SKYLIGHT] Unable to start` are expected noise).
- Lint: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop <files> -a` and `docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint <files> -a`.
- Baseline: `test/models test/jobs test/controllers` had exactly **124** pre-existing failing tests (16 failures / 118 errors), mostly `tailwind.css` not built in the bind mount (any test that renders the full application layout errors). Rules for this plan:
  - Prefer model / helper / job tests.
  - A controller test that renders a view sends `headers: { "Turbo-Frame" => "<frame id>" }` (turbo-rails 2.0.16 then uses its `turbo_rails/frame` layout, which does not link `tailwind.css`) or requests a turbo stream (`headers: { "Accept" => "text/vnd.turbo-stream.html" }`). Redirect-only assertions need neither.
  - When an assertion contains an apostrophe, compare against `ERB::Util.html_escape("...")`.
  - Views without an automated test are verified in Task 18's browser checklist.
- Commit messages end with: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Families with no recurring payments must look and behave exactly as today (except the approved future-budget navigation).

## File Map

| File | Responsibility |
|---|---|
| `app/models/family.rb` (modify) | `#today` (family timezone), `#recurring_commitments` |
| `app/jobs/generate_recurring_transactions_job.rb` (modify) | Family date, generatable plans only, one plan failing never stops the rest |
| `app/controllers/concerns/recurring_generation.rb` (modify) | Daily trigger keyed on `family.today` |
| `app/models/category.rb` (modify) | `replace_and_destroy!` moves plans too |
| `app/models/recurring_transaction.rb` (modify) | Copy-exact validations, eligibility guards, `build_from_entry`, schedule lock, `backfill_count`, `ended_on`, `monthly_amount`, `next_payment_date`, `budget_impact` |
| `app/models/family/recurring_commitments.rb` (create) | **The** committed calculation (items in a date range) |
| `app/models/budget.rb` (modify) | Commitments + basis + percent, `for_cycle`, future horizon, committed-as-spending in future months, autofill source |
| `app/models/recurring_transaction/budget_impact.rb` (create) | Capture-time projection for the next 3 installments |
| `app/models/account.rb`, `app/models/account/recurring_commitments.rb` (modify / create) | Credit-card KPIs, tables, Upcoming |
| `app/helpers/custom_confirm.rb`, `app/views/layouts/shared/_confirm_dialog.html.erb`, `app/javascript/controllers/confirm_dialog_controller.js` (modify) | Secondary "Keep it" button with initial focus + plan/purchase/occurrence factories |
| `app/models/transaction.rb`, `app/models/transfer.rb`, `app/controllers/transfer_matches_controller.rb`, `app/views/layouts/shared/_htmldoc.html.erb` (modify) | Locked rows never 500; notification tray is a status region |
| `config/routes.rb` (modify) | `recurring_transactions` (preview/show/update/stop), `transactions/:id/recurrence` |
| `app/controllers/concerns/recurrence_params.rb` (create) | `recurrence[...]` params + success notices |
| `app/controllers/recurring_transactions_controller.rb` (create) | Preview (B2), plan dialog (C3) |
| `app/helpers/recurring_transactions_helper.rb` (create) | Copy-exact labels, summaries, dates |
| `app/views/recurring_transactions/_preview.html.erb`, `_budget_impact.html.erb`, `show.html.erb`, `_commitment_group.html.erb`, `_commitment_row.html.erb` (create) | B2 summary, impact block, C3 dialog, shared commitment list |
| `app/javascript/controllers/recurring_form_controller.js` (create) | Type switching + 500 ms debounced preview |
| `app/views/transactions/_recurrence_fields.html.erb` (create), `_form.html.erb`, `new.html.erb` (modify) | B1 fields |
| `app/controllers/transactions_controller.rb` (modify) | Create entry + plan atomically; index includes plan |
| `app/controllers/transactions/recurrences_controller.rb`, `app/views/transactions/recurrences/*` (create) | B3 convert flow |
| `app/views/transactions/show.html.erb`, `_transaction.html.erb` (modify) | C1 provenance, locked fields, B3 block, delete confirms |
| `app/components/UI/account_page.rb`, `.html.erb` (modify), `app/views/credit_cards/tabs/_recurring.html.erb` (create) | C2 tab |
| `app/views/budgets/_recurring_commitments.html.erb` (create), `budgets/*`, `budget_categories/*` (modify) | C4 block + future months |

---

### Task 1: Family date, resilient generation, category replacement (carry-over)

**Files:**
- Modify: `app/models/family.rb:121-123` (add `#today` after `self_hoster?`)
- Modify: `app/jobs/generate_recurring_transactions_job.rb`
- Modify: `app/controllers/concerns/recurring_generation.rb`
- Modify: `app/models/recurring_transaction.rb:24` (add `generatable` scope), `:109` (default `as_of`)
- Modify: `app/models/category.rb:99-104`
- Test: `test/models/family_test.rb`, `test/jobs/generate_recurring_transactions_job_test.rb`, `test/models/category_test.rb`

**Interfaces:**
- Produces: `Family#today -> Date` (today in the family timezone, falls back to `Time.zone`); `RecurringTransaction.generatable` (active plans on manual, active accounts); `RecurringTransaction#generate_due!(as_of: family.today)`; `Category#replace_and_destroy!` moves `recurring_transactions.category_id`.

- [ ] **Step 1: Write the failing tests**

Append to `test/models/family_test.rb` (inside the class):

```ruby
  test "today follows the family timezone" do
    family = families(:dylan_family)
    family.update!(timezone: "Pacific/Kiritimati")

    travel_to Time.utc(2026, 10, 8, 12) do
      assert_equal Date.new(2026, 10, 9), family.today
    end
  end
```

Replace the body of `test/jobs/generate_recurring_transactions_job_test.rb` with:

```ruby
require "test_helper"

class GenerateRecurringTransactionsJobTest < ActiveJob::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:credit_card)
    @account.entries.delete_all
  end

  test "generates due occurrences for active plans" do
    plan = create_plan(name: "Gym", start_date: Date.current)

    GenerateRecurringTransactionsJob.perform_now(@family)

    assert_equal 1, plan.transactions.count
  end

  test "uses the family's date, not the server's" do
    @family.update!(timezone: "Pacific/Kiritimati")

    travel_to Time.utc(2026, 10, 8, 12) do
      plan = create_plan(name: "Gym", start_date: Date.new(2026, 10, 9))

      GenerateRecurringTransactionsJob.perform_now(@family)

      assert_equal 1, plan.transactions.count
    end
  end

  test "one failing plan does not stop the others" do
    broken = create_plan(name: "Broken", start_date: Date.current)
    broken.update_column(:name, "")
    healthy = create_plan(name: "Gym", start_date: Date.current)

    assert_nothing_raised { GenerateRecurringTransactionsJob.perform_now(@family) }

    assert_equal 0, broken.transactions.count
    assert_equal 1, healthy.transactions.count
  end

  test "skips plans whose account is no longer active" do
    plan = create_plan(name: "Gym", start_date: Date.current)
    @account.update_column(:status, "disabled")

    GenerateRecurringTransactionsJob.perform_now(@family)

    assert_equal 0, plan.transactions.count
  end

  private
    def create_plan(name:, start_date:)
      @family.recurring_transactions.create!(
        account: @account, name: name, plan_type: "charge", amount: 500, currency: "USD", start_date: start_date
      )
    end
end
```

Append to `test/models/category_test.rb` (inside the class):

```ruby
  test "replace_and_destroy! moves recurring plans to the replacement" do
    category = categories(:food_and_drink)
    replacement = families(:dylan_family).categories.create!(name: "Dining", color: "#e99537", lucide_icon: "utensils")
    plan = families(:dylan_family).recurring_transactions.create!(
      account: accounts(:credit_card), name: "Club", plan_type: "charge", amount: 10, currency: "USD",
      start_date: Date.current + 1.day, category: category
    )

    category.replace_and_destroy!(replacement)

    assert_equal replacement, plan.reload.category
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/family_test.rb test/jobs/generate_recurring_transactions_job_test.rb test/models/category_test.rb`
Expected: FAIL — `undefined method 'today'`; "one failing plan" raises `ActiveRecord::RecordInvalid`; "skips plans" gets 1; category test expects `Dining` but gets `nil`.

- [ ] **Step 3: Implement**

`app/models/family.rb` — add after `self_hoster?` (line 121-123):

```ruby
  # Dates users see (generation, "today" in previews) follow the family's timezone, not the server's
  def today
    (Time.find_zone(timezone) || Time.zone).today
  end
```

`app/models/recurring_transaction.rb` — below `scope :active` (line 24):

```ruby
  scope :generatable, -> { active.joins(:account).merge(Account.manual).where(accounts: { status: "active" }) }
```

and change the signature on line 109 to:

```ruby
  def generate_due!(as_of: family.today)
```

`app/jobs/generate_recurring_transactions_job.rb`:

```ruby
class GenerateRecurringTransactionsJob < ApplicationJob
  def perform(family)
    today = family.today

    family.recurring_transactions.generatable.find_each do |plan|
      plan.generate_due!(as_of: today)
    rescue StandardError => e
      # One broken plan must not stop the rest of the family's plans
      Rails.logger.error("Recurring plan #{plan.id} failed to generate: #{e.class}: #{e.message}")
      Sentry.capture_exception(e)
    end
  end
end
```

`app/controllers/concerns/recurring_generation.rb` — replace the private method:

```ruby
    # One date comparison per request; at most one job per family per day
    def generate_recurring_transactions_later
      family = Current.family
      return unless family

      today = family.today
      return if family.recurring_generated_on == today

      family.update_column(:recurring_generated_on, today)
      GenerateRecurringTransactionsJob.perform_later(family) if family.recurring_transactions.generatable.exists?
    end
```

`app/models/category.rb:99-104`:

```ruby
  def replace_and_destroy!(replacement)
    transaction do
      transactions.update_all category_id: replacement&.id
      recurring_transactions.update_all category_id: replacement&.id
      destroy!
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command, then `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/recurring_transaction_test.rb test/controllers/recurring_generation_test.rb`
Expected: all pass (`0 failures, 0 errors`).

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/models/family.rb app/models/recurring_transaction.rb app/jobs/generate_recurring_transactions_job.rb app/controllers/concerns/recurring_generation.rb app/models/category.rb test/models/family_test.rb test/jobs/generate_recurring_transactions_job_test.rb test/models/category_test.rb -a
git add app/models/family.rb app/models/recurring_transaction.rb app/jobs/generate_recurring_transactions_job.rb app/controllers/concerns/recurring_generation.rb app/models/category.rb test/models/family_test.rb test/jobs/generate_recurring_transactions_job_test.rb test/models/category_test.rb
git commit -m "Generate recurring payments on the family's date and isolate failing plans

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Plan validations, eligibility guards and schedule lock

**Files:**
- Modify: `app/models/recurring_transaction.rb` (full replacement below)
- Test: `test/models/recurring_transaction_test.rb`

**Interfaces:**
- Consumes: `Family#today`, `RecurringTransaction.generatable` (Task 1).
- Produces:
  - `RecurringTransaction::MAX_INSTALLMENTS = 48`, `::INELIGIBILITY_MESSAGES` (Hash Symbol → String), `::GENERIC_ERROR = "We couldn't set this up. Nothing changed. Try again."`
  - `RecurringTransaction.ineligibility_reason(entry) -> Symbol | nil` (`:transfer`, `:already_linked`, `:not_standard`, `:income`, `:account_not_manual`)
  - `RecurringTransaction.build_from_entry(entry, plan_type:, total_payments: nil, start_date: nil) -> RecurringTransaction` (unsaved; `start_date` nil = default "purchase + 1 month" for installments; a String is parsed as ISO date, blank/invalid → nil → validation error; charges always start on the entry date)
  - `RecurringTransaction.create_from_entry!(entry, **same)` (raises `ActiveRecord::RecordInvalid`)
  - `#source_entry` (attr_accessor), `#backfill_count(as_of: family.today) -> Integer`, `#ended_on -> Date | nil`, `#monthly_amount -> BigDecimal`
  - Error messages (exact copy): `:total_payments` → `b.err.payments_range_installments` / `b.err.payments_range_charge` / `b.err.amount_too_small`; `:start_date` → `b.err.first_payment_missing` / `b.err.first_payment_before_purchase`; `:account` → `b.err.installments_credit_only` / `b.err.account_not_manual`; `:base` → `b3.err.transfer` / `b3.err.already_linked` / `b3.err.not_standard` / `b.err.expense_only`.

- [ ] **Step 1: Write the failing tests**

Append inside `RecurringTransactionTest` (before `private`):

```ruby
  test "create_from_entry! rejects transactions that can't repeat" do
    linked = create_transaction(account: @credit_card, amount: 100, name: "Netflix")
    RecurringTransaction.create_from_entry!(linked, plan_type: "charge")

    {
      create_transaction(account: @credit_card, amount: 100, kind: "cc_payment") => "Transfers can't repeat.",
      create_transaction(account: @credit_card, amount: 100, kind: "one_time") => "Turn off One-time Expense to set this up.",
      create_transaction(account: @credit_card, amount: -100) => "Only expenses can repeat.",
      linked => "This is already part of a recurring payment."
    }.each do |entry, message|
      error = assert_raises(ActiveRecord::RecordInvalid) do
        RecurringTransaction.create_from_entry!(entry, plan_type: "charge")
      end
      assert_includes error.record.errors[:base], message
    end
  end

  test "plans require a manual, active account" do
    plan = build_plan(plan_type: "charge", total_payments: nil, account: accounts(:connected))

    assert_not plan.valid?
    assert_includes plan.errors[:account], "Only manual accounts can have recurring payments."
  end

  test "validation messages are the interface copy" do
    assert_equal [ "Enter 2 to 48 installments." ], build_plan(total_payments: 49).tap(&:validate).errors[:total_payments]
    assert_equal [ "Too small to split into 6 installments. Use fewer." ],
                 build_plan(amount: BigDecimal("0.05"), total_payments: 6).tap(&:validate).errors[:total_payments]
    assert_includes build_plan(account: accounts(:depository)).tap(&:validate).errors[:account],
                    "Installments only work on credit cards."
    assert_equal [ "Enter a whole number, or leave it empty." ],
                 build_plan(plan_type: "charge", total_payments: "abc").tap(&:validate).errors[:total_payments]
  end

  test "the first payment can't be missing or before the purchase" do
    purchase = create_transaction(account: @credit_card, amount: 1200, date: Date.new(2026, 10, 8))

    early = RecurringTransaction.build_from_entry(purchase, plan_type: "installments", total_payments: 3, start_date: "2026-10-01")
    assert_not early.valid?
    assert_equal [ "The first payment can't be before Oct 8, 2026." ], early.errors[:start_date]

    blank = RecurringTransaction.build_from_entry(purchase, plan_type: "installments", total_payments: 3, start_date: "")
    assert_not blank.valid?
    assert_equal [ "Choose a date for the first payment." ], blank.errors[:start_date]

    default = RecurringTransaction.build_from_entry(purchase, plan_type: "installments", total_payments: 3)
    assert_equal Date.new(2026, 11, 8), default.start_date
  end

  test "the schedule can't change after the plan is created" do
    plan = build_plan
    plan.save!

    assert_not plan.update(total_payments: 6)
    assert plan.reload.update(name: "New laptop")
  end

  test "backfill_count counts past occurrences except a charge's own first payment" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: @credit_card, amount: 3000, date: Date.new(2026, 7, 8))

    installments = RecurringTransaction.build_from_entry(purchase, plan_type: "installments", total_payments: 6)
    charge = RecurringTransaction.build_from_entry(purchase, plan_type: "charge")

    assert_equal 3, installments.backfill_count # Aug 8, Sep 8, Oct 8
    assert_equal 3, charge.backfill_count       # Jul 8 is the purchase itself
  end

  test "ended_on and monthly_amount describe the plan" do
    plan = build_plan(start_date: Date.new(2026, 1, 15))
    plan.save!

    assert_equal BigDecimal("333.33"), plan.monthly_amount
    assert_nil plan.ended_on

    plan.cancel!
    assert_equal plan.updated_at.to_date, plan.ended_on
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/recurring_transaction_test.rb`
Expected: 7 new tests FAIL/ERROR (`undefined method 'build_from_entry'`, Active Record default messages, no eligibility errors).

- [ ] **Step 3: Implement** — replace `app/models/recurring_transaction.rb` with:

```ruby
class RecurringTransaction < ApplicationRecord
  PLAN_TYPES = %w[charge installments].freeze
  STATUSES = %w[active cancelled completed].freeze
  MAX_INSTALLMENTS = 48

  INELIGIBILITY_MESSAGES = {
    transfer: "Transfers can't repeat.",
    already_linked: "This is already part of a recurring payment.",
    not_standard: "Turn off One-time Expense to set this up.",
    income: "Only expenses can repeat.",
    account_not_manual: "Only manual accounts can have recurring payments."
  }.freeze

  GENERIC_ERROR = "We couldn't set this up. Nothing changed. Try again.".freeze

  Occurrence = Data.define(:number, :date, :amount)

  belongs_to :family
  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :merchant, optional: true
  # Runs before the nullify below so installments are removed and the purchase reverted first
  before_destroy :release_transactions
  has_many :transactions, dependent: :nullify
  after_destroy :sync_account_later, unless: :destroyed_by_association

  # The entry a plan is being built from (capture, preview, convert); drives eligibility and first-payment checks
  attr_accessor :source_entry

  validates :name, :currency, presence: true
  validates :start_date, presence: { message: "Choose a date for the first payment." }
  validates :plan_type, inclusion: { in: PLAN_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :amount, numericality: { greater_than: 0 }
  validate :total_payments_in_range
  validate :installment_amount_large_enough
  validate :installments_require_credit_card
  validate :account_manual_and_active, on: :create
  validate :first_payment_not_before_purchase, on: :create
  validate :source_entry_eligible, on: :create
  validate :schedule_unchanged, on: :update

  scope :active, -> { where(status: "active") }
  scope :generatable, -> { active.joins(:account).merge(Account.manual).where(accounts: { status: "active" }) }

  class << self
    # Why an entry can't become (part of) a plan, or nil when it can
    def ineligibility_reason(entry)
      transaction = entry.entryable
      return :not_standard unless transaction.is_a?(Transaction)
      return :transfer if transaction.transfer? || transaction.transfer.present?
      return :already_linked if transaction.recurring_transaction_id.present?
      return :not_standard unless transaction.standard?
      return :income if entry.amount.to_d.negative?
      return :account_not_manual unless entry.account.manual? && entry.account.active?

      nil
    end

    def build_from_entry(entry, plan_type:, total_payments: nil, start_date: nil)
      source = entry.entryable

      new(
        source_entry: entry,
        family: entry.account.family,
        account: entry.account,
        name: entry.name,
        category: source.try(:category),
        merchant: source.try(:merchant),
        plan_type: plan_type,
        amount: entry.amount,
        currency: entry.currency,
        total_payments: total_payments,
        start_date: plan_type == "installments" ? first_payment_date(entry, start_date) : entry.date
      )
    end

    def create_from_entry!(entry, **attributes)
      transaction do
        plan = build_from_entry(entry, **attributes)
        plan.save!

        source = entry.entryable
        if plan.installments?
          source.update!(kind: "msi_purchase", recurring_transaction: plan)
        else
          source.update!(recurring_transaction: plan, installment_number: 1)
        end

        plan.generate_due!
        plan
      end
    end

    private
      # nil means "not provided" (default: one month after the purchase); a blank or invalid string stays nil
      def first_payment_date(entry, start_date)
        return entry.date&.next_month if start_date.nil?
        return start_date unless start_date.is_a?(String)

        Date.iso8601(start_date)
      rescue Date::Error
        nil
      end
  end

  def installments?
    plan_type == "installments"
  end

  def charge?
    plan_type == "charge"
  end

  def occurrence_date(number)
    start_date.advance(months: number - 1)
  end

  # Installment plans store the total; each payment is floored to cents and the last absorbs the remainder
  def occurrence_amount(number)
    return amount unless installments?

    base = (amount / total_payments).floor(2)
    number == total_payments ? amount - base * (total_payments - 1) : base
  end

  def end_date
    total_payments && occurrence_date(total_payments)
  end

  def generated_numbers
    transactions.where.not(installment_number: nil).pluck(:installment_number)
  end

  # Every number up to this one is done (generated, or generated and later deleted).
  # Deleted occurrences are never regenerated, so the gap they leave is permanent.
  def last_handled_number
    [ generated_numbers.max || 0, numbers_generated_through(last_generated_on) ].max
  end

  def remaining_payments
    total_payments && [ total_payments - last_handled_number, 0 ].max
  end

  def remaining_balance
    return BigDecimal("0") unless installments?

    amount - (1..last_handled_number).sum(BigDecimal("0")) { |number| occurrence_amount(number) }
  end

  # What one month of this plan costs: the next installment, or the charge amount
  def monthly_amount
    next_number = last_handled_number + 1
    next_number = total_payments if total_payments && next_number > total_payments
    occurrence_amount(next_number)
  end

  # Occurrences that saving this plan adds with past dates (a charge's first payment is the source transaction)
  def backfill_count(as_of: family.today)
    upcoming(through: as_of).count { |occurrence| installments? || occurrence.number > 1 }
  end

  # The day a finished plan stopped: when it was stopped, or its last payment
  def ended_on
    case status
    when "cancelled" then updated_at.to_date
    when "completed" then end_date
    end
  end

  def upcoming(through:)
    ((last_handled_number + 1)..).lazy
      .map { |number| Occurrence.new(number: number, date: occurrence_date(number), amount: occurrence_amount(number)) }
      .take_while { |occurrence| occurrence.date <= through && (total_payments.nil? || occurrence.number <= total_payments) }
      .to_a
  end

  def cancel!
    update!(status: "cancelled")
  end

  def generate_due!(as_of: family.today)
    return 0 unless status == "active"

    created = upcoming(through: as_of).count { |occurrence| create_occurrence(occurrence) }

    update!(last_generated_on: as_of, status: fully_generated? ? "completed" : status)
    account.sync_later if created.positive?

    created
  end

  private
    def total_payments_in_range
      raw = total_payments_before_type_cast.to_s.strip
      whole = raw.match?(/\A\d+\z/) ? raw.to_i : nil

      if installments?
        unless whole&.between?(2, MAX_INSTALLMENTS)
          errors.add(:total_payments, "Enter 2 to #{MAX_INSTALLMENTS} installments.")
        end
      elsif raw.present? && !(whole && whole >= 1)
        errors.add(:total_payments, "Enter a whole number, or leave it empty.")
      end
    end

    def installment_amount_large_enough
      return unless installments? && amount.present? && total_payments.present?
      return if errors.include?(:total_payments)
      return if (amount / total_payments).floor(2) >= BigDecimal("0.01")

      errors.add(:total_payments, "Too small to split into #{total_payments} installments. Use fewer.")
    end

    def installments_require_credit_card
      return unless installments? && account

      errors.add(:account, "Installments only work on credit cards.") unless account.accountable_type == "CreditCard"
    end

    def account_manual_and_active
      return unless account
      return if account.manual? && account.active?

      errors.add(:account, INELIGIBILITY_MESSAGES[:account_not_manual])
    end

    def first_payment_not_before_purchase
      return unless installments? && start_date && source_entry&.date
      return if start_date >= source_entry.date

      errors.add(:start_date, "The first payment can't be before #{source_entry.date.strftime("%b %-d, %Y")}.")
    end

    def source_entry_eligible
      return unless source_entry

      reason = self.class.ineligibility_reason(source_entry)
      # A manual/active account is reported on :account by account_manual_and_active
      return if reason.nil? || reason == :account_not_manual

      errors.add(:base, INELIGIBILITY_MESSAGES.fetch(reason))
    end

    # D12: the schedule is fixed once created, so last_generated_on never needs a reset
    def schedule_unchanged
      changed_schedule = will_save_change_to_start_date? || will_save_change_to_total_payments? ||
                         will_save_change_to_plan_type? || (installments? && will_save_change_to_amount?)
      errors.add(:base, "The schedule can't be changed. Stop this plan and add a new one.") if changed_schedule
    end

    def create_occurrence(occurrence)
      Entry.transaction(requires_new: true) do
        account.entries.create!(
          name: name,
          date: occurrence.date,
          amount: occurrence.amount,
          currency: currency,
          entryable: Transaction.new(
            kind: installments? ? "installment" : "standard",
            category: category,
            merchant: merchant,
            recurring_transaction: self,
            installment_number: occurrence.number
          )
        )
      end
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end

    def fully_generated?
      total_payments.present? && last_handled_number >= total_payments
    end

    # generate_due! creates every occurrence dated on or before the day it ran, so those numbers are done
    def numbers_generated_through(date)
      return 0 if date.nil?

      number = 0
      number += 1 while occurrence_date(number + 1) <= date && (total_payments.nil? || number < total_payments)
      number
    end

    def release_transactions
      return unless installments?

      installment_ids = transactions.where(kind: "installment").where.not(installment_number: nil).select(:id)
      Entry.where(entryable_type: "Transaction", entryable_id: installment_ids).find_each(&:destroy!)
      transactions.where(kind: "msi_purchase").find_each(&:release_from_plan!)
    end

    def sync_account_later
      account.sync_later
    end
end
```

Notes: `has_many :transactions` on an unsaved plan returns an empty relation without a query, so `backfill_count` works on preview plans. The "schedule can't be changed" string is a defense message (never reached from the UI) and is not in the copy doc.

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/recurring_transaction_test.rb test/models/transaction_test.rb test/jobs`
Expected: all pass, including every Phase A test in the file.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/models/recurring_transaction.rb test/models/recurring_transaction_test.rb -a
git add app/models/recurring_transaction.rb test/models/recurring_transaction_test.rb
git commit -m "Guard recurring plans with copy-exact validations and a locked schedule

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: One shared committed calculation for budgets

**Files:**
- Create: `app/models/family/recurring_commitments.rb`
- Modify: `app/models/family.rb` (add `#recurring_commitments`)
- Modify: `app/models/budget.rb` (class method `for_cycle`, commitments section, `future?`, `past?`, `latest_initialized_budget_before`, monetize list)
- Test (create): `test/models/family/recurring_commitments_test.rb`; Test: `test/models/budget_test.rb`

**Interfaces:**
- Consumes: `RecurringTransaction#upcoming`, `.generatable`, `Transaction::BUDGET_EXCLUDED_KINDS`.
- Produces:
  - `Family::RecurringCommitments.new(family, start_date:, end_date:, accounts: nil, include_generated: true)` with `#items -> Array<Item>` (sorted by date, plan name, number), `#total -> BigDecimal`, `#items_for(category)`, `#total_for(category)` (subcategories roll into the parent; a category with `id == nil` means Uncategorized), `#by_date -> Hash{Date => Array<Item>}`.
  - `Family::RecurringCommitments::Item = Data.define(:plan, :number, :date, :amount, :category, :entry)` with `#generated?`.
  - `Family#recurring_commitments(start_date:, end_date:, **options)`.
  - `Budget.for_cycle(family, date) -> Budget` (persisted if it exists, otherwise unsaved; never added to `family.budgets`).
  - `Budget#recurring_commitments`, `#committed_spending`, `#committed_spending_for(budget_category)`, `#future?`, `#past?`, `#basis_budget`, `#budget_basis`, `#uses_reference_budget?`, `#commitments_over_budget?`, `#commitments_overage`, `#commitments_percent -> Integer | nil` (floor normally, ceil when over), `#latest_initialized_budget_before`, plus `_money` versions of `committed_spending`, `budget_basis`, `commitments_overage`.
  - Rule (interaction §6.1): `committed(C)` = generated plan rows dated in C (kinds not in `BUDGET_EXCLUDED_KINDS`, not excluded, so never the `msi_purchase`) + upcoming occurrences of generatable plans dated in C, whole family, all accounts. `budget_basis(C)` = own `budgeted_spending` when initialized, else (current/future months only) the latest initialized budget before C.

- [ ] **Step 1: Write the failing tests**

Create `test/models/family/recurring_commitments_test.rb`:

```ruby
require "test_helper"

class Family::RecurringCommitmentsTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 10, 8)
    @family = families(:dylan_family)
    @card = accounts(:credit_card)
    @card.entries.delete_all
  end

  test "counts generated rows and upcoming occurrences in the range, never the purchase" do
    purchase = create_transaction(account: @card, amount: 3000, name: "Laptop", date: Date.new(2026, 8, 20))
    RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 3) # Sep 20 generated, Oct 20 upcoming

    commitments = @family.recurring_commitments(start_date: Date.new(2026, 8, 1), end_date: Date.new(2026, 10, 31))

    assert_equal [ 1, 2 ], commitments.items.map(&:number)
    assert_equal [ true, false ], commitments.items.map(&:generated?)
    assert_equal BigDecimal("2000"), commitments.total
  end

  test "rolls subcategory commitments into the parent and keeps uncategorized apart" do
    create_charge(name: "Dinner club", amount: 100, start_date: Date.new(2026, 10, 15), category: categories(:subcategory))
    create_charge(name: "Gym", amount: 50, start_date: Date.new(2026, 10, 16))

    commitments = @family.recurring_commitments(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31))

    assert_equal BigDecimal("100"), commitments.total_for(categories(:food_and_drink))
    assert_equal BigDecimal("100"), commitments.total_for(categories(:subcategory))
    assert_equal BigDecimal("50"), commitments.total_for(@family.categories.uncategorized)
  end

  test "stopped plans add nothing new" do
    create_charge(name: "Gym", amount: 50, start_date: Date.new(2026, 10, 16)).cancel!

    commitments = @family.recurring_commitments(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 12, 31))

    assert_empty commitments.items
  end

  private
    def create_charge(name:, amount:, start_date:, category: nil)
      @family.recurring_transactions.create!(
        account: @card, name: name, plan_type: "charge", amount: amount, currency: "USD", start_date: start_date, category: category
      )
    end
end
```

Append inside `BudgetTest` (`test/models/budget_test.rb`):

```ruby
  test "compares commitments with the latest configured budget when a month has none" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.budgets.destroy_all
    accounts(:credit_card).entries.delete_all
    october = family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                                     currency: "USD", budgeted_spending: 1000, expected_income: 2000)
    family.recurring_transactions.create!(account: accounts(:credit_card), name: "Rent", plan_type: "charge",
                                          amount: 1200, currency: "USD", start_date: Date.new(2026, 10, 5))

    december = Budget.for_cycle(family, Date.new(2026, 12, 1))

    assert december.new_record?
    assert_equal BigDecimal("1200"), december.committed_spending
    assert_equal october, december.basis_budget
    assert december.uses_reference_budget?
    assert december.commitments_over_budget?
    assert_equal BigDecimal("200"), december.commitments_overage
    assert_equal 120, december.commitments_percent
  end

  test "commitments percent rounds down while under budget" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.budgets.destroy_all
    accounts(:credit_card).entries.delete_all
    october = family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                                     currency: "USD", budgeted_spending: 1000, expected_income: 2000)
    family.recurring_transactions.create!(account: accounts(:credit_card), name: "Gym", plan_type: "charge",
                                          amount: BigDecimal("999.50"), currency: "USD", start_date: Date.new(2026, 10, 20))

    assert_not october.commitments_over_budget?
    assert_equal 99, october.commitments_percent
    assert_not october.uses_reference_budget?
  end

  test "past months never borrow another budget" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.budgets.destroy_all
    family.budgets.create!(start_date: Date.new(2026, 8, 1), end_date: Date.new(2026, 8, 31),
                           currency: "USD", budgeted_spending: 1000, expected_income: 2000)

    september = Budget.for_cycle(family, Date.new(2026, 9, 1))

    assert september.past?
    assert_nil september.basis_budget
    assert_nil september.commitments_percent
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/family/recurring_commitments_test.rb test/models/budget_test.rb`
Expected: ERROR — `undefined method 'recurring_commitments'`, `undefined method 'for_cycle'`.

- [ ] **Step 3: Implement**

Create `app/models/family/recurring_commitments.rb`:

```ruby
# What recurring payments commit in a date range: rows the plans already generated plus the
# occurrences active plans will still add. The single source for C4, the capture preview,
# future budget months and the credit card's Upcoming list.
class Family::RecurringCommitments
  Item = Data.define(:plan, :number, :date, :amount, :category, :entry) do
    def generated?
      entry.present?
    end
  end

  attr_reader :family, :start_date, :end_date

  def initialize(family, start_date:, end_date:, accounts: nil, include_generated: true)
    @family = family
    @start_date = start_date
    @end_date = end_date
    @account_ids = accounts&.map(&:id)
    @include_generated = include_generated
  end

  def items
    @items ||= (generated_items + upcoming_items).sort_by { |item| [ item.date, item.plan.name, item.number ] }
  end

  def total
    items.sum(BigDecimal("0"), &:amount)
  end

  # Same roll-up as budget spending: a parent includes its subcategories; a category without id is "Uncategorized"
  def items_for(category)
    items.select do |item|
      if category.id.nil?
        item.category.nil?
      else
        item.category&.id == category.id || item.category&.parent_id == category.id
      end
    end
  end

  def total_for(category)
    items_for(category).sum(BigDecimal("0"), &:amount)
  end

  def by_date
    items.group_by(&:date)
  end

  private
    attr_reader :account_ids

    def plan_scope
      scope = family.recurring_transactions
      account_ids ? scope.where(account_id: account_ids) : scope
    end

    def generated_items
      return [] unless @include_generated

      Transaction.joins(:entry)
        .includes(:category, :entry, recurring_transaction: :account)
        .where(recurring_transaction_id: plan_scope.select(:id))
        .where.not(installment_number: nil)
        .where.not(kind: Transaction::BUDGET_EXCLUDED_KINDS)
        .where(entries: { date: start_date..end_date, excluded: false })
        .map do |transaction|
          Item.new(
            plan: transaction.recurring_transaction,
            number: transaction.installment_number,
            date: transaction.entry.date,
            amount: transaction.entry.amount,
            category: transaction.category,
            entry: transaction.entry
          )
        end
    end

    def upcoming_items
      plan_scope.generatable.includes(:category, :account).flat_map do |plan|
        plan.upcoming(through: end_date).filter_map do |occurrence|
          next if occurrence.date < start_date

          Item.new(plan: plan, number: occurrence.number, date: occurrence.date,
                   amount: occurrence.amount, category: plan.category, entry: nil)
        end
      end
    end
end
```

`app/models/family.rb` — add after `#today`:

```ruby
  def recurring_commitments(start_date:, end_date:, **options)
    RecurringCommitments.new(self, start_date: start_date, end_date: end_date, **options)
  end
```

`app/models/budget.rb`:

1. Extend the monetize list (line 13-15):

```ruby
  monetize :budgeted_spending, :expected_income, :allocated_spending,
           :actual_spending, :available_to_spend, :available_to_allocate,
           :estimated_spending, :estimated_income, :actual_income, :remaining_expected_income,
           :committed_spending, :budget_basis, :commitments_overage
```

2. Inside `class << self`, after `find_or_bootstrap`:

```ruby
    # The month's budget if it was ever created, otherwise an unsaved one (never bootstraps or saves)
    def for_cycle(family, date)
      start_date, end_date = family.cycle_range_containing(date)

      family.budgets.find_by(start_date: start_date, end_date: end_date) ||
        Budget.new(family_id: family.id, start_date: start_date, end_date: end_date, currency: family.currency)
    end
```

3. After `current?` (line 135-137):

```ruby
  def future?
    start_date > Date.current
  end

  def past?
    end_date < Date.current
  end

  # The latest month before this one that has a spending budget set up
  def latest_initialized_budget_before
    family.budgets.where("end_date < ?", start_date).where.not(budgeted_spending: nil).order(end_date: :desc).first
  end
```

4. New section before `private`:

```ruby
  # =============================================================================
  # Recurring commitments: what recurring payments already take from this month
  # =============================================================================
  def recurring_commitments
    @recurring_commitments ||= family.recurring_commitments(start_date: start_date, end_date: end_date)
  end

  def committed_spending
    recurring_commitments.total
  end

  def committed_spending_for(budget_category)
    recurring_commitments.total_for(budget_category.category)
  end

  # The budget commitments are compared with: this one once set up, otherwise (current and
  # future months only) the latest set-up budget before it
  def basis_budget
    return self if initialized?
    return nil if past?

    latest_initialized_budget_before
  end

  def budget_basis
    basis_budget&.budgeted_spending
  end

  def uses_reference_budget?
    basis_budget.present? && basis_budget != self
  end

  def commitments_over_budget?
    budget_basis.present? && budget_basis.positive? && committed_spending > budget_basis
  end

  def commitments_overage
    commitments_over_budget? ? committed_spending - budget_basis : 0
  end

  # Whole percent of the basis; rounded up once over so it never reads "100%" while over budget
  def commitments_percent
    return nil unless budget_basis&.positive?

    ratio = committed_spending / budget_basis * 100
    commitments_over_budget? ? ratio.ceil : ratio.floor
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: all pass. Note the existing budget tests use `families(:empty)`; the new ones destroy `dylan_family` budgets first because fixture `budgets(:one)` covers the real current month.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/models/family/recurring_commitments.rb app/models/family.rb app/models/budget.rb test/models/family/recurring_commitments_test.rb test/models/budget_test.rb -a
git add app/models/family/recurring_commitments.rb app/models/family.rb app/models/budget.rb test/models/family/recurring_commitments_test.rb test/models/budget_test.rb
git commit -m "Compute recurring commitments per budget month in one place

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Future budgets in the model (12 months ahead)

**Files:**
- Modify: `app/models/budget.rb` (`FUTURE_CYCLES_LIMIT`, `budget_date_valid?`, `latest_valid_budget_end_date`, `next_budget_param`, `actual_spending`, `budget_category_actual_spending`, `previous_budget`)
- Test: `test/models/budget_test.rb` (replace the test at lines 61-63)

**Interfaces:**
- Consumes: `Budget#future?`, `#committed_spending`, `#committed_spending_for`, `#latest_initialized_budget_before` (Task 3).
- Produces: `Budget::FUTURE_CYCLES_LIMIT = 12`; `Budget.latest_valid_budget_end_date(family) -> Date`; `budget_date_valid?` accepts months up to current + 12; `next_budget_param` works from the current month; **single decision point**: `Budget#actual_spending` and `#budget_category_actual_spending` return committed amounts when `future?` (so `available_to_spend`, donut segments, `BudgetCategory#actual_spending/available_to_spend` all follow); `previous_budget` returns `latest_initialized_budget_before` for future months (autofill source).

- [ ] **Step 1: Write the failing tests**

In `test/models/budget_test.rb` replace the test `"budget_date_valid? does not allow future dates beyond current month"` (lines 61-63) with:

```ruby
  test "budget_date_valid? allows planning up to 12 months ahead" do
    travel_to Date.new(2026, 10, 8)

    assert Budget.budget_date_valid?(Date.new(2027, 10, 1), family: @family)
    refute Budget.budget_date_valid?(Date.new(2027, 11, 1), family: @family)
  end

  test "the planning horizon follows custom month windows" do
    travel_to Date.new(2026, 10, 8)
    @family.update!(cycle_end_day: 27) # current month: Sep 28 - Oct 27

    assert Budget.budget_date_valid?(Date.new(2027, 10, 1), family: @family)  # Sep 28 - Oct 27, 2027
    refute Budget.budget_date_valid?(Date.new(2027, 11, 1), family: @family)  # Oct 28 - Nov 27, 2027
  end
```

Append:

```ruby
  test "next_budget_param moves past the current month until the horizon" do
    travel_to Date.new(2026, 10, 8)
    current = Budget.create!(family: @family, start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31), currency: "USD")
    last = Budget.create!(family: @family, start_date: Date.new(2027, 10, 1), end_date: Date.new(2027, 10, 31), currency: "USD")

    assert_equal "nov-2026", current.next_budget_param
    assert_nil last.next_budget_param
  end

  test "future months show committed amounts where spending would be" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.budgets.destroy_all
    accounts(:credit_card).entries.delete_all
    family.recurring_transactions.create!(account: accounts(:credit_card), name: "Club", plan_type: "charge",
                                          amount: 300, currency: "USD", start_date: Date.new(2026, 10, 15),
                                          category: categories(:food_and_drink))

    december = Budget.find_or_bootstrap(family, start_date: Date.new(2026, 12, 1))
    food = december.budget_categories.find { |bc| bc.category == categories(:food_and_drink) }

    assert december.future?
    assert_equal BigDecimal("300"), december.actual_spending
    assert_equal BigDecimal("300"), food.actual_spending
  end

  test "previous_budget of a future month is the latest configured one" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.budgets.destroy_all
    october = family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                                     currency: "USD", budgeted_spending: 1000, expected_income: 2000)
    family.budgets.create!(start_date: Date.new(2026, 11, 1), end_date: Date.new(2026, 11, 30), currency: "USD")
    december = family.budgets.create!(start_date: Date.new(2026, 12, 1), end_date: Date.new(2026, 12, 31), currency: "USD")

    assert_equal october, december.previous_budget
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/budget_test.rb`
Expected: FAIL — future dates rejected, `next_budget_param` nil for current, actual spending 0, previous_budget nil.

- [ ] **Step 3: Implement** in `app/models/budget.rb`

Below `PARAM_DATE_FORMAT`:

```ruby
  FUTURE_CYCLES_LIMIT = 12
```

Replace `budget_date_valid?` (lines 32-37) and add the horizon helper right after it:

```ruby
    def budget_date_valid?(date, family:)
      start_date, end_date = family.cycle_range_containing(date)

      start_date >= oldest_valid_budget_date(family) && end_date <= latest_valid_budget_end_date(family)
    end

    # End of the furthest month that can be planned: the current one plus FUTURE_CYCLES_LIMIT
    def latest_valid_budget_end_date(family)
      cycle_end = family.cycle_range_containing(Date.current).last
      FUTURE_CYCLES_LIMIT.times { cycle_end = family.cycle_range_containing(cycle_end + 1.day).last }
      cycle_end
    end
```

Replace `previous_budget` (lines 146-152):

```ruby
  # The budget to copy from. For a future month it's the latest one set up (the months in
  # between are usually empty); otherwise the prior month's record, if any (never bootstraps one)
  def previous_budget
    return latest_initialized_budget_before if future?
    return nil unless previous_budget_param

    prev_start, prev_end = family.cycle_range_containing(end_date.prev_month.beginning_of_month)
    family.budgets.find_by(start_date: prev_start, end_date: prev_end)
  end
```

Replace `next_budget_param` (lines 167-174):

```ruby
  def next_budget_param
    next_month_date = end_date.next_month.beginning_of_month
    return nil unless self.class.budget_date_valid?(next_month_date, family: family)

    self.class.date_to_param(next_month_date)
  end
```

Replace `actual_spending` and `budget_category_actual_spending` (lines 200-206):

```ruby
  # Future months have no real spending yet: what recurring payments commit takes its place
  # everywhere spending is shown (donut, summary, category rows). This is the only switch.
  def actual_spending
    future? ? committed_spending : expense_totals.total
  end

  def budget_category_actual_spending(budget_category)
    return committed_spending_for(budget_category) if future?

    expense_totals.category_totals.find { |ct| ct.category.id == budget_category.category.id }&.total || 0
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/budget_test.rb test/models/budget_category_test.rb test/models/family/recurring_commitments_test.rb`
Expected: all pass (if `test/models/budget_category_test.rb` doesn't exist, drop it from the command).

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/models/budget.rb test/models/budget_test.rb -a
git add app/models/budget.rb test/models/budget_test.rb
git commit -m "Allow budgets up to 12 months ahead, showing committed amounts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Budget impact of a new installment purchase (with parity test)

**Files:**
- Create: `app/models/recurring_transaction/budget_impact.rb`
- Modify: `app/models/recurring_transaction.rb` (add `#budget_impact` after `#ended_on`)
- Test (create): `test/models/recurring_transaction/budget_impact_test.rb`

**Interfaces:**
- Consumes: `Budget.for_cycle`, `Budget#committed_spending`, `#basis_budget`, `Family#today`.
- Produces: `RecurringTransaction#budget_impact -> RecurringTransaction::BudgetImpact`; `BudgetImpact#months -> Array<Month>`, `#available?`, `#over_months`, `#installments_count`, `#scale`, `#width(amount) -> Float`, `#reference_budget -> Budget | nil`; `BudgetImpact::Month = Data.define(:budget, :committed, :purchase, :basis_budget)` with `#basis`, `#total`, `#over?`, `#overage`, `#percent`, `#reference?`.
- Rule (§2.4b): the months containing the next ≤ 3 installments whose month hasn't ended (by `family.today`), `total(C) = budget.committed_spending + this plan's installments in C`, basis = `budget.basis_budget`; months without a basis are left out; `scale = max(basis × 1.2, totals)`.

- [ ] **Step 1: Write the failing tests**

Create `test/models/recurring_transaction/budget_impact_test.rb`:

```ruby
require "test_helper"

class RecurringTransaction::BudgetImpactTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 10, 8)
    @family = families(:dylan_family)
    @family.budgets.destroy_all
    @card = accounts(:credit_card)
    @card.entries.delete_all
    @family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                            currency: "USD", budgeted_spending: 1500, expected_income: 4000)
    @family.recurring_transactions.create!(account: @card, name: "Rent", plan_type: "charge",
                                           amount: 1000, currency: "USD", start_date: Date.new(2026, 10, 20))
  end

  test "projects the next three installments over the reference budget" do
    purchase = create_transaction(account: @card, amount: 3000, name: "iPad", date: Date.new(2026, 10, 8))
    impact = RecurringTransaction.build_from_entry(purchase, plan_type: "installments", total_payments: 6).budget_impact

    assert_equal [ "November 2026", "December 2026", "January 2027" ], impact.months.map { |m| m.budget.name }
    assert impact.months.all?(&:reference?)
    assert_equal [ BigDecimal("1500") ] * 3, impact.months.map(&:total)
    assert_equal [ 100 ] * 3, impact.months.map(&:percent)
    assert_empty impact.over_months
    assert_equal 1800, impact.scale
  end

  test "flags the months a purchase puts over budget" do
    purchase = create_transaction(account: @card, amount: 1200, name: "TV", date: Date.new(2026, 10, 8))
    impact = RecurringTransaction.build_from_entry(purchase, plan_type: "installments", total_payments: 2).budget_impact

    assert_equal 2, impact.installments_count
    assert_equal [ BigDecimal("100") ] * 2, impact.over_months.map(&:overage)
    assert_equal [ 107 ] * 2, impact.months.map(&:percent)
  end

  test "skips installments in months that already ended" do
    purchase = create_transaction(account: @card, amount: 600, name: "Chair", date: Date.new(2026, 7, 2))
    impact = RecurringTransaction.build_from_entry(purchase, plan_type: "installments", total_payments: 6).budget_impact

    assert_equal "October 2026", impact.months.first.budget.name # Aug and Sep are over
  end

  test "nothing to show without any configured budget" do
    @family.budgets.destroy_all
    purchase = create_transaction(account: @card, amount: 600, name: "Chair", date: Date.new(2026, 10, 8))

    assert_not RecurringTransaction.build_from_entry(purchase, plan_type: "installments", total_payments: 3).budget_impact.available?
  end

  test "the preview total equals the committed amount once the plan is saved" do
    purchase = create_transaction(account: @card, amount: 3000, name: "iPad", date: Date.new(2026, 10, 8))
    preview = RecurringTransaction.build_from_entry(purchase, plan_type: "installments", total_payments: 3).budget_impact
    expected = preview.months.to_h { |month| [ month.budget.start_date, month.total ] }

    RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 3)

    expected.each do |start_date, total|
      assert_equal total, Budget.for_cycle(@family, start_date).committed_spending
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/recurring_transaction/budget_impact_test.rb`
Expected: ERROR — `undefined method 'budget_impact'`.

- [ ] **Step 3: Implement**

Create `app/models/recurring_transaction/budget_impact.rb`:

```ruby
# Capture-time projection: how the next installments of a (usually unsaved) plan land on
# the budget months they fall in, using the same committed/basis numbers as the budget screen.
class RecurringTransaction::BudgetImpact
  MAX_INSTALLMENTS = 3

  Month = Data.define(:budget, :committed, :purchase, :basis_budget) do
    def basis
      basis_budget.budgeted_spending
    end

    def total
      committed + purchase
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
  end

  attr_reader :plan

  def initialize(plan)
    @plan = plan
  end

  # The next installments still to come (their month hasn't ended), at most three
  def occurrences
    @occurrences ||= begin
      return [] unless plan.installments? && plan.total_payments && plan.start_date

      (1..plan.total_payments).lazy
        .map { |n| RecurringTransaction::Occurrence.new(number: n, date: plan.occurrence_date(n), amount: plan.occurrence_amount(n)) }
        .reject { |occurrence| family.cycle_range_containing(occurrence.date).last < family.today }
        .first(MAX_INSTALLMENTS)
    end
  end

  def installments_count
    occurrences.size
  end

  def months
    @months ||= occurrences.group_by { |occurrence| family.cycle_range_containing(occurrence.date).first }.filter_map do |start_date, group|
      budget = Budget.for_cycle(family, start_date)
      basis_budget = budget.basis_budget
      next unless basis_budget&.budgeted_spending&.positive?

      Month.new(budget: budget, committed: budget.committed_spending,
                purchase: group.sum(BigDecimal("0"), &:amount), basis_budget: basis_budget)
    end
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
end
```

`app/models/recurring_transaction.rb` — add after `#ended_on`:

```ruby
  def budget_impact
    BudgetImpact.new(self)
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command plus `test/models/recurring_transaction_test.rb`. Expected: all pass.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/models/recurring_transaction/budget_impact.rb app/models/recurring_transaction.rb test/models/recurring_transaction/budget_impact_test.rb -a
git add app/models/recurring_transaction/budget_impact.rb app/models/recurring_transaction.rb test/models/recurring_transaction/budget_impact_test.rb
git commit -m "Project an installment purchase onto upcoming budget months

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Credit-card commitments summary (with parity test)

**Files:**
- Create: `app/models/account/recurring_commitments.rb`
- Modify: `app/models/account.rb` (add `#recurring_commitments` near the other public instance methods)
- Modify: `app/models/recurring_transaction.rb` (add `#next_payment_date` after `#monthly_amount`)
- Test (create): `test/models/account/recurring_commitments_test.rb`

**Interfaces:**
- Consumes: `Family#recurring_commitments`, `Family#today`, `RecurringTransaction#monthly_amount`, `#remaining_balance`, `#end_date`, `#ended_on`.
- Produces: `Account#recurring_commitments -> Account::RecurringCommitments` with `#plans`, `#any?`, `#active_installment_plans` (by end date), `#active_charge_plans`, `#past_plans` (most recently ended first), `#committed_per_month`, `#left_on_installments`, `#last_installment_date`, `#upcoming -> Family::RecurringCommitments` (current month + 2 next, not-yet-generated only), `#later_months_budget_param -> String`; `RecurringTransaction#next_payment_date -> Date | nil`.

- [ ] **Step 1: Write the failing tests**

Create `test/models/account/recurring_commitments_test.rb`:

```ruby
require "test_helper"

class Account::RecurringCommitmentsTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 10, 8)
    @family = families(:dylan_family)
    @family.budgets.destroy_all
    @card = accounts(:credit_card)
    @card.entries.delete_all
    purchase = create_transaction(account: @card, amount: 6000, name: "Sofa", date: Date.new(2026, 9, 15))
    @sofa = RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 6) # Oct 15 .. Mar 15
    @netflix = @family.recurring_transactions.create!(account: @card, name: "Netflix", plan_type: "charge",
                                                      amount: 299, currency: "USD", start_date: Date.new(2026, 10, 12))
  end

  test "summarizes what the card commits" do
    commitments = @card.recurring_commitments

    assert_equal BigDecimal("1299"), commitments.committed_per_month
    assert_equal BigDecimal("6000"), commitments.left_on_installments
    assert_equal Date.new(2027, 3, 15), commitments.last_installment_date
    assert_equal Date.new(2026, 10, 12), @netflix.next_payment_date
    assert_equal "jan-2027", commitments.later_months_budget_param
  end

  test "upcoming covers this month and the next two" do
    dates = @card.recurring_commitments.upcoming.items.map(&:date)

    assert_equal Date.new(2026, 10, 12), dates.first
    assert_equal Date.new(2026, 12, 15), dates.last
  end

  test "a future month's committed amount equals the card's upcoming list in it" do
    november = Budget.for_cycle(@family, Date.new(2026, 11, 1))
    card_items = @card.recurring_commitments.upcoming.items.select { |item| item.date.between?(november.start_date, november.end_date) }

    assert_equal november.committed_spending, card_items.sum(&:amount)
  end

  test "finished plans are past plans" do
    @netflix.cancel!

    commitments = @card.recurring_commitments

    assert_equal [ @netflix ], commitments.past_plans
    assert_equal [ @sofa ], commitments.active_installment_plans
    assert_empty commitments.active_charge_plans
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models/account/recurring_commitments_test.rb`
Expected: ERROR — `undefined method 'recurring_commitments'`.

- [ ] **Step 3: Implement**

Create `app/models/account/recurring_commitments.rb`:

```ruby
# Recurring payments on one account (the credit card's "Recurring payments" tab)
class Account::RecurringCommitments
  UPCOMING_MONTHS = 3

  attr_reader :account

  def initialize(account)
    @account = account
  end

  def plans
    @plans ||= account.recurring_transactions.includes(:category).order(:name).to_a
  end

  def any?
    plans.any?
  end

  def active_installment_plans
    plans.select { |plan| plan.status == "active" && plan.installments? }.sort_by(&:end_date)
  end

  def active_charge_plans
    plans.select { |plan| plan.status == "active" && plan.charge? }
  end

  def past_plans
    plans.reject { |plan| plan.status == "active" }.sort_by { |plan| plan.ended_on || Date.new(1970) }.reverse
  end

  def committed_per_month
    (active_installment_plans + active_charge_plans).sum(BigDecimal("0"), &:monthly_amount)
  end

  def left_on_installments
    active_installment_plans.sum(BigDecimal("0"), &:remaining_balance)
  end

  def last_installment_date
    active_installment_plans.filter_map(&:end_date).max
  end

  # Not-yet-generated payments from the start of this month through the end of the second next one
  def upcoming
    @upcoming ||= family.recurring_commitments(
      start_date: family.cycle_range_containing(family.today).first,
      end_date: upcoming_end_date,
      accounts: [ account ],
      include_generated: false
    )
  end

  # Budget param of the first month after Upcoming ("See later months")
  def later_months_budget_param
    Budget.date_to_param(family.cycle_range_containing(upcoming_end_date + 1.day).last)
  end

  private
    def family
      account.family
    end

    def upcoming_end_date
      cycle_end = family.cycle_range_containing(family.today).last
      (UPCOMING_MONTHS - 1).times { cycle_end = family.cycle_range_containing(cycle_end + 1.day).last }
      cycle_end
    end
end
```

`app/models/account.rb` — add a public method (e.g. right after the `class << self ... end` block):

```ruby
  def recurring_commitments
    RecurringCommitments.new(self)
  end
```

`app/models/recurring_transaction.rb` — after `#monthly_amount`:

```ruby
  def next_payment_date
    next_number = last_handled_number + 1
    return nil if total_payments && next_number > total_payments

    occurrence_date(next_number)
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: 4 runs, 0 failures.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/models/account/recurring_commitments.rb app/models/account.rb app/models/recurring_transaction.rb test/models/account/recurring_commitments_test.rb -a
git add app/models/account/recurring_commitments.rb app/models/account.rb app/models/recurring_transaction.rb test/models/account/recurring_commitments_test.rb
git commit -m "Summarize a card's recurring payments and upcoming months

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 7: Confirm dialog with a safe "Keep it" button (C3 confirms)

**Files:**
- Modify: `app/helpers/custom_confirm.rb`
- Modify: `app/views/layouts/shared/_confirm_dialog.html.erb`
- Modify: `app/javascript/controllers/confirm_dialog_controller.js`
- Test (create): `test/helpers/custom_confirm_test.rb`

**Interfaces:**
- Consumes: `RecurringTransaction#remaining_payments`, `#remaining_balance`, `#last_handled_number`, `Budget.for_cycle`.
- Produces: `CustomConfirm.new(..., cancel_text: nil)`; `to_data_attribute` adds `cancelText` when present; factories `CustomConfirm.for_plan_stop(plan)`, `.for_plan_edit(plan)`, `.for_msi_purchase_deletion(entry)`, `.for_occurrence_deletion(entry)`. When `cancelText` is present the dialog shows a secondary outline button with that text and **focuses it** after opening (D7); without it the dialog behaves exactly as today.
- Copy: `c3.confirm_stop_*`, `c3.confirm_edit_*`, `c3.delete_msi_*`, `c3.delete_occurrence_*`. The body goes into `innerHTML`, so bodies never include user-entered names (titles use `textContent`).

- [ ] **Step 1: Write the failing test** — create `test/helpers/custom_confirm_test.rb`:

```ruby
require "test_helper"

class CustomConfirmTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 10, 8)
    @card = accounts(:credit_card)
    @card.entries.delete_all
    purchase = create_transaction(account: @card, amount: 1200, name: "MacBook Air", date: Date.new(2026, 7, 20))
    @plan = RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 12) # 2 added
    @purchase = purchase
  end

  test "stop confirm keeps the safe choice" do
    data = CustomConfirm.for_plan_stop(@plan).to_data_attribute

    assert_equal "Stop MacBook Air?", data[:title]
    assert_equal "The 10 installments left ($1,000.00) won't count in future budgets. The full purchase stays on your card balance.", data[:body]
    assert_equal "Stop payments", data[:confirmText]
    assert_equal "Keep it", data[:cancelText]
    assert_equal "outline-destructive", data[:variant]
  end

  test "deleting an installment purchase is high severity" do
    data = CustomConfirm.for_msi_purchase_deletion(@purchase).to_data_attribute

    assert_equal "Delete this purchase and its installments?", data[:title]
    assert_equal "All 12 installments will be deleted, including the 2 already added. Your card balance and past budgets will change. This can't be undone.", data[:body]
    assert_equal "Delete", data[:confirmText]
    assert_equal "destructive", data[:variant]
  end

  test "deleting one installment names its budget month" do
    installment = @plan.transactions.find_by(installment_number: 1).entry
    data = CustomConfirm.for_occurrence_deletion(installment).to_data_attribute

    assert_equal "Delete this installment?", data[:title]
    assert_equal "It won't be added again. Your August 2026 budget will change.", data[:body]
    assert_equal "Delete installment", data[:confirmText]
    assert_equal "Keep it", data[:cancelText]
  end

  test "editing a plan with payments asks first" do
    data = CustomConfirm.for_plan_edit(@plan).to_data_attribute

    assert_equal "Save changes to future payments?", data[:title]
    assert_equal "The 2 payments already added won't change.", data[:body]
    assert_equal "Keep editing", data[:cancelText]
    assert_equal "primary", data[:variant]
  end

  test "existing confirms have no secondary button" do
    assert_not CustomConfirm.for_resource_deletion("transaction").to_data_attribute.key?(:cancelText)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/helpers/custom_confirm_test.rb`
Expected: ERROR — `undefined method 'for_plan_stop'`.

- [ ] **Step 3: Implement**

Replace `app/helpers/custom_confirm.rb` with:

```ruby
# The shape of data expected by `confirm_dialog_controller.js` to override the
# default browser confirm API via Turbo.
class CustomConfirm
  class << self
    def for_resource_deletion(resource_name, high_severity: false)
      new(
        destructive: true,
        high_severity: high_severity,
        title: "Delete #{resource_name.titleize}?",
        body: "Are you sure you want to delete #{resource_name.downcase}? This is not reversible.",
        btn_text: "Delete #{resource_name.titleize}"
      )
    end

    def for_plan_stop(plan)
      body = if plan.installments?
        left = plan.remaining_payments
        "The #{left} #{"installment".pluralize(left)} left (#{money(plan.remaining_balance, plan.currency)}) " \
          "won't count in future budgets. The full purchase stays on your card balance."
      else
        added = plan.last_handled_number
        "No new payments will be added. The #{added} already added #{added == 1 ? "stays" : "stay"}."
      end

      new(title: "Stop #{plan.name}?", body: body, btn_text: "Stop payments", destructive: true, cancel_text: "Keep it")
    end

    def for_plan_edit(plan)
      added = plan.last_handled_number

      new(
        title: "Save changes to future payments?",
        body: "The #{added} #{"payment".pluralize(added)} already added won't change.",
        btn_text: "Save changes",
        cancel_text: "Keep editing"
      )
    end

    def for_msi_purchase_deletion(entry)
      plan = entry.transaction.recurring_transaction
      added = plan.transactions.where(kind: "installment").count

      new(
        title: "Delete this purchase and its installments?",
        body: "All #{plan.total_payments} installments will be deleted, including the #{added} already added. " \
              "Your card balance and past budgets will change. This can't be undone.",
        btn_text: "Delete",
        destructive: true,
        high_severity: true,
        cancel_text: "Keep it"
      )
    end

    def for_occurrence_deletion(entry)
      noun = entry.transaction.installment? ? "installment" : "payment"
      month = Budget.for_cycle(entry.account.family, entry.date).name

      new(
        title: "Delete this #{noun}?",
        body: "It won't be added again. Your #{month} budget will change.",
        btn_text: "Delete #{noun}",
        destructive: true,
        cancel_text: "Keep it"
      )
    end

    private
      def money(amount, currency)
        Money.new(amount, currency).format
      end
  end

  def initialize(title: default_title, body: default_body, btn_text: default_btn_text, destructive: false, high_severity: false, cancel_text: nil)
    @title = title
    @body = body
    @btn_text = btn_text
    @btn_variant = derive_btn_variant(destructive, high_severity)
    @cancel_text = cancel_text
  end

  def to_data_attribute
    {
      title: title,
      body: body,
      confirmText: btn_text,
      variant: btn_variant,
      cancelText: cancel_text
    }.compact
  end

  private
    attr_reader :title, :body, :btn_text, :btn_variant, :cancel_text

    def derive_btn_variant(destructive, high_severity)
      return "primary" unless destructive
      high_severity ? "destructive" : "outline-destructive"
    end

    def default_title
      "Are you sure?"
    end

    def default_body
      "This is not reversible."
    end

    def default_btn_text
      "Confirm"
    end
end
```

Replace `app/views/layouts/shared/_confirm_dialog.html.erb` with:

```erb
<%# This dialog is used as an override to the browser's confirm API when submitting forms with data-turbo-confirm %>
<%# See confirm_dialog_controller.js and _htmldoc.html.erb  %>
<%= render DS::Dialog.new(id: "confirm-dialog", auto_open: false, data: { controller: "confirm-dialog" }, aria: { describedby: "confirm-dialog-body" }, width: "sm", disable_frame: true) do |dialog| %>
  <% dialog.with_body do %>
    <form method="dialog" class="space-y-4">
      <div class="space-y-2">
        <div class="flex items-center justify-between gap-2">
          <h3 class="font-medium text-primary" data-confirm-dialog-target="title">Are you sure?</h3>
          <%= icon("x", as_button: true, type: "submit", value: "cancel") %>
        </div>

        <p id="confirm-dialog-body" class="text-sm text-secondary" data-confirm-dialog-target="subtitle">This action cannot be undone.</p>
      </div>

      <div class="flex flex-col gap-2">
        <% ["primary", "outline-destructive", "destructive"].each do |variant| %>
          <%= render DS::Button.new(
          text: "Confirm",
          variant: variant,
          autofocus: true,
          full_width: true,
          value: "confirm",
          data: { variant: variant, confirm_dialog_target: "confirmButton" },
          hidden: true,
        ) %>
        <% end %>

        <%= render DS::Button.new(
          text: "Cancel",
          variant: "outline",
          full_width: true,
          value: "cancel",
          data: { confirm_dialog_target: "cancelButton" },
          hidden: true,
        ) %>
      </div>
    </form>
  <% end %>
<% end %>
```

Replace `app/javascript/controllers/confirm_dialog_controller.js` with:

```js
import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="confirm-dialog"
// See javascript/controllers/application.js for how this is wired up
export default class extends Controller {
  static targets = ["title", "subtitle", "confirmButton", "cancelButton"];

  handleConfirm(rawData) {
    const data = this.#normalizeRawData(rawData);

    this.#prepareDialog(data);

    this.element.showModal();

    // With a secondary button, the safe choice gets the initial focus (destructive confirms)
    if (data.cancelText) this.cancelButtonTarget.focus();

    return new Promise((resolve) => {
      this.element.addEventListener(
        "close",
        () => {
          const isConfirmed = this.element.returnValue === "confirm";
          resolve(isConfirmed);
        },
        { once: true },
      );
    });
  }

  #prepareDialog(data) {
    const variant = data.variant || "primary";

    this.confirmButtonTargets.forEach((button) => {
      if (button.dataset.variant === variant) {
        button.removeAttribute("hidden");
      } else {
        button.setAttribute("hidden", true);
      }

      button.textContent = data.confirmText || "Confirm";
    });

    if (data.cancelText) {
      this.cancelButtonTarget.textContent = data.cancelText;
      this.cancelButtonTarget.removeAttribute("hidden");
    } else {
      this.cancelButtonTarget.setAttribute("hidden", true);
    }

    this.titleTarget.textContent = data.title || "Are you sure?";
    this.subtitleTarget.innerHTML =
      data.body || "This action cannot be undone.";
  }

  // If data is a string, it's the title.  Otherwise, return the parsed object.
  #normalizeRawData(rawData) {
    try {
      const parsed = JSON.parse(rawData);

      if (typeof parsed === "boolean") {
        return { title: "Are you sure?" };
      }

      return parsed;
    } catch (e) {
      return { title: rawData };
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: 5 runs, 0 failures. `DS::Dialog` passes `aria:` through `merged_opts` to the `<dialog>` tag (see `app/components/DS/dialog.rb:98-110`).

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/helpers/custom_confirm.rb test/helpers/custom_confirm_test.rb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/layouts/shared/_confirm_dialog.html.erb -a
git add app/helpers/custom_confirm.rb app/views/layouts/shared/_confirm_dialog.html.erb app/javascript/controllers/confirm_dialog_controller.js test/helpers/custom_confirm_test.rb
git commit -m "Give destructive confirms a focused Keep it button

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Locked rows never 500 (carry-over)

**Files:**
- Modify: `app/models/transaction.rb:61` (message)
- Modify: `app/models/transfer.rb:135` (message)
- Modify: `app/controllers/transfer_matches_controller.rb:9-20`
- Modify: `app/views/transactions/show.html.erb:101` (alert at top of Settings)
- Modify: `app/views/layouts/shared/_htmldoc.html.erb:22`
- Test: `test/controllers/transfer_matches_controller_test.rb`, `test/controllers/transactions_controller_test.rb`

**Interfaces:**
- Produces: kind changes on `msi_purchase`/`installment` rows fail validation with `c1.err.kind_locked` ("This is part of a recurring payment, so it can't be one-time."); transfers touching them fail with `c1.err.transfer_match_locked` ("This is part of a recurring payment, so it can't be a transfer."). `TransferMatchesController#create` redirects back with that alert instead of raising (the matcher form targets `_top`, so a 422 re-render of the modal would replace the whole page). `TransactionsController#update` already returns 422 + `show`; the drawer now shows the reason in Settings. `#notification-tray` gets `role="status" aria-live="polite"` (interaction §11.11).

- [ ] **Step 1: Write the failing tests**

Append inside `TransferMatchesControllerTest`:

```ruby
  test "explains instead of failing when the transaction belongs to a recurring payment" do
    installment = create_transaction(amount: 100, account: accounts(:credit_card), kind: "installment")

    assert_no_difference "Transfer.count" do
      post transaction_transfer_match_path(installment), params: {
        transfer_match: { method: "new", target_account_id: accounts(:depository).id }
      }
    end

    assert_redirected_to transactions_url
    assert_equal "This is part of a recurring payment, so it can't be a transfer.", flash[:alert]
  end
```

Append inside `TransactionsControllerTest`:

```ruby
  test "explains why a recurring row can't become one-time" do
    installment = create_transaction(amount: 100, account: accounts(:credit_card), kind: "installment")

    patch transaction_url(installment), params: {
      entry: { entryable_attributes: { id: installment.entryable_id, kind: "one_time" } }
    }, headers: { "Turbo-Frame" => "drawer" }

    assert_response :unprocessable_entity
    assert_includes response.body, ERB::Util.html_escape("This is part of a recurring payment, so it can't be one-time.")
    assert installment.reload.transaction.installment?
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/transfer_matches_controller_test.rb test/controllers/transactions_controller_test.rb`
Expected: the transfer test ERRORs with `ActiveRecord::RecordInvalid`; the drawer test fails on the missing message. (Other tests in these files may already be in the 124-failure baseline; compare names, not counts.)

- [ ] **Step 3: Implement**

`app/models/transaction.rb:61`:

```ruby
      errors.add(:kind, "This is part of a recurring payment, so it can't be one-time.")
```

`app/models/transfer.rb:135`:

```ruby
        errors.add(:base, "This is part of a recurring payment, so it can't be a transfer.")
```

`app/controllers/transfer_matches_controller.rb` — replace `create`:

```ruby
  LOCKED_MESSAGE = "This is part of a recurring payment, so it can't be a transfer.".freeze

  def create
    if Transaction::PLAN_LOCKED_KINDS.include?(@entry.transaction.kind)
      return redirect_back_or_to transactions_path, alert: LOCKED_MESSAGE
    end

    @transfer = build_transfer
    Transfer.transaction do
      @transfer.save!
      @transfer.outflow_transaction.update!(kind: Transfer.kind_for_account(@transfer.outflow_transaction.entry.account))
      @transfer.inflow_transaction.update!(kind: "funds_movement")
    end

    @transfer.sync_account_later

    redirect_back_or_to transactions_path, notice: "Transfer created"
  rescue ActiveRecord::RecordInvalid => e
    redirect_back_or_to transactions_path, alert: e.record.errors.map(&:message).to_sentence
  end
```

`app/views/transactions/show.html.erb` — first thing inside `dialog.with_section(title: t(".settings")) do` (line 101), before the first `<div class="pb-4">`:

```erb
      <% if @entry.errors.any? %>
        <div role="alert" class="pb-4">
          <%= render DS::Alert.new(message: @entry.errors.map(&:message).uniq.to_sentence, variant: :error) %>
        </div>
      <% end %>
```

and add `open: @entry.errors.any?` to that section call: `dialog.with_section(title: t(".settings"), open: @entry.errors.any?) do`.

`app/views/layouts/shared/_htmldoc.html.erb:22`:

```erb
      <div id="notification-tray" class="space-y-1 w-full" role="status" aria-live="polite">
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: both new tests pass; no test that passed before now fails.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/models/transaction.rb app/models/transfer.rb app/controllers/transfer_matches_controller.rb test/controllers/transfer_matches_controller_test.rb test/controllers/transactions_controller_test.rb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/transactions/show.html.erb app/views/layouts/shared/_htmldoc.html.erb -a
git add app/models/transaction.rb app/models/transfer.rb app/controllers/transfer_matches_controller.rb app/views/transactions/show.html.erb app/views/layouts/shared/_htmldoc.html.erb test/controllers/transfer_matches_controller_test.rb test/controllers/transactions_controller_test.rb
git commit -m "Explain locked recurring rows instead of failing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Live summary endpoint, labels helper and budget-impact block (B2)

**Files:**
- Modify: `config/routes.rb` (after the `resources :transactions` block, line 136)
- Create: `app/controllers/concerns/recurrence_params.rb`
- Create: `app/controllers/recurring_transactions_controller.rb` (only `preview` here; Task 13 adds the rest)
- Create: `app/helpers/recurring_transactions_helper.rb`
- Create: `app/views/recurring_transactions/_preview.html.erb`, `app/views/recurring_transactions/_budget_impact.html.erb`
- Test (create): `test/helpers/recurring_transactions_helper_test.rb`, `test/controllers/recurring_transactions_controller_test.rb`

**Interfaces:**
- Consumes: `RecurringTransaction.build_from_entry`, `#backfill_count`, `#budget_impact` (Tasks 2, 5).
- Produces:
  - Routes: `preview_recurring_transactions_path` (GET), `recurring_transaction_path(plan)` (GET show / PATCH update), `stop_recurring_transaction_path(plan)` (PATCH).
  - `RecurrenceParams` (private): `recurrence_params`, `recurrence_requested? -> Boolean`, `recurrence_attributes -> Hash` (`plan_type:`, `total_payments:`, and `start_date:` only when the param was sent), `recurrence_notice(plan) -> String` (`b3.success_installments` / `b3.success_charge`).
  - `GET /recurring_transactions/preview` params: `entry[account_id|amount|currency|date]` **or** `entry_id`, `recurrence[plan_type|total_payments|start_date]`, `impact=1` (B1 only). Renders `<turbo-frame id="recurring_preview">` with the summary (empty when anything is missing/invalid) and a hidden `[data-recurring-form-announcement]` carrying the spoken text.
  - `RecurringTransactionsHelper`: `recurring_date(date, short: false)`, `recurring_money(amount, currency)`, `recurring_summary(plan, as_of:) -> RecurringSummary(icon, line1, line2, past_due, announcement)`, `recurring_icon(plan)`, `recurring_occurrence_label(plan, number)`, `recurring_provenance_label(transaction)`, `recurring_status_text(transaction)`, `recurring_plan_state(plan) -> [icon_or_nil, text]`, `recurring_group_label(date, today:)`, `budget_impact_title(impact) -> String | nil`.

- [ ] **Step 1: Write the failing tests**

Create `test/helpers/recurring_transactions_helper_test.rb`:

```ruby
require "test_helper"

class RecurringTransactionsHelperTest < ActionView::TestCase
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 10, 8)
    @card = accounts(:credit_card)
    @card.entries.delete_all
    @family = families(:dylan_family)
  end

  test "summarizes even installments in two lines" do
    plan = build(amount: 15000, total_payments: 12, start_date: Date.new(2026, 11, 8))
    summary = recurring_summary(plan, as_of: Date.new(2026, 10, 8))

    assert_equal "credit-card", summary.icon
    assert_equal "12 installments of $1,250.00", summary.line1
    assert_equal "Last on Oct 8, 2027", summary.line2
    assert_nil summary.past_due
    assert_equal "12 installments of $1,250.00, last on Oct 8, 2027", summary.announcement
  end

  test "names an uneven last installment" do
    plan = build(amount: 10000, total_payments: 6, start_date: Date.new(2026, 10, 27))

    assert_equal "Last one $1,666.70 on Mar 27, 2027", recurring_summary(plan, as_of: Date.new(2026, 10, 8)).line2
  end

  test "summarizes charges and past payments" do
    open_charge = build(plan_type: "charge", amount: 199, total_payments: nil, start_date: Date.new(2026, 6, 30))
    summary = recurring_summary(open_charge, as_of: Date.new(2026, 10, 8))

    assert_equal "repeat", summary.icon
    assert_equal "$199.00 every month", summary.line1
    assert_equal "No end date", summary.line2
    assert_equal "3 already due. They'll be added with their original dates.", summary.past_due

    ending = build(plan_type: "charge", amount: 199, total_payments: 12, start_date: Date.new(2026, 10, 15))
    assert_equal "$199.00 every month, 12 payments, last on Sep 15, 2027", recurring_summary(ending, as_of: Date.new(2026, 10, 8)).announcement
  end

  test "labels occurrences and plan states with interface copy" do
    installments = build(amount: 6000, total_payments: 6, start_date: Date.new(2026, 11, 8))
    charge = build(plan_type: "charge", amount: 299, total_payments: nil, start_date: Date.new(2026, 10, 12))

    assert_equal "Installment 2 of 6", recurring_occurrence_label(installments, 2)
    assert_equal "Monthly charge", recurring_occurrence_label(charge, 3)
    assert_equal "Payment 3 of 12", recurring_occurrence_label(build(plan_type: "charge", total_payments: 12), 3)
    assert_equal [ nil, "Active" ], recurring_plan_state(installments)
    assert_equal "Today", recurring_group_label(Date.new(2026, 10, 8), today: Date.new(2026, 10, 8))
    assert_equal "Tomorrow", recurring_group_label(Date.new(2026, 10, 9), today: Date.new(2026, 10, 8))
    assert_equal "Oct 12", recurring_group_label(Date.new(2026, 10, 12), today: Date.new(2026, 10, 8))
    assert_equal "Jan 8, 2027", recurring_group_label(Date.new(2027, 1, 8), today: Date.new(2026, 10, 8))
  end

  test "describes where a transaction comes from" do
    purchase = create_transaction(account: @card, amount: 1200, name: "Desk", date: Date.new(2026, 8, 20))
    plan = RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 12)

    assert_equal "Paid in 12 installments", recurring_provenance_label(purchase.transaction)
    assert_equal "Installment 1 of 12", recurring_provenance_label(plan.transactions.find_by(installment_number: 1))
    assert_equal "One time", recurring_status_text(create_transaction(account: @card, amount: 10).transaction)
  end

  private
    def build(plan_type: "installments", amount: 1000, total_payments: 3, start_date: Date.new(2026, 11, 8))
      RecurringTransaction.new(family: @family, account: @card, name: "Plan", plan_type: plan_type,
                               amount: amount, currency: "USD", total_payments: total_payments, start_date: start_date)
    end
end
```

Create `test/controllers/recurring_transactions_controller_test.rb`:

```ruby
require "test_helper"

class RecurringTransactionsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 10, 8)
    sign_in users(:family_admin)
    @card = accounts(:credit_card)
    @card.entries.delete_all
    @frame = { "Turbo-Frame" => "recurring_preview" }
  end

  test "preview summarizes installments for a new purchase" do
    get preview_recurring_transactions_url, params: {
      entry: { account_id: @card.id, amount: "15000", currency: "USD", date: "2026-10-08" },
      recurrence: { plan_type: "installments", total_payments: "12", start_date: "2026-11-08" }
    }, headers: @frame

    assert_response :success
    assert_includes response.body, "12 installments of $1,250.00"
    assert_includes response.body, "Last on Oct 8, 2027"
  end

  test "preview stays empty while data is missing" do
    get preview_recurring_transactions_url, params: {
      entry: { account_id: @card.id, amount: "15000", currency: "USD", date: "2026-10-08" },
      recurrence: { plan_type: "installments", total_payments: "" }
    }, headers: @frame

    assert_response :success
    assert_includes response.body, %(<turbo-frame id="recurring_preview">)
    assert_not_includes response.body, "installments of"
  end

  test "preview shows the budget impact when asked" do
    family = families(:dylan_family)
    family.budgets.destroy_all
    family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                           currency: "USD", budgeted_spending: 1000, expected_income: 3000)

    get preview_recurring_transactions_url, params: {
      impact: "1",
      entry: { account_id: @card.id, amount: "3600", currency: "USD", date: "2026-10-08" },
      recurrence: { plan_type: "installments", total_payments: "3", start_date: "2026-11-08" }
    }, headers: @frame

    assert_includes response.body, "This puts 3 budgets over. The first is November 2026."
    assert_includes response.body, "Budget impact of the next 3 installments"
    assert_includes response.body, "Months without a budget use your October 2026 budget."
  end

  test "preview of an existing entry" do
    entry = create_transaction(account: @card, amount: 199, name: "Spotify", date: Date.new(2026, 6, 30))

    get preview_recurring_transactions_url, params: { entry_id: entry.id, recurrence: { plan_type: "charge" } }, headers: @frame

    assert_includes response.body, "$199.00 every month"
    assert_includes response.body, ERB::Util.html_escape("3 already due. They'll be added with their original dates.")
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/helpers/recurring_transactions_helper_test.rb test/controllers/recurring_transactions_controller_test.rb`
Expected: ERROR — undefined helper methods / no route `preview_recurring_transactions_url`.

- [ ] **Step 3: Implement**

`config/routes.rb` — after the `resources :transactions ... end` block (line 136):

```ruby
  resources :recurring_transactions, only: %i[show update] do
    get :preview, on: :collection
    patch :stop, on: :member
  end
```

Create `app/controllers/concerns/recurrence_params.rb`:

```ruby
# The virtual `recurrence[...]` params of the capture and convert forms (kept out of entry params)
module RecurrenceParams
  extend ActiveSupport::Concern

  private
    def recurrence_params
      params.fetch(:recurrence, {}).permit(:plan_type, :total_payments, :start_date)
    end

    def recurrence_requested?
      recurrence_params[:plan_type].in?(RecurringTransaction::PLAN_TYPES)
    end

    # start_date is only passed when the form sent it, so a cleared field is an error rather than the default
    def recurrence_attributes
      attributes = { plan_type: recurrence_params[:plan_type], total_payments: recurrence_params[:total_payments].presence }
      attributes[:start_date] = recurrence_params[:start_date].to_s if recurrence_params.key?(:start_date)
      attributes
    end

    def recurrence_notice(plan)
      plan.installments? ? "Split into #{plan.total_payments} installments." : "Monthly charge started."
    end
end
```

Create `app/controllers/recurring_transactions_controller.rb`:

```ruby
class RecurringTransactionsController < ApplicationController
  include RecurrenceParams

  # B2: server-side summary (and B1 budget impact) for the plan being typed; never saves anything
  def preview
    render partial: "recurring_transactions/preview", locals: {
      plan: build_preview_plan,
      show_impact: params[:impact] == "1",
      surface: params[:entry_id].present? ? :container : :inset
    }
  end

  private
    def build_preview_plan
      return nil unless recurrence_requested?

      entry = preview_entry
      entry && RecurringTransaction.build_from_entry(entry, **recurrence_attributes)
    end

    def preview_entry
      return Current.family.entries.find_by(id: params[:entry_id]) if params[:entry_id].present?

      account = Current.family.accounts.find_by(id: params.dig(:entry, :account_id))
      return nil unless account

      Entry.new(
        account: account,
        name: "Preview",
        date: parse_date(params.dig(:entry, :date)),
        amount: params.dig(:entry, :amount).presence,
        currency: params.dig(:entry, :currency).presence || account.currency,
        entryable: Transaction.new
      )
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
end
```

Create `app/helpers/recurring_transactions_helper.rb`:

```ruby
module RecurringTransactionsHelper
  RecurringSummary = Data.define(:icon, :line1, :line2, :past_due, :announcement)

  # "Mar 27, 2027"; with short: true, "Oct 27" in the current year
  def recurring_date(date, short: false)
    return date.strftime("%b %-d") if short && date.year == Date.current.year

    date.strftime("%b %-d, %Y")
  end

  def recurring_money(amount, currency)
    Money.new(amount, currency).format
  end

  def recurring_icon(plan)
    plan.installments? ? "credit-card" : "repeat"
  end

  # B2 summary: figures on line 1, dates on line 2 (copy b2.*); the announcement uses commas instead of "·"
  def recurring_summary(plan, as_of: plan.family.today)
    first_amount = recurring_money(plan.occurrence_amount(1), plan.currency)

    if plan.installments?
      line1 = "#{plan.total_payments} installments of #{first_amount}"
      last_amount = plan.occurrence_amount(plan.total_payments)
      last_date = recurring_date(plan.end_date)

      if last_amount == plan.occurrence_amount(1)
        line2 = "Last on #{last_date}"
        spoken = "#{line1}, last on #{last_date}"
      else
        last_money = recurring_money(last_amount, plan.currency)
        line2 = "Last one #{last_money} on #{last_date}"
        spoken = "#{line1}, last one #{last_money} on #{last_date}"
      end
    else
      line1 = "#{first_amount} every month"

      if plan.total_payments
        payments = pluralize(plan.total_payments, "payment")
        last_date = recurring_date(plan.end_date)
        line2 = safe_join([ payments, tag.span("·", aria: { hidden: true }), "last on #{last_date}" ], " ")
        spoken = "#{line1}, #{payments}, last on #{last_date}"
      else
        line2 = "No end date"
        spoken = "#{line1}, no end date"
      end
    end

    backfill = plan.backfill_count(as_of: as_of)
    past_due = backfill.positive? ? "#{backfill} already due. They'll be added with their original dates." : nil

    RecurringSummary.new(
      icon: recurring_icon(plan),
      line1: line1,
      line2: line2,
      past_due: past_due,
      announcement: [ spoken, past_due ].compact.join(". ")
    )
  end

  # c1.installment_line / c1.charge_line_end / c1.charge_line_open
  def recurring_occurrence_label(plan, number)
    if plan.installments?
      "Installment #{number} of #{plan.total_payments}"
    elsif plan.total_payments
      "Payment #{number} of #{plan.total_payments}"
    else
      "Monthly charge"
    end
  end

  # C1 provenance line of a transaction linked to a plan
  def recurring_provenance_label(transaction)
    plan = transaction.recurring_transaction
    return "Paid in #{plan.total_payments} installments" if transaction.msi_purchase?

    recurring_occurrence_label(plan, transaction.installment_number)
  end

  # b3.status_* under "Recurring payment" in the drawer
  def recurring_status_text(transaction)
    plan = transaction.recurring_transaction
    return "One time" unless plan
    return "Monthly charge" if plan.charge?

    number = transaction.installment? ? transaction.installment_number : plan.last_handled_number
    safe_join([ "Installments", tag.span("·", aria: { hidden: true }), tag.span(",", class: "sr-only"), "#{number} of #{plan.total_payments}" ], " ")
  end

  # [icon, text] for a plan's state: Active / Stopped {date} / Paid off {date} / Ended {date}
  def recurring_plan_state(plan)
    case plan.status
    when "active" then [ nil, "Active" ]
    when "cancelled" then [ "circle-stop", "Stopped #{recurring_date(plan.ended_on)}" ]
    else [ "check", "#{plan.installments? ? "Paid off" : "Ended"} #{recurring_date(plan.ended_on)}" ]
    end
  end

  # c2.upcoming_group
  def recurring_group_label(date, today: Current.family.today)
    return "Today" if date == today
    return "Tomorrow" if date == today + 1.day

    recurring_date(date, short: true)
  end

  # bi.title_over / bi.title_over_multi (nil when no month goes over)
  def budget_impact_title(impact)
    over = impact.over_months
    return nil if over.empty?

    first = over.first
    if over.size > 1
      "This puts #{over.size} budgets over. The first is #{first.budget.name}."
    else
      "This puts #{first.budget.name} #{recurring_money(first.overage, first.budget.currency)} over budget"
    end
  end
end
```

Create `app/views/recurring_transactions/_preview.html.erb`:

```erb
<%# locals: (plan:, show_impact: false, surface: :inset) %>

<%= turbo_frame_tag "recurring_preview" do %>
  <% if plan&.valid? %>
    <% summary = recurring_summary(plan) %>
    <% impact = plan.budget_impact if show_impact && plan.installments? %>
    <% impact = nil unless impact&.available? %>
    <% impact_title = impact && budget_impact_title(impact) %>

    <div class="space-y-3">
      <div class="<%= class_names("rounded-lg px-3 py-2 flex items-start gap-2", surface == :container ? "bg-container shadow-border-xs" : "bg-container-inset") %>">
        <%= icon summary.icon, size: "sm", class: "mt-0.5" %>

        <div class="text-sm tabular-nums min-w-0">
          <p class="text-primary font-medium"><%= summary.line1 %></p>
          <p class="text-secondary"><%= summary.line2 %></p>
          <% if summary.past_due %>
            <p class="text-secondary mt-1"><%= summary.past_due %></p>
          <% end %>
        </div>
      </div>

      <%# Copied by recurring-form into its live region: one announcement per pause %>
      <span hidden data-recurring-form-announcement><%= [ summary.announcement, impact_title ].compact.join(". ") %></span>

      <% if impact %>
        <%= render "recurring_transactions/budget_impact", impact: impact, title: impact_title %>
      <% end %>
    </div>
  <% end %>
<% end %>
```

Create `app/views/recurring_transactions/_budget_impact.html.erb` (visual spec §2, canvas `Main.dc.html` figure 2; red text = orchestrator default):

```erb
<%# locals: (impact:, title:) %>

<% over_text = "text-red-700 theme-dark:text-red-400" %>
<% count = impact.installments_count %>
<% subtitle = count == 1 ? "Budget impact of the next installment" : "Budget impact of the next #{count} installments" %>

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
        <div class="flex items-center justify-between text-sm tabular-nums">
          <span class="text-primary font-medium"><%= month.budget.name %></span>
          <% if month.over? %>
            <span class="font-medium <%= over_text %>"><%= recurring_money(month.overage, currency) %> over</span>
          <% else %>
            <span class="text-secondary"><%= month.percent %>% of budget</span>
          <% end %>
        </div>

        <div class="relative flex h-2 rounded bg-surface-inset" aria-hidden="true">
          <div class="h-2 rounded-l bg-inverse" style="width: <%= impact.width(month.committed) %>%"></div>
          <div class="h-2 rounded-r bg-destructive" style="width: <%= impact.width(month.purchase) %>%"></div>
          <div class="absolute -top-1 h-4 w-0.5 rounded-sm bg-current text-secondary" style="left: <%= impact.width(month.basis) %>%"></div>
        </div>

        <p class="text-xs text-secondary tabular-nums">
          <%= recurring_money(month.total, currency) %> of <%= recurring_money(month.basis, currency) %> budgeted
        </p>
      </li>
    <% end %>
  </ul>

  <div class="flex flex-wrap items-center gap-4 text-xs text-secondary" aria-hidden="true">
    <span class="flex items-center gap-1.5"><span class="size-2 rounded-sm bg-inverse"></span>Already committed</span>
    <span class="flex items-center gap-1.5"><span class="size-2 rounded-sm bg-destructive"></span>This purchase</span>
    <span class="flex items-center gap-1.5"><span class="h-2.5 w-0.5 bg-current"></span>Budget</span>
  </div>

  <% if (reference = impact.reference_budget) %>
    <p class="text-xs text-secondary">Months without a budget use your <%= reference.name %> budget.</p>
  <% end %>
</section>
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: all pass. (`preview` renders a partial, so the test never touches the app layout.)

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop config/routes.rb app/controllers/concerns/recurrence_params.rb app/controllers/recurring_transactions_controller.rb app/helpers/recurring_transactions_helper.rb test/helpers/recurring_transactions_helper_test.rb test/controllers/recurring_transactions_controller_test.rb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/recurring_transactions/_preview.html.erb app/views/recurring_transactions/_budget_impact.html.erb -a
git add config/routes.rb app/controllers/concerns/recurrence_params.rb app/controllers/recurring_transactions_controller.rb app/helpers/recurring_transactions_helper.rb app/views/recurring_transactions test/helpers/recurring_transactions_helper_test.rb test/controllers/recurring_transactions_controller_test.rb
git commit -m "Render the recurring payment summary and budget impact on the server

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Capture fields and the `recurring-form` controller (B1 view)

**Files:**
- Create: `app/views/transactions/_recurrence_fields.html.erb`, `app/views/transactions/_recurrence_error.html.erb`
- Create: `app/javascript/controllers/recurring_form_controller.js`
- Modify: `app/views/transactions/_form.html.erb`, `app/views/transactions/new.html.erb`
- Modify: `app/helpers/recurring_transactions_helper.rb` (add `recurring_credit_account_ids`)

**Interfaces:**
- Consumes: `preview_recurring_transactions_path(impact: 1)` (Task 9), `RecurringTransaction` errors (Task 2).
- Produces:
  - Partial `transactions/recurrence_fields` locals `(recurrence:, installments_available:, default_first_payment:, show_base_error: true, autofocus_type: false)`. Inputs: radios `recurrence[plan_type]` (`""` / `charge` / `installments`), `recurrence[total_payments]` (one input per type, the inactive one `disabled`), `recurrence[start_date]` (installments only). Contains `<turbo-frame id="recurring_preview">` and the `sr-only` live region.
  - Stimulus `recurring-form` — targets `fields` (×2, `data-plan-type`), `installmentsOption`, `firstPayment`, `preview`, `status`, `review`; values `previewUrl` (String), `creditAccountIds` (Array), `accountId` (String), `unavailableText` (String), `creditOnlyText` (String); actions `selectType`, `accountChanged`, `syncFirstPayment`, `markFirstPaymentEdited`, `schedulePreview`, `previewLoaded`, `previewFailed`.
  - `_form` local `recurrence:` (default nil); `new.html.erb` passes `@recurrence`.
  - `recurring_credit_account_ids -> Array<String>`.

This task is view + JS only; it's verified in the browser (Task 18) and by Task 11's controller tests, which render this form.

- [ ] **Step 1: Add the helper** — append inside `RecurringTransactionsHelper`:

```ruby
  # Accounts whose new transactions can be split into installments (manual, active credit cards)
  def recurring_credit_account_ids
    Current.family.accounts.manual.active.where(accountable_type: "CreditCard").pluck(:id)
  end
```

- [ ] **Step 2: Create `app/javascript/controllers/recurring_form_controller.js`**

```js
import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="recurring-form"
// Shows the fields of the chosen recurring payment type and asks the server for a
// live summary 500 ms after the last change. It never formats money or computes payments.
export default class extends Controller {
  static targets = ["fields", "installmentsOption", "firstPayment", "preview", "status", "review"];
  static values = {
    previewUrl: String,
    creditAccountIds: Array,
    accountId: String,
    unavailableText: String,
    creditOnlyText: String,
  };

  connect() {
    this.#syncInstallmentsOption();
    this.#applyType();
    if (this.#planType) this.schedulePreview();
  }

  disconnect() {
    clearTimeout(this.previewTimeout);
  }

  selectType() {
    this.#applyType();
    this.schedulePreview();
  }

  accountChanged() {
    this.#syncInstallmentsOption();
    this.schedulePreview();
  }

  syncFirstPayment(event) {
    if (!this.hasFirstPaymentTarget || this.firstPaymentTarget.dataset.edited === "true") return;

    const nextMonth = this.#addOneMonth(event.target.value);
    if (nextMonth) this.firstPaymentTarget.value = nextMonth;
  }

  markFirstPaymentEdited() {
    this.firstPaymentTarget.dataset.edited = "true";
  }

  schedulePreview() {
    if (!this.hasPreviewTarget) return;
    clearTimeout(this.previewTimeout);

    if (!this.#planType) {
      this.#clearPreview();
      return;
    }

    this.previewTarget.setAttribute("aria-busy", "true");
    this.previewTarget.classList.add("opacity-60");
    this.previewTimeout = setTimeout(() => this.#loadPreview(), 500);
  }

  previewLoaded() {
    this.#finishLoading();
    const announcement = this.previewTarget.querySelector("[data-recurring-form-announcement]");
    this.#announce(announcement ? announcement.textContent.trim() : "");
  }

  previewFailed(event) {
    event.preventDefault();
    this.#finishLoading();

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

  get #planType() {
    const checked = this.element.querySelector('input[name="recurrence[plan_type]"]:checked');
    return checked ? checked.value : "";
  }

  get #form() {
    return this.element.closest("form") || this.element;
  }

  #applyType() {
    const type = this.#planType;

    this.fieldsTargets.forEach((group) => {
      const active = group.dataset.planType === type;
      group.hidden = !active;
      group.querySelectorAll("input, select").forEach((input) => {
        input.disabled = !active;
      });
    });

    if (this.hasReviewTarget) this.reviewTarget.disabled = type === "";
  }

  #syncInstallmentsOption() {
    if (!this.hasInstallmentsOptionTarget) return;

    const accountId = this.accountIdValue || this.#formValue("entry[account_id]");
    const isCreditCard = this.creditAccountIdsValue.includes(accountId);
    const radio = this.installmentsOptionTarget.querySelector("input");

    this.installmentsOptionTarget.hidden = !isCreditCard;
    radio.disabled = !isCreditCard;

    if (!isCreditCard && radio.checked) {
      this.element.querySelector('input[name="recurrence[plan_type]"][value=""]').checked = true;
      this.#applyType();
      this.#clearPreview();
      this.#announce(this.creditOnlyTextValue);
    }
  }

  #loadPreview() {
    const url = new URL(this.previewUrlValue, window.location.origin);
    const data = new FormData(this.#form);

    [
      "entry[account_id]",
      "entry[amount]",
      "entry[currency]",
      "entry[date]",
      "recurrence[plan_type]",
      "recurrence[total_payments]",
      "recurrence[start_date]",
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
    this.#announce("");
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

  #formValue(name) {
    const field = this.#form.elements.namedItem(name);
    return field ? field.value : "";
  }

  // Same rule as Ruby's Date#next_month: Jan 31 -> Feb 28
  #addOneMonth(isoDate) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(isoDate || "");
    if (!match) return null;

    const year = Number(match[1]);
    const month = Number(match[2]);
    const day = Number(match[3]);
    const targetYear = month === 12 ? year + 1 : year;
    const targetMonth = month === 12 ? 1 : month + 1;
    const lastDay = new Date(Date.UTC(targetYear, targetMonth, 0)).getUTCDate();
    const pad = (n) => String(n).padStart(2, "0");

    return `${targetYear}-${pad(targetMonth)}-${pad(Math.min(day, lastDay))}`;
  }
}
```

- [ ] **Step 3: Create `app/views/transactions/_recurrence_fields.html.erb`** (canvas `Main.dc.html` figures 1, 2, 4, 5; copy `b1.*`, `b.err.*`)

```erb
<%# locals: (recurrence:, installments_available:, default_first_payment:, show_base_error: true, autofocus_type: false) %>

<% plan_type = recurrence&.plan_type.to_s %>
<% errors = recurrence&.errors %>
<% payments_error = errors&.[](:total_payments)&.first %>
<% start_error = errors&.[](:start_date)&.first %>
<% base_error = show_base_error && errors && (errors[:base] + errors[:account]).first %>
<% first_invalid = if base_error then :plan_type elsif payments_error then :total_payments elsif start_error then :start_date end %>
<% first_payment = recurrence&.installments? ? recurrence.start_date : default_first_payment %>

<div class="space-y-3">
  <fieldset <%= tag.attributes("aria-describedby": ("recurrence_base_error" if base_error)) %>>
    <legend class="text-xs text-secondary mb-1">Repeat</legend>

    <% [ [ "", "Doesn't repeat", "none" ], [ "charge", "Monthly charge", "charge" ], [ "installments", "Installments", "installments" ] ].each do |value, label, key| %>
      <% installments = value == "installments" %>
      <%= tag.label class: "flex items-center gap-2 min-h-11 text-sm text-primary",
                    hidden: installments && !installments_available,
                    data: (installments ? { recurring_form_target: "installmentsOption" } : {}) do %>
        <%= radio_button_tag "recurrence[plan_type]", value, plan_type == value,
              id: "recurrence_plan_type_#{key}",
              class: "form-field__radio",
              disabled: installments && !installments_available,
              autofocus: (plan_type == value && (first_invalid == :plan_type || (autofocus_type && first_invalid.nil?))),
              data: { action: "change->recurring-form#selectType" } %>
        <span><%= label %></span>
      <% end %>
    <% end %>

    <% if base_error %>
      <div class="mt-1"><%= render "transactions/recurrence_error", id: "recurrence_base_error", message: base_error %></div>
    <% end %>
  </fieldset>

  <%= tag.div class: "@container", hidden: plan_type != "installments",
              data: { recurring_form_target: "fields", plan_type: "installments" } do %>
    <div class="grid grid-cols-1 @sm:grid-cols-2 gap-2">
      <div class="flex flex-col gap-1">
        <label class="<%= class_names("form-field", "border-destructive": payments_error && plan_type == "installments") %>" for="recurrence_total_payments_installments">
          <span class="form-field__label">Number of installments</span>
          <%= number_field_tag "recurrence[total_payments]",
                (recurrence&.total_payments_before_type_cast if plan_type == "installments"),
                id: "recurrence_total_payments_installments",
                class: "form-field__input tabular-nums h-5",
                inputmode: "numeric", min: 2, max: RecurringTransaction::MAX_INSTALLMENTS, step: 1,
                disabled: plan_type != "installments",
                autofocus: first_invalid == :total_payments && plan_type == "installments",
                "aria-invalid": (payments_error.present? if plan_type == "installments"),
                "aria-describedby": ("recurrence_total_payments_installments_error" if payments_error && plan_type == "installments") %>
        </label>
        <% if payments_error && plan_type == "installments" %>
          <%= render "transactions/recurrence_error", id: "recurrence_total_payments_installments_error", message: payments_error %>
        <% end %>
      </div>

      <div class="flex flex-col gap-1">
        <label class="<%= class_names("form-field", "border-destructive": start_error) %>" for="recurrence_start_date">
          <span class="form-field__label">First payment</span>
          <%= date_field_tag "recurrence[start_date]", first_payment&.iso8601,
                id: "recurrence_start_date",
                class: "form-field__input tabular-nums h-5",
                disabled: plan_type != "installments",
                autofocus: first_invalid == :start_date,
                "aria-invalid": start_error.present?,
                "aria-describedby": ("recurrence_start_date_error" if start_error),
                data: { recurring_form_target: "firstPayment", action: "input->recurring-form#markFirstPaymentEdited" } %>
        </label>
        <% if start_error %>
          <%= render "transactions/recurrence_error", id: "recurrence_start_date_error", message: start_error %>
        <% end %>
      </div>
    </div>
  <% end %>

  <%= tag.div class: "flex flex-col gap-1", hidden: plan_type != "charge",
              data: { recurring_form_target: "fields", plan_type: "charge" } do %>
    <label class="<%= class_names("form-field", "border-destructive": payments_error && plan_type == "charge") %>" for="recurrence_total_payments_charge">
      <span class="form-field__label">Ends after</span>
      <span class="flex items-center gap-2">
        <%= number_field_tag "recurrence[total_payments]",
              (recurrence&.total_payments_before_type_cast if plan_type == "charge"),
              id: "recurrence_total_payments_charge",
              class: "form-field__input tabular-nums w-16",
              inputmode: "numeric", min: 1, step: 1, placeholder: "—",
              disabled: plan_type != "charge",
              autofocus: first_invalid == :total_payments && plan_type == "charge",
              "aria-invalid": (payments_error.present? if plan_type == "charge"),
              "aria-describedby": ("recurrence_total_payments_charge_error" if payments_error && plan_type == "charge") %>
        <span class="text-sm text-secondary">payments</span>
      </span>
    </label>
    <% if payments_error && plan_type == "charge" %>
      <%= render "transactions/recurrence_error", id: "recurrence_total_payments_charge_error", message: payments_error %>
    <% end %>
  <% end %>

  <%= turbo_frame_tag "recurring_preview",
        class: "block transition-opacity duration-150 motion-reduce:transition-none",
        data: {
          recurring_form_target: "preview",
          action: "turbo:frame-load->recurring-form#previewLoaded turbo:frame-missing->recurring-form#previewFailed turbo:fetch-request-error->recurring-form#previewFailed"
        } %>

  <p class="sr-only" role="status" aria-live="polite" aria-atomic="true" data-recurring-form-target="status"></p>
</div>
```

Create `app/views/transactions/_recurrence_error.html.erb` (canvas `Main.dc.html` figure 5: message under its field, left edge = field edge):

```erb
<%# locals: (id:, message:) %>

<p id="<%= id %>" class="text-xs text-destructive flex items-start gap-1">
  <%= icon "circle-alert", size: "xs", color: "current", class: "mt-0.5" %><span><%= message %></span>
</p>
```

- [ ] **Step 4: Wire the B1 form** — `app/views/transactions/_form.html.erb`:

Replace lines 1-3 with:

```erb
<%# locals: (entry:, income_categories:, expense_categories:, recurrence: nil) %>

<% outflow = params[:nature] != "inflow" && params.dig(:entry, :nature) != "inflow" %>
<% recurring_data = if outflow
     {
       controller: "recurring-form",
       recurring_form_preview_url_value: preview_recurring_transactions_path(impact: 1),
       recurring_form_credit_account_ids_value: recurring_credit_account_ids,
       recurring_form_unavailable_text_value: "We couldn't calculate this. You can still save.",
       recurring_form_credit_only_text_value: "Installments only work on credit cards.",
       action: "input->recurring-form#schedulePreview change->recurring-form#schedulePreview"
     }
   else
     {}
   end %>

<%= styled_form_with model: entry, url: transactions_path, class: "space-y-4", data: recurring_data do |f| %>
```

Replace the account `collection_select` (line 21) with:

```erb
      <%= f.collection_select :account_id, Current.family.accounts.manual.active.alphabetically, :id, :name, { prompt: t(".account_prompt"), label: t(".account") }, required: true, class: "form-field__input text-ellipsis", data: { action: "change->recurring-form#accountChanged" } %>
```

Replace the date field (line 29) with:

```erb
    <%= f.date_field :date, label: t(".date"), required: true, min: Entry.min_supported_date, max: Date.current, value: Date.current, data: { action: "change->recurring-form#syncFirstPayment" } %>
```

Insert between the closing `</section>` of the main section (line 30) and the Details disclosure (line 32):

```erb
  <% if outflow %>
    <%= render DS::Disclosure.new(title: "Recurring payment", open: recurrence.present?) do %>
      <%= render "transactions/recurrence_fields",
                 recurrence: recurrence,
                 installments_available: entry.account&.credit_card? || false,
                 default_first_payment: (entry.date || Date.current).next_month %>
    <% end %>
  <% end %>
```

`app/views/transactions/new.html.erb` line 4:

```erb
    <%= render "form", entry: @entry, income_categories: @income_categories, expense_categories: @expense_categories, recurrence: @recurrence %>
```

- [ ] **Step 5: Lint**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/helpers/recurring_transactions_helper.rb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/transactions/_recurrence_fields.html.erb app/views/transactions/_recurrence_error.html.erb app/views/transactions/_form.html.erb app/views/transactions/new.html.erb -a
npm run lint
```

Expected: no offenses (fix any reported by `npm run lint` in `recurring_form_controller.js`; if `npm` isn't available on the host, run Biome later in Task 18).

- [ ] **Step 6: Smoke test the render** — run `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/transactions_controller_test.rb`. Expected: no new failures compared with before this task (the form now renders the disclosure for outflows).

- [ ] **Step 7: Commit**

```bash
git add app/javascript/controllers/recurring_form_controller.js app/views/transactions/_recurrence_fields.html.erb app/views/transactions/_recurrence_error.html.erb app/views/transactions/_form.html.erb app/views/transactions/new.html.erb app/helpers/recurring_transactions_helper.rb
git commit -m "Add the Recurring payment fields to new transactions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Create a transaction with its plan, atomically (B1 submit)

**Files:**
- Modify: `app/controllers/transactions_controller.rb:1-2` (include), `:56-74` (`create`), private section
- Test: `test/controllers/transactions_controller_test.rb`

**Interfaces:**
- Consumes: `RecurrenceParams` (Task 9), `RecurringTransaction.build_from_entry` / `.create_from_entry!` / `::GENERIC_ERROR` (Task 2), form partials (Task 10).
- Produces: `POST /transactions` with `recurrence[...]` saves the entry and the plan in one DB transaction; an invalid plan rolls back the entry and re-renders `new` (422) with the disclosure open, errors next to fields and `autofocus` on the first invalid one; success notice is `b3.success_installments` / `b3.success_charge`. Also fixes the latent 422 crash (`@income_categories` / `@expense_categories` were nil when `create` re-rendered `new`).

- [ ] **Step 1: Write the failing tests** — append inside `TransactionsControllerTest`:

```ruby
  test "creates an installment purchase and its plan together" do
    travel_to Date.new(2026, 10, 8)
    card = accounts(:credit_card)

    assert_difference [ "Entry.count", "RecurringTransaction.count" ], 1 do
      post transactions_url, params: {
        entry: recurring_entry_params(card, amount: 15000),
        recurrence: { plan_type: "installments", total_payments: "12", start_date: "2026-11-08" }
      }
    end

    entry = Entry.order(:created_at).last
    assert entry.transaction.msi_purchase?
    assert_equal 12, entry.transaction.recurring_transaction.total_payments
    assert_equal "Split into 12 installments.", flash[:notice]
  end

  test "creates a monthly charge" do
    travel_to Date.new(2026, 10, 8)

    post transactions_url, params: {
      entry: recurring_entry_params(accounts(:depository), amount: 299),
      recurrence: { plan_type: "charge", total_payments: "" }
    }

    entry = Entry.order(:created_at).last
    assert_equal 1, entry.transaction.installment_number
    assert_equal "Monthly charge started.", flash[:notice]
  end

  test "an invalid plan saves nothing and explains why" do
    travel_to Date.new(2026, 10, 8)

    assert_no_difference [ "Entry.count", "RecurringTransaction.count" ] do
      post transactions_url, params: {
        entry: recurring_entry_params(accounts(:credit_card), amount: 15000),
        recurrence: { plan_type: "installments", total_payments: "1", start_date: "2026-11-08" }
      }, headers: { "Turbo-Frame" => "modal" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Enter 2 to 48 installments."
  end

  test "installments are refused on accounts that aren't credit cards" do
    travel_to Date.new(2026, 10, 8)

    assert_no_difference "Entry.count" do
      post transactions_url, params: {
        entry: recurring_entry_params(accounts(:depository), amount: 1200),
        recurrence: { plan_type: "installments", total_payments: "3", start_date: "2026-11-08" }
      }, headers: { "Turbo-Frame" => "modal" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Installments only work on credit cards."
  end

  private
    def recurring_entry_params(account, amount:)
      {
        account_id: account.id, name: "iPad Air", date: "2026-10-08", currency: "USD", amount: amount,
        nature: "outflow", entryable_type: "Transaction",
        entryable_attributes: { category_id: categories(:food_and_drink).id }
      }
    end
```

(If the test class already has a `private` section, put `recurring_entry_params` inside it instead of adding a second one.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/transactions_controller_test.rb`
Expected: the 4 new tests FAIL (no plan created / no 422).

- [ ] **Step 3: Implement** in `app/controllers/transactions_controller.rb`

Line 2:

```ruby
  include EntryableResource, RecurrenceParams
```

Replace `create` (lines 56-74):

```ruby
  def create
    account = Current.family.accounts.find(params.dig(:entry, :account_id))
    @entry = account.entries.new(entry_params)
    @recurrence = RecurringTransaction.build_from_entry(@entry, **recurrence_attributes) if recurrence_requested?

    if save_entry_with_recurrence
      @entry.sync_account_later
      @entry.lock_saved_attributes!
      @entry.transaction.lock_attr!(:tag_ids) if @entry.transaction.tags.any?

      flash[:notice] = @recurrence ? recurrence_notice(@recurrence) : "Transaction created"

      respond_to do |format|
        format.html { redirect_back_or_to account_path(@entry.account) }
        format.turbo_stream { stream_redirect_back_or_to(account_path(@entry.account)) }
      end
    else
      @income_categories = Current.family.categories.incomes.alphabetically
      @expense_categories = Current.family.categories.expenses.alphabetically
      render :new, status: :unprocessable_entity
    end
  end
```

Add in the `private` section:

```ruby
    # The entry and its plan are saved together: an invalid plan never leaves a purchase behind
    def save_entry_with_recurrence
      Entry.transaction do
        entry_saved = @entry.save
        plan_valid = @recurrence.nil? || @recurrence.valid?
        raise ActiveRecord::Rollback unless entry_saved && plan_valid

        @recurrence = RecurringTransaction.create_from_entry!(@entry, **recurrence_attributes) if @recurrence
        true
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("Recurring payment not created: #{e.message}")
      @recurrence&.errors&.add(:base, RecurringTransaction::GENERIC_ERROR)
      false
    end
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: the 4 new tests pass; the pre-existing "creates with transaction details" still passes.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/controllers/transactions_controller.rb test/controllers/transactions_controller_test.rb -a
git add app/controllers/transactions_controller.rb test/controllers/transactions_controller_test.rb
git commit -m "Create a transaction and its recurring payment in one step

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Convert an existing transaction from its drawer (B3)

**Files:**
- Modify: `config/routes.rb:129-136` (nested `resource :recurrence`)
- Create: `app/controllers/transactions/recurrences_controller.rb`
- Create: `app/views/transactions/recurrences/_recurrence.html.erb`, `_closed.html.erb`, `_fields.html.erb`, `_confirm.html.erb`
- Modify: `app/helpers/recurring_transactions_helper.rb` (add `recurrence_block_state`)
- Modify: `app/views/transactions/show.html.erb` (first block of Settings)
- Test (create): `test/controllers/transactions/recurrences_controller_test.rb`

**Interfaces:**
- Consumes: `RecurrenceParams`, `RecurringTransaction.build_from_entry`, `.create_from_entry!`, `.ineligibility_reason`, `::GENERIC_ERROR`, `recurring_status_text`, `transactions/recurrence_fields` partial, `preview_recurring_transactions_path(entry_id:)`.
- Produces:
  - Routes: `transaction_recurrence_path(entry)` (GET show = closed step; POST create), `new_transaction_recurrence_path(entry)` (GET fields; with `recurrence[...]` = review).
  - All steps render inside `<turbo-frame id="<%= dom_id(entry, :recurrence) %>">` (`transactions/recurrences/recurrence` partial, locals `(entry:, step:, recurrence: nil, error: nil, autofocus: false)`, steps `:closed`, `:fields`, `:confirm`).
  - Success: turbo stream replaces `drawer` (re-render of `transactions/show` with `@focus_provenance = true`) and the row (`turbo_stream.replace(@entry)`), plus notice. Failure: 422 confirm step with a `role="alert"` error (`b3.err.*`), never 500.
  - `recurrence_block_state(entry) -> :editable | :one_time | :linked | nil` (interaction §3.1; `:linked` follows the canvas/D14: status + "Edit" that opens the plan dialog).
- Flow (server-driven, Hotwire-first): closed → **Edit** link (frame GET) → fields (`autofocus` on the checked radio) → **Review** (GET form) → confirm (`autofocus` on the `h4 tabindex="-1"`) → **Split into N installments / Start monthly charge** (POST). **Cancel** links (fields and confirm) GET `transaction_recurrence_path` → closed with `autofocus` on Edit.

- [ ] **Step 1: Write the failing tests** — create `test/controllers/transactions/recurrences_controller_test.rb`:

```ruby
require "test_helper"

class Transactions::RecurrencesControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper, ActionView::RecordIdentifier

  setup do
    travel_to Date.new(2026, 10, 8)
    sign_in users(:family_admin)
    @card = accounts(:credit_card)
    @card.entries.delete_all
    @entry = create_transaction(account: @card, amount: 3000, name: "Laptop", date: Date.new(2026, 8, 20))
    @frame = { "Turbo-Frame" => dom_id(@entry, :recurrence) }
    @installments = { plan_type: "installments", total_payments: "3", start_date: "2026-08-25" }
  end

  test "opens the fields with Doesn't repeat selected" do
    get new_transaction_recurrence_url(@entry), headers: @frame

    assert_response :success
    assert_includes response.body, ERB::Util.html_escape("Doesn't repeat")
    assert_includes response.body, "Review"
  end

  test "review shows field errors without saving" do
    get new_transaction_recurrence_url(@entry), params: { recurrence: @installments.merge(total_payments: "60") }, headers: @frame

    assert_response :unprocessable_entity
    assert_includes response.body, "Enter 2 to 48 installments."
  end

  test "review confirms what will change" do
    get new_transaction_recurrence_url(@entry), params: { recurrence: @installments }, headers: @frame

    assert_response :success
    assert_includes response.body, "Split $3,000.00 into 3 installments"
    assert_includes response.body, "Your card balance stays the same."
    assert_includes response.body, "Adds 2 past installments with their original dates. Past budgets will change."
  end

  test "converts the purchase and refreshes the drawer" do
    assert_difference "RecurringTransaction.count", 1 do
      post transaction_recurrence_url(@entry), params: { recurrence: @installments },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, %(target="drawer")
    assert @entry.reload.transaction.msi_purchase?
    assert_equal 2, @entry.transaction.recurring_transaction.transactions.where(kind: "installment").count
  end

  test "explains why a transfer can't repeat" do
    payment = create_transaction(account: @card, amount: 500, kind: "cc_payment")

    assert_no_difference "RecurringTransaction.count" do
      post transaction_recurrence_url(payment), params: { recurrence: { plan_type: "charge" } },
           headers: { "Turbo-Frame" => dom_id(payment, :recurrence) }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, ERB::Util.html_escape("Transfers can't repeat.")
  end

  test "cancel returns to the closed block" do
    get transaction_recurrence_url(@entry), headers: @frame

    assert_response :success
    assert_includes response.body, "One time"
    assert_includes response.body, %(aria-label="Edit recurring payment")
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/transactions/recurrences_controller_test.rb`
Expected: ERROR — no route `new_transaction_recurrence_url`.

- [ ] **Step 3: Implement**

`config/routes.rb` — inside `resources :transactions ... do` (after `resource :category ...`, line 131):

```ruby
    resource :recurrence, only: %i[show new create], module: :transactions
```

Create `app/controllers/transactions/recurrences_controller.rb`:

```ruby
# B3: turn an existing transaction into a recurring payment, inline in its drawer
class Transactions::RecurrencesController < ApplicationController
  include RecurrenceParams

  before_action :set_entry

  def show
    render_step :closed
  end

  def new
    unless recurrence_requested?
      @recurrence = RecurringTransaction.build_from_entry(@entry, plan_type: nil)
      return render_step(:fields)
    end

    @recurrence = RecurringTransaction.build_from_entry(@entry, **recurrence_attributes)

    if @recurrence.valid?
      render_step :confirm
    else
      render_step :fields, status: :unprocessable_entity
    end
  end

  def create
    @recurrence = RecurringTransaction.create_from_entry!(@entry, **recurrence_attributes)
    @entry.reload
    @focus_provenance = true
    flash.now[:notice] = recurrence_notice(@recurrence)

    render turbo_stream: [
      turbo_stream.replace("drawer", template: "transactions/show"),
      turbo_stream.replace(@entry),
      *flash_notification_stream_items
    ]
  rescue ActiveRecord::RecordInvalid => e
    @recurrence = RecurringTransaction.build_from_entry(@entry, **recurrence_attributes)
    render_step :confirm, status: :unprocessable_entity,
                error: e.record.errors.map(&:message).first || RecurringTransaction::GENERIC_ERROR
  rescue StandardError => e
    Rails.logger.error("Recurring conversion failed for entry #{@entry.id}: #{e.class}: #{e.message}")
    Sentry.capture_exception(e)
    @recurrence = RecurringTransaction.build_from_entry(@entry, **recurrence_attributes)
    render_step :confirm, status: :unprocessable_entity, error: RecurringTransaction::GENERIC_ERROR
  end

  private
    def set_entry
      @entry = Current.family.entries.find(params[:transaction_id])
    end

    def render_step(step, status: :ok, error: nil)
      render partial: "transactions/recurrences/recurrence",
             locals: { entry: @entry, step: step, recurrence: @recurrence, error: error, autofocus: step != :confirm },
             status: status
    end
end
```

Append inside `RecurringTransactionsHelper`:

```ruby
  # Which "Recurring payment" block the drawer's Settings shows (interaction §3.1 + canvas D14)
  def recurrence_block_state(entry)
    transaction = entry.transaction
    return :linked if transaction.recurring_transaction
    return nil if entry.amount.negative? || transaction.transfer? || transaction.transfer.present?
    return nil unless entry.account.manual? && entry.account.active?
    return :one_time if transaction.one_time?

    RecurringTransaction.ineligibility_reason(entry).nil? ? :editable : nil
  end
```

Create `app/views/transactions/recurrences/_recurrence.html.erb`:

```erb
<%# locals: (entry:, step:, recurrence: nil, error: nil, autofocus: false) %>

<%= turbo_frame_tag dom_id(entry, :recurrence) do %>
  <% case step %>
  <% when :closed %>
    <%= render "transactions/recurrences/closed", entry: entry, autofocus: autofocus %>
  <% when :fields %>
    <%= render "transactions/recurrences/fields", entry: entry, recurrence: recurrence, error: error, autofocus: autofocus %>
  <% when :confirm %>
    <%= render "transactions/recurrences/confirm", entry: entry, recurrence: recurrence, error: error %>
  <% end %>
<% end %>
```

Create `app/views/transactions/recurrences/_closed.html.erb` (canvas `Convert.dc.html` figures 1 and 6):

```erb
<%# locals: (entry:, autofocus: false) %>

<% state = recurrence_block_state(entry) %>
<% plan = entry.transaction.recurring_transaction %>

<% if state == :one_time %>
  <div class="p-3 text-sm space-y-1">
    <h4 class="text-primary">Recurring payment</h4>
    <p class="text-secondary">Turn off One-time Expense to set this up.</p>
  </div>
<% elsif state %>
  <div class="flex items-center justify-between gap-4 p-3">
    <div class="text-sm space-y-1">
      <h4 class="text-primary">Recurring payment</h4>
      <p class="text-secondary"><%= recurring_status_text(entry.transaction) %></p>
    </div>

    <%= render DS::Link.new(
      text: "Edit",
      icon: "pencil",
      variant: "outline",
      href: plan ? recurring_transaction_path(plan) : new_transaction_recurrence_path(entry),
      frame: (plan ? :modal : nil),
      autofocus: autofocus || nil,
      aria: { label: "Edit recurring payment" }
    ) %>
  </div>
<% end %>
```

Create `app/views/transactions/recurrences/_fields.html.erb` (canvas `Convert.dc.html` figures 2, 3, 5):

```erb
<%# locals: (entry:, recurrence:, error: nil, autofocus: false) %>

<% credit_card = entry.account.credit_card? %>
<% block_error = error || (recurrence && (recurrence.errors[:base] + recurrence.errors[:account]).first) %>

<div class="p-3">
  <h4 class="text-sm text-primary">Recurring payment</h4>

  <%= form_with url: new_transaction_recurrence_path(entry), method: :get,
        class: "mt-3 rounded-lg bg-container-inset p-3 space-y-3",
        data: {
          controller: "recurring-form",
          recurring_form_preview_url_value: preview_recurring_transactions_path(entry_id: entry.id),
          recurring_form_account_id_value: entry.account_id,
          recurring_form_credit_account_ids_value: credit_card ? [ entry.account_id ] : [],
          recurring_form_unavailable_text_value: "We couldn't calculate this. You can still save.",
          recurring_form_credit_only_text_value: "Installments only work on credit cards.",
          action: "input->recurring-form#schedulePreview change->recurring-form#schedulePreview"
        } do %>
    <% if block_error %>
      <div role="alert">
        <%= render DS::Alert.new(message: block_error, variant: :error) %>
      </div>
    <% end %>

    <%= render "transactions/recurrence_fields",
               recurrence: recurrence,
               installments_available: credit_card,
               default_first_payment: entry.date.next_month,
               show_base_error: false,
               autofocus_type: autofocus %>

    <div class="flex flex-col-reverse sm:flex-row sm:justify-end gap-2">
      <%= render DS::Link.new(text: "Cancel", variant: "ghost", href: transaction_recurrence_path(entry)) %>
      <%= render DS::Button.new(
        text: "Review",
        type: "submit",
        disabled: recurrence&.plan_type.blank?,
        aria: { label: "Review recurring payment" },
        data: { recurring_form_target: "review" }
      ) %>
    </div>
  <% end %>
</div>
```

Create `app/views/transactions/recurrences/_confirm.html.erb` (canvas `Convert.dc.html` figures 4, 5; copy `b3.confirm_*`):

```erb
<%# locals: (entry:, recurrence:, error: nil) %>

<% total = recurring_money(entry.amount.abs, entry.currency) %>
<% backfill = recurrence.backfill_count %>
<% noun = recurrence.installments? ? "installment" : "payment" %>

<div class="p-3">
  <h4 class="text-sm text-primary">Recurring payment</h4>

  <%= form_with url: transaction_recurrence_path(entry), method: :post, class: "mt-3 rounded-lg border border-tertiary p-3 space-y-3" do %>
    <% if error %>
      <div role="alert">
        <%= render DS::Alert.new(message: error, variant: :error) %>
      </div>
    <% end %>

    <%= hidden_field_tag "recurrence[plan_type]", recurrence.plan_type, id: nil %>
    <%= hidden_field_tag "recurrence[total_payments]", recurrence.total_payments, id: nil %>
    <% if recurrence.installments? && recurrence.start_date %>
      <%= hidden_field_tag "recurrence[start_date]", recurrence.start_date.iso8601, id: nil %>
    <% end %>

    <h4 tabindex="-1" autofocus class="text-sm font-medium text-primary tabular-nums rounded outline-none focus-visible:ring-4 focus-visible:ring-alpha-black-200">
      <% if recurrence.installments? %>
        Split <%= total %> into <%= recurrence.total_payments %> installments
      <% else %>
        Repeat <%= total %> every month
      <% end %>
    </h4>

    <ul class="list-disc pl-5 space-y-1 text-sm text-secondary tabular-nums">
      <% if recurrence.installments? %>
        <li>Your card balance stays the same.</li>
      <% end %>
      <% if backfill.positive? %>
        <li>Adds <%= backfill %> past <%= noun.pluralize(backfill) %> with their original dates. Past budgets will change.</li>
      <% end %>
    </ul>

    <div class="flex flex-col-reverse sm:flex-row sm:justify-end gap-2">
      <%= render DS::Link.new(text: "Cancel", variant: "outline", href: transaction_recurrence_path(entry)) %>
      <%= render DS::Button.new(
        text: recurrence.installments? ? "Split into #{recurrence.total_payments} installments" : "Start monthly charge",
        type: "submit"
      ) %>
    </div>
  <% end %>
</div>
```

`app/views/transactions/show.html.erb` — inside the Settings section, as the first child of the first `<div class="pb-4">` (before the Exclude form, line 103):

```erb
        <% if recurrence_block_state(@entry) %>
          <%= render "transactions/recurrences/recurrence", entry: @entry, step: :closed %>
        <% end %>
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: 6 runs, 0 failures. If the ERB heading renders with extra whitespace, the `assert_includes` for "Split $3,000.00 into 3 installments" still matches because the text is on one line.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop config/routes.rb app/controllers/transactions/recurrences_controller.rb app/helpers/recurring_transactions_helper.rb test/controllers/transactions/recurrences_controller_test.rb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/transactions/recurrences/_recurrence.html.erb app/views/transactions/recurrences/_closed.html.erb app/views/transactions/recurrences/_fields.html.erb app/views/transactions/recurrences/_confirm.html.erb app/views/transactions/show.html.erb -a
git add config/routes.rb app/controllers/transactions/recurrences_controller.rb app/helpers/recurring_transactions_helper.rb app/views/transactions/recurrences app/views/transactions/show.html.erb test/controllers/transactions/recurrences_controller_test.rb
git commit -m "Convert an existing transaction into a recurring payment from its drawer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---
### Task 13: Plan dialog — view, edit, stop (C3)

**Files:**
- Modify: `app/controllers/recurring_transactions_controller.rb` (add `show`, `update`, `stop`)
- Create: `app/views/recurring_transactions/show.html.erb`
- Modify: `app/helpers/recurring_transactions_helper.rb` (add `recurring_plan_subtitle_parts`)
- Test: `test/controllers/recurring_transactions_controller_test.rb`

**Interfaces:**
- Consumes: routes (Task 9), `CustomConfirm.for_plan_stop` / `.for_plan_edit` (Task 7), `recurring_plan_state`, `recurring_money` (Task 9), schedule lock (Task 2).
- Produces: `GET /recurring_transactions/:id` → `DS::Dialog` (frame `modal`, `reload_on_close: true`); `PATCH /recurring_transactions/:id` (name, category; amount for charges only) → turbo stream replacing `modal` + notice `c3.saved_notice` ("Changes saved."), 422 re-render on errors; `PATCH /recurring_transactions/:id/stop` → `cancel!`, turbo stream + notice `c3.stopped_notice` ("{name} stopped."). Stopped/completed plans render read-only (no Save, no Stop). Focus on open: the dialog title (`h2 tabindex="-1" autofocus`). Canvas: `Dialogs.dc.html`.

- [ ] **Step 1: Write the failing tests** — append inside `RecurringTransactionsControllerTest`:

```ruby
  test "shows a plan with a safe stop confirm" do
    plan = create_charge

    get recurring_transaction_url(plan), headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_includes response.body, "Netflix"
    assert_includes response.body, "Save changes"
    assert_includes response.body, "Stop payments"
    assert_includes response.body, "Keep it"
  end

  test "saves a charge's name and amount for future payments" do
    plan = create_charge

    patch recurring_transaction_url(plan), params: { recurring_transaction: { name: "Netflix Premium", amount: "349" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal "Netflix Premium", plan.reload.name
    assert_equal BigDecimal("349"), plan.amount
    assert_includes response.body, "Changes saved."
  end

  test "never changes an installment plan's total" do
    purchase = create_transaction(account: @card, amount: 1200, name: "Desk", date: Date.new(2026, 10, 1))
    plan = RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 3)

    patch recurring_transaction_url(plan), params: { recurring_transaction: { name: "Standing desk", amount: "1" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal "Standing desk", plan.reload.name
    assert_equal BigDecimal("1200"), plan.amount
  end

  test "stops a plan" do
    plan = create_charge

    patch stop_recurring_transaction_url(plan), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal "cancelled", plan.reload.status
    assert_includes response.body, "Netflix stopped."
  end

  test "plans from other families are not found" do
    get recurring_transaction_url(SecureRandom.uuid), headers: { "Turbo-Frame" => "modal" }

    assert_response :not_found
  end

  private
    def create_charge
      families(:dylan_family).recurring_transactions.create!(
        account: @card, name: "Netflix", plan_type: "charge", amount: 299, currency: "USD", start_date: Date.new(2026, 10, 12)
      )
    end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/recurring_transactions_controller_test.rb`
Expected: the 5 new tests ERROR (`AbstractController::ActionNotFound` / missing template).

- [ ] **Step 3: Implement**

`app/controllers/recurring_transactions_controller.rb` — add below `include RecurrenceParams`:

```ruby
  before_action :set_recurring_transaction, only: %i[show update stop]

  def show
  end

  # Only name and category (and a charge's amount) can change; past payments never do
  def update
    if @recurring_transaction.update(recurring_transaction_params)
      flash.now[:notice] = "Changes saved."
      render_dialog
    else
      render :show, status: :unprocessable_entity
    end
  end

  def stop
    @recurring_transaction.cancel!
    flash.now[:notice] = "#{@recurring_transaction.name} stopped."
    render_dialog
  end
```

and in `private`:

```ruby
    def set_recurring_transaction
      @recurring_transaction = Current.family.recurring_transactions.includes(:account, :category).find(params[:id])
    end

    def recurring_transaction_params
      permitted = params.require(:recurring_transaction).permit(:name, :category_id, :amount)
      permitted.delete(:amount) unless @recurring_transaction.charge?
      if permitted[:category_id].present? && !Current.family.categories.exists?(permitted[:category_id])
        permitted[:category_id] = nil
      end
      permitted
    end

    def render_dialog
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("modal", template: "recurring_transactions/show"),
            *flash_notification_stream_items
          ]
        end
        format.html { redirect_to recurring_transaction_path(@recurring_transaction), notice: flash.now[:notice] }
      end
    end
```

Append inside `RecurringTransactionsHelper`:

```ruby
  # c3.subtitle_installments / c3.subtitle_charge, joined by an aria-hidden "·" in the view
  def recurring_plan_subtitle_parts(plan)
    state_icon, state_text = recurring_plan_state(plan)
    state = state_icon ? safe_join([ icon(state_icon, size: "xs", color: "current"), state_text ]) : state_text

    if plan.installments?
      [ "#{plan.total_payments} installments of #{recurring_money(plan.occurrence_amount(1), plan.currency)}", state ]
    else
      [ "Monthly charge", recurring_money(plan.amount, plan.currency), state ]
    end
  end
```

Create `app/views/recurring_transactions/show.html.erb`:

```erb
<% plan = @recurring_transaction %>
<% editable = plan.status == "active" %>

<%= render DS::Dialog.new(reload_on_close: true) do |dialog| %>
  <% dialog.with_header(hide_close_icon: true) do %>
    <div class="flex items-start justify-between gap-2">
      <div class="min-w-0">
        <h2 tabindex="-1" autofocus class="text-lg font-medium text-primary rounded outline-none focus-visible:ring-4 focus-visible:ring-alpha-black-200"><%= plan.name %></h2>
        <p class="text-sm text-secondary tabular-nums flex flex-wrap items-center gap-x-1">
          <% recurring_plan_subtitle_parts(plan).each_with_index do |part, index| %>
            <% if index.positive? %><span aria-hidden="true">·</span><% end %>
            <span class="inline-flex items-center gap-1"><%= part %></span>
          <% end %>
        </p>
      </div>

      <%= render DS::Button.new(variant: "icon", icon: "x", class: "shrink-0", type: "button",
            data: { action: "DS--dialog#close" }, aria: { label: "Close" }) %>
    </div>
  <% end %>

  <% dialog.with_body do %>
    <div class="space-y-4 pb-4">
      <% if editable && plan.installments? %>
        <% paid = plan.last_handled_number %>
        <% paid_percent = (paid * 100.0 / plan.total_payments).round(2) %>
        <div>
          <div class="flex h-1.5 mb-3 gap-1" aria-hidden="true">
            <div class="rounded-md h-1.5 bg-inverse" style="width: <%= paid_percent %>%"></div>
            <div class="rounded-md h-1.5 bg-surface-inset" style="width: <%= 100 - paid_percent %>%"></div>
          </div>
          <div class="flex justify-between text-sm tabular-nums">
            <p class="text-secondary"><%= paid %> of <%= plan.total_payments %> paid</p>
            <p class="text-primary font-medium text-right"><%= recurring_money(plan.remaining_balance, plan.currency) %> left</p>
          </div>
        </div>
      <% end %>

      <% if editable %>
        <%= styled_form_with model: plan, url: recurring_transaction_path(plan), method: :patch, class: "space-y-4" do |f| %>
          <% if plan.errors.any? %>
            <%= render "shared/form_errors", model: plan %>
          <% end %>

          <div class="space-y-2">
            <%= f.text_field :name, label: "Name", required: true %>
            <%= f.collection_select :category_id, Current.family.categories.expenses.alphabetically, :id, :name,
                  { label: "Category", include_blank: "Uncategorized" } %>
            <% if plan.charge? %>
              <%= f.money_field :amount, label: "Amount", required: true, disable_currency: true %>
            <% end %>
          </div>

          <% if plan.installments? %>
            <div class="flex items-start gap-3 rounded-lg border border-tertiary p-3">
              <%= icon "lock" %>
              <p class="text-sm text-secondary">To change installments or dates, delete the purchase and add it again.</p>
            </div>
          <% end %>

          <%= render DS::Button.new(
            text: "Save changes",
            type: "submit",
            full_width: true,
            confirm: (CustomConfirm.for_plan_edit(plan) if plan.last_handled_number.positive?)
          ) %>
        <% end %>

        <div class="border-t border-divider pt-4">
          <%= render DS::Button.new(
            text: "Stop payments",
            variant: "outline-destructive",
            href: stop_recurring_transaction_path(plan),
            method: :patch,
            confirm: CustomConfirm.for_plan_stop(plan)
          ) %>
        </div>
      <% else %>
        <dl class="space-y-3 text-sm">
          <div class="flex justify-between gap-4">
            <dt class="text-secondary">Category</dt>
            <dd class="text-primary font-medium text-right"><%= plan.category&.name || "Uncategorized" %></dd>
          </div>
          <div class="flex justify-between gap-4">
            <dt class="text-secondary">Account</dt>
            <dd class="text-primary font-medium text-right"><%= plan.account.name %></dd>
          </div>
        </dl>
      <% end %>
    </div>
  <% end %>
<% end %>
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: all tests in the file pass.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/controllers/recurring_transactions_controller.rb app/helpers/recurring_transactions_helper.rb test/controllers/recurring_transactions_controller_test.rb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/recurring_transactions/show.html.erb -a
git add app/controllers/recurring_transactions_controller.rb app/helpers/recurring_transactions_helper.rb app/views/recurring_transactions/show.html.erb test/controllers/recurring_transactions_controller_test.rb
git commit -m "Add the recurring payment dialog to view, edit and stop a plan

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Generated rows explain themselves (C1 list row + drawer)

**Files:**
- Modify: `app/views/transactions/_transaction.html.erb:74-85`
- Create: `app/views/transactions/_provenance.html.erb`
- Modify: `app/views/transactions/show.html.erb` (body top, Overview amount/nature, full Settings section)
- Modify: `app/controllers/transactions_controller.rb:18-22` (index `includes`)
- Test: `test/controllers/transactions_controller_test.rb`

**Interfaces:**
- Consumes: `recurring_icon`, `recurring_provenance_label`, `recurrence_block_state` (Tasks 9, 12), `CustomConfirm.for_msi_purchase_deletion` / `.for_occurrence_deletion` (Task 7), `@focus_provenance` (Task 12), the Settings alert (Task 8).
- Produces:
  - List row: provenance line on every width — `icon` + `[account · ]` (account only `lg:`) + `c1.*_line` + "View plan" (`aria-label="View plan for {name}"`, frame `modal`). Rows without a plan keep today's `hidden lg:block` account line.
  - Drawer: `#<dom_id(entry, :provenance)>` block above Overview (`tabindex="-1"`, `autofocus` after a conversion): installment/charge row = one line + "View plan"; `msi_purchase` = label + `c1.drawer_msi_purchase` + "View plan" (canvas `Rows.dc.html`).
  - Locked kinds (`msi_purchase`, `installment`, judged on `kind_in_database`): Type and Amount stacked full width and `disabled`, with `c1.locked_amount_help_installment` / `_msi` via `aria-describedby`; Settings hides Exclude, One-time and "Transfer or Debt Payment?".
  - Delete: `msi_purchase` → subtitle `c3.delete_msi_subtitle` + `for_msi_purchase_deletion`; any other plan row → `for_occurrence_deletion`; others unchanged.

- [ ] **Step 1: Write the failing tests** — append inside `TransactionsControllerTest`:

```ruby
  test "the drawer explains a generated installment and locks its amount" do
    travel_to Date.new(2026, 10, 8)
    installment = create_installment_plan.transactions.find_by(installment_number: 1).entry

    get transaction_url(installment), headers: { "Turbo-Frame" => "drawer" }

    assert_response :success
    assert_includes response.body, "Installment 1 of 3"
    assert_includes response.body, "Set by the plan."
    assert_includes response.body, "View plan for Laptop"
    assert_not_includes response.body, "One-time Expense"
    assert_not_includes response.body, "Open matcher"
  end

  test "the list explains generated rows" do
    travel_to Date.new(2026, 10, 8)
    create_installment_plan

    get transactions_url(q: { search: "Laptop" }), headers: { "Turbo-Frame" => "transactions" }

    assert_response :success
    assert_includes response.body, "Paid in 3 installments"
    assert_includes response.body, "Installment 1 of 3"
  end
```

and in the test class's `private` section:

```ruby
    def create_installment_plan
      card = accounts(:credit_card)
      purchase = create_transaction(account: card, amount: 3000, name: "Laptop", date: Date.new(2026, 8, 20))
      RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 3)
    end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/transactions_controller_test.rb`
Expected: the 2 new tests FAIL (no provenance text; One-time toggle still present).

- [ ] **Step 3: Implement**

`app/controllers/transactions_controller.rb` index `includes` (lines 18-22):

```ruby
                       .includes(
                         { entry: :account },
                         :category, :merchant, :tags, :recurring_transaction,
                         :transfer_as_inflow, :transfer_as_outflow
                       )
```

`app/views/transactions/_transaction.html.erb` — replace lines 74-85 (the `<div class="text-secondary text-xs font-normal hidden lg:block">…</div>`) with:

```erb
                <% plan = transaction.recurring_transaction %>
                <% if plan %>
                  <p class="text-secondary text-xs font-normal flex items-start gap-1">
                    <%= icon recurring_icon(plan), size: "xs", class: "mt-0.5" %>
                    <span class="min-w-0">
                      <span class="hidden lg:inline">
                        <%= link_to entry.account.name,
                            account_path(entry.account, tab: "transactions"),
                            data: { turbo_frame: "_top" },
                            class: "hover:underline" %>
                        <span aria-hidden="true">·</span>
                      </span>
                      <%= recurring_provenance_label(transaction) %>
                      <%= link_to "View plan",
                          recurring_transaction_path(plan),
                          class: "text-primary font-medium hover:underline whitespace-nowrap",
                          aria: { label: "View plan for #{plan.name}" },
                          data: { turbo_frame: :modal } %>
                    </span>
                  </p>
                <% else %>
                  <div class="text-secondary text-xs font-normal hidden lg:block">
                    <% if transaction.transfer? %>
                      <span class="text-secondary">
                        <%= transaction.loan_payment? ? "Loan Payment" : "Transfer" %> • <%= entry.account.name %>
                      </span>
                    <% else %>
                      <%= link_to entry.account.name,
                          account_path(entry.account, tab: "transactions"),
                          data: { turbo_frame: "_top" },
                          class: "hover:underline" %>
                    <% end %>
                  </div>
                <% end %>
```

Create `app/views/transactions/_provenance.html.erb`:

```erb
<%# locals: (entry:, plan:, focus: false) %>

<% transaction = entry.transaction %>
<% view_plan = DS::Link.new(text: "View plan", variant: "outline", size: "sm", href: recurring_transaction_path(plan),
                            frame: :modal, aria: { label: "View plan for #{plan.name}" }) %>
<% focus_classes = "outline-none focus-visible:ring-4 focus-visible:ring-alpha-black-200" %>

<% if transaction.msi_purchase? %>
  <%= tag.div id: dom_id(entry, :provenance), tabindex: "-1", autofocus: focus || nil,
              class: "mb-4 flex items-start gap-3 rounded-lg border border-tertiary p-3 #{focus_classes}" do %>
    <%= icon "credit-card" %>
    <div class="text-sm space-y-3 min-w-0">
      <p class="text-primary font-medium"><%= recurring_provenance_label(transaction) %></p>
      <p class="text-secondary -mt-2">Adds to your card balance, not to spending. Each installment counts as spending.</p>
      <%= render view_plan %>
    </div>
  <% end %>
<% else %>
  <%= tag.div id: dom_id(entry, :provenance), tabindex: "-1", autofocus: focus || nil,
              class: "mb-4 flex items-center justify-between gap-3 rounded-lg border border-tertiary p-3 #{focus_classes}" do %>
    <div class="flex items-center gap-3 min-w-0">
      <%= icon recurring_icon(plan) %>
      <p class="text-sm text-primary font-medium"><%= recurring_provenance_label(transaction) %></p>
    </div>
    <%= render view_plan %>
  <% end %>
<% end %>
```

`app/views/transactions/show.html.erb`:

1. Right after `<% dialog.with_body do %>` (line 6), before the Overview section:

```erb
    <% plan = @entry.transaction.recurring_transaction %>
    <% locked = Transaction::PLAN_LOCKED_KINDS.include?(@entry.transaction.kind_in_database) %>

    <% if plan %>
      <%= render "transactions/provenance", entry: @entry, plan: plan, focus: @focus_provenance %>
    <% end %>
```

2. Replace the Type/Amount block (lines 25-38, the `<div class="flex items-center gap-2">…</div>`) with:

```erb
            <% if locked %>
              <% help_id = dom_id(@entry, :locked_amount_help) %>
              <div class="flex flex-col gap-1">
                <div class="flex flex-col gap-2">
                  <%= f.select :nature,
                        [["Expense", "outflow"], ["Income", "inflow"]],
                        { label: t(".nature"), selected: @entry.amount.negative? ? "inflow" : "outflow" },
                        { disabled: true, "aria-describedby": help_id } %>
                  <%= f.text_field :amount, label: t(".amount"), value: format_money(@entry.amount_money.abs),
                        disabled: true, class: "form-field__input tabular-nums", "aria-describedby": help_id %>
                </div>
                <p id="<%= help_id %>" class="text-xs text-secondary flex items-start gap-1">
                  <%= icon "lock", size: "xs", class: "mt-0.5" %>
                  <span><%= @entry.transaction.msi_purchase? ? "To change it, delete this purchase and add it again." : "Set by the plan." %></span>
                </p>
              </div>
            <% else %>
              <div class="flex items-center gap-2">
                <%= f.select :nature,
                      [["Expense", "outflow"], ["Income", "inflow"]],
                      { container_class: "w-1/3", label: t(".nature"), selected: @entry.amount.negative? ? "inflow" : "outflow" },
                      { data: { "auto-submit-form-target": "auto" }, disabled: @entry.linked? } %>

                <%= f.money_field :amount, label: t(".amount"),
                      container_class: "w-2/3",
                      auto_submit: true,
                      min: 0,
                      value: @entry.amount.abs,
                      disabled: @entry.linked?,
                      disable_currency: @entry.linked? %>
              </div>
            <% end %>
```

3. Replace the whole Settings section (from `<% dialog.with_section(title: t(".settings")…) do %>` to its `<% end %>`, which by now contains Task 8's alert and Task 12's block) with:

```erb
    <% dialog.with_section(title: t(".settings"), open: @entry.errors.any?) do %>
      <% if @entry.errors.any? %>
        <div role="alert" class="pb-4">
          <%= render DS::Alert.new(message: @entry.errors.map(&:message).uniq.to_sentence, variant: :error) %>
        </div>
      <% end %>

      <div class="pb-4">
        <% if recurrence_block_state(@entry) %>
          <%= render "transactions/recurrences/recurrence", entry: @entry, step: :closed %>
        <% end %>

        <% unless locked %>
          <%= styled_form_with model: @entry,
                url: transaction_path(@entry),
                class: "p-3",
                data: { controller: "auto-submit-form" } do |f| %>
            <div class="flex cursor-pointer items-center gap-4 justify-between">
              <div class="text-sm space-y-1">
                <h4 class="text-primary">Exclude</h4>
                <p class="text-secondary">Excluded transactions will be removed from budgeting calculations and reports.</p>
              </div>

              <%= f.toggle :excluded, { data: { auto_submit_form_target: "auto" } } %>
            </div>
          <% end %>
        <% end %>
      </div>

      <div class="pb-4">
        <% unless locked %>
          <%= styled_form_with model: @entry,
                url: transaction_path(@entry),
                class: "p-3",
                data: { controller: "auto-submit-form" } do |f| %>
            <%= f.fields_for :entryable do |ef| %>
              <div class="flex cursor-pointer items-center gap-4 justify-between">
                <div class="text-sm space-y-1">
                  <h4 class="text-primary">One-time <%= @entry.amount.negative? ? "Income" : "Expense" %></h4>
                  <p class="text-secondary">One-time transactions will be excluded from certain budgeting calculations and reports to help you see what's really important.</p>
                </div>

                <%= ef.toggle :kind, {
                      checked: @entry.transaction.one_time?,
                      data: { auto_submit_form_target: "auto" }
                    }, "one_time", "standard" %>
              </div>
            <% end %>
          <% end %>

          <div class="flex items-center justify-between gap-4 p-3">
            <div class="text-sm space-y-1">
              <h4 class="text-primary">Transfer or Debt Payment?</h4>
              <p class="text-secondary">Transfers and payments are special types of transactions that indicate money movement between 2 accounts.</p>
            </div>

            <%= render DS::Link.new(
              text: "Open matcher",
              icon: "arrow-left-right",
              variant: "outline",
              href: new_transaction_transfer_match_path(@entry),
              frame: :modal
            ) %>
          </div>
        <% end %>

        <% delete_confirm, delete_subtitle =
             if @entry.transaction.msi_purchase? && plan
               [ CustomConfirm.for_msi_purchase_deletion(@entry), "Also deletes its #{plan.total_payments} installments." ]
             elsif plan
               [ CustomConfirm.for_occurrence_deletion(@entry), t(".delete_subtitle") ]
             else
               [ CustomConfirm.for_resource_deletion("transaction"), t(".delete_subtitle") ]
             end %>

        <!-- Delete Transaction Form -->
        <div class="flex items-center justify-between gap-2 p-3">
          <div class="text-sm space-y-1 min-w-0">
            <h4 class="text-primary"><%= t(".delete_title") %></h4>
            <p class="text-secondary"><%= delete_subtitle %></p>
          </div>

          <%= render DS::Button.new(
            text: t(".delete"),
            variant: "outline-destructive",
            class: "shrink-0",
            href: entry_path(@entry),
            method: :delete,
            confirm: delete_confirm,
            frame: "_top"
          ) %>
        </div>
      </div>
    <% end %>
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command, plus `test/controllers/transactions/recurrences_controller_test.rb` (its success stream re-renders `show`). Expected: the new tests pass; no previously passing test fails.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/controllers/transactions_controller.rb test/controllers/transactions_controller_test.rb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/transactions/_transaction.html.erb app/views/transactions/_provenance.html.erb app/views/transactions/show.html.erb -a
git add app/controllers/transactions_controller.rb app/views/transactions/_transaction.html.erb app/views/transactions/_provenance.html.erb app/views/transactions/show.html.erb test/controllers/transactions_controller_test.rb
git commit -m "Explain generated rows and lock plan-owned fields

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: Credit card "Recurring payments" tab (C2) and the shared commitment list

**Files:**
- Modify: `app/components/UI/account_page.rb:39-58`, `app/components/UI/account_page.html.erb:14`
- Create: `app/views/credit_cards/tabs/_recurring.html.erb`
- Create: `app/views/recurring_transactions/_commitment_group.html.erb`, `app/views/recurring_transactions/_commitment_row.html.erb`
- Test (create): `test/components/ui/account_page_test.rb`, `test/controllers/credit_card_recurring_tab_test.rb`

**Interfaces:**
- Consumes: `Account#recurring_commitments` (Task 6), `Family::RecurringCommitments::Item` (Task 3), `recurring_*` helpers (Task 9).
- Produces:
  - `UI::AccountPage#tabs` → `[:activity, :recurring]` for credit cards (Activity stays first/default); `#tab_label(tab)` ("Recurring payments" for `:recurring`, else `humanize`); tab partials resolve via `accountable_type.underscore.pluralize` (`credit_cards/tabs/_recurring`).
  - Partial `recurring_transactions/commitment_group` locals `(date:, items:, compact: false, **row_options)`; partial `recurring_transactions/commitment_row` locals `(item:, avatar: true, account: false, view_plan: true, compact: false)`. Used by C2 Upcoming (avatar, no account, no View plan), C4 details (compact, no avatar, account link, View plan) and the future category drawer (avatar, View plan).
- Canvas: `Card.dc.html` (no warning in C2, D13/V16).

- [ ] **Step 1: Write the failing tests**

Create `test/components/ui/account_page_test.rb`:

```ruby
require "test_helper"

class UI::AccountPageTest < ActiveSupport::TestCase
  test "credit cards get a Recurring payments tab after Activity" do
    page = UI::AccountPage.new(account: accounts(:credit_card))

    assert_equal [ :activity, :recurring ], page.tabs
    assert_equal :activity, page.active_tab
    assert_equal "Recurring payments", page.tab_label(:recurring)
    assert_equal "Activity", page.tab_label(:activity)
  end

  test "other accounts keep their tabs" do
    assert_equal [ :activity ], UI::AccountPage.new(account: accounts(:depository)).tabs
    assert_equal [ :activity, :holdings ], UI::AccountPage.new(account: accounts(:investment)).tabs
  end
end
```

Create `test/controllers/credit_card_recurring_tab_test.rb`:

```ruby
require "test_helper"

class CreditCardRecurringTabTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 10, 8)
    sign_in users(:family_admin)
    @card = accounts(:credit_card)
    @card.entries.delete_all
  end

  test "shows the card's commitments" do
    purchase = create_transaction(account: @card, amount: 6000, name: "Sofa", date: Date.new(2026, 9, 15))
    RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 6)
    families(:dylan_family).recurring_transactions.create!(account: @card, name: "Netflix", plan_type: "charge",
                                                           amount: 299, currency: "USD", start_date: Date.new(2026, 10, 12))

    get account_url(@card, tab: "recurring"), headers: { "Turbo-Frame" => "account" }

    assert_response :success
    assert_includes response.body, "Committed per month"
    assert_includes response.body, "$1,299.00"
    assert_includes response.body, "Left on installments"
    assert_includes response.body, "Upcoming"
    assert_includes response.body, "Installment 1 of 6"
    assert_includes response.body, "See later months"
    assert_includes response.body, "Monthly charges"
  end

  test "an empty card says where recurring payments come from" do
    get account_url(@card, tab: "recurring"), headers: { "Turbo-Frame" => "account" }

    assert_includes response.body, "No recurring payments on this card"
    assert_includes response.body, "Add one when you create a transaction."
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/components/ui/account_page_test.rb test/controllers/credit_card_recurring_tab_test.rb`
Expected: FAIL — tabs are `[:activity]`; `tab_label` undefined.

- [ ] **Step 3: Implement**

`app/components/UI/account_page.rb` — replace `tabs` and `tab_content_for`, add `tab_label`:

```ruby
  TAB_LABELS = { recurring: "Recurring payments" }.freeze

  def tabs
    case account.accountable_type
    when "Investment"
      [ :activity, :holdings ]
    when "Property", "Vehicle", "Loan"
      [ :activity, :overview ]
    when "CreditCard"
      [ :activity, :recurring ]
    else
      [ :activity ]
    end
  end

  def tab_label(tab)
    TAB_LABELS.fetch(tab) { tab.to_s.humanize }
  end

  def tab_content_for(tab)
    case tab
    when :activity
      activity_feed
    when :holdings, :overview, :recurring
      # Accountable is responsible for implementing the partial in the correct folder
      render "#{account.accountable_type.underscore.pluralize}/tabs/#{tab}", account: account
    end
  end
```

`app/components/UI/account_page.html.erb:14`:

```erb
              <% nav.with_btn(id: tab, label: tab_label(tab), classes: "px-6") %>
```

Create `app/views/recurring_transactions/_commitment_row.html.erb`:

```erb
<%# locals: (item:, avatar: true, account: false, view_plan: true, compact: false) %>

<% plan = item.plan %>

<div class="<%= class_names("flex items-start py-3", compact ? "gap-2 px-3" : "gap-3 px-4") %>">
  <% if avatar %>
    <%= render DS::FilledIcon.new(variant: :text, text: plan.name, size: "sm", rounded: true) %>
  <% end %>

  <div class="min-w-0 grow">
    <p class="text-sm font-medium text-primary truncate"><%= plan.name %></p>
    <p class="text-xs text-secondary flex items-start gap-1">
      <%= icon recurring_icon(plan), size: "xs", class: "mt-0.5" %>
      <span class="min-w-0">
        <%= recurring_occurrence_label(plan, item.number) %>
        <% if account %>
          <span aria-hidden="true">·</span>
          <%= link_to plan.account.name, account_path(plan.account, tab: "recurring"),
                class: "hover:underline", data: { turbo_frame: "_top" } %>
        <% end %>
      </span>
    </p>
  </div>

  <div class="text-right shrink-0">
    <p class="text-sm font-medium text-primary tabular-nums"><%= recurring_money(item.amount, plan.currency) %></p>
    <% if view_plan %>
      <%= link_to "View plan", recurring_transaction_path(plan),
            class: "text-xs font-medium text-primary hover:underline",
            aria: { label: "View plan for #{plan.name}" },
            data: { turbo_frame: :modal } %>
    <% end %>
  </div>
</div>
```

Create `app/views/recurring_transactions/_commitment_group.html.erb` (anatomy of `entries/_entry_group`, V1):

```erb
<%# locals: (date:, items:, compact: false, **row_options) %>

<div class="bg-container-inset rounded-xl p-1">
  <h4 class="<%= class_names("py-2 flex items-center justify-between font-medium text-xs text-secondary", compact ? "px-3" : "px-4") %>">
    <span class="uppercase"><%= recurring_group_label(date) %> <span aria-hidden="true">·</span> <%= items.size %></span>
    <span class="tabular-nums">
      <span class="sr-only">Total for <%= date.strftime("%B %-d") %>: </span><%= recurring_money(items.sum(&:amount), items.first.plan.currency) %>
    </span>
  </h4>

  <ul class="bg-container shadow-border-xs rounded-lg">
    <% items.each_with_index do |item, index| %>
      <li>
        <% if index.positive? %>
          <%= render "shared/ruler" %>
        <% end %>
        <%= render "recurring_transactions/commitment_row", item: item, compact: compact, **row_options %>
      </li>
    <% end %>
  </ul>
</div>
```

Create `app/views/credit_cards/tabs/_recurring.html.erb` (copy `c2.*`):

```erb
<%# locals: (account:) %>

<% commitments = account.recurring_commitments %>
<% installment_plans = commitments.active_installment_plans %>
<% charge_plans = commitments.active_charge_plans %>
<% past_plans = commitments.past_plans %>
<% all_done = commitments.any? && installment_plans.empty? && charge_plans.empty? %>

<div class="bg-container p-5 shadow-border-xs rounded-xl space-y-5">
  <% if !commitments.any? %>
    <div class="flex flex-col items-center text-center gap-3 py-10">
      <span class="w-9 h-9 rounded-xl bg-container-inset flex items-center justify-center"><%= icon "repeat", size: "lg" %></span>
      <h2 class="text-sm font-medium text-primary">No recurring payments on this card</h2>
      <p class="text-sm text-secondary max-w-xs -mt-2">Add one when you create a transaction.</p>
      <%= render DS::Link.new(text: "New transaction", variant: "secondary", icon: "plus",
            href: new_transaction_path(account_id: account.id, nature: "outflow"), frame: :modal) %>
    </div>
  <% elsif all_done %>
    <div class="flex flex-col items-center text-center gap-3 py-6">
      <span class="w-9 h-9 rounded-xl bg-container-inset flex items-center justify-center"><%= icon "check", size: "lg" %></span>
      <h2 class="text-sm font-medium text-primary">Nothing left to pay</h2>
    </div>
  <% else %>
    <h2 class="font-medium text-lg">Recurring payments</h2>

    <dl class="<%= class_names("grid grid-cols-1 gap-1 bg-container-inset rounded-xl p-1", "md:grid-cols-3": installment_plans.any?) %>">
      <div class="bg-container shadow-border-xs rounded-lg p-4 flex flex-col gap-1">
        <dt class="text-sm text-secondary">Committed per month</dt>
        <dd class="text-2xl font-medium text-primary tabular-nums"><%= recurring_money(commitments.committed_per_month, account.currency) %></dd>
      </div>
      <% if installment_plans.any? %>
        <div class="bg-container shadow-border-xs rounded-lg p-4 flex flex-col gap-1">
          <dt class="text-sm text-secondary">Left on installments</dt>
          <dd class="text-2xl font-medium text-primary tabular-nums"><%= recurring_money(commitments.left_on_installments, account.currency) %></dd>
        </div>
        <div class="bg-container shadow-border-xs rounded-lg p-4 flex flex-col gap-1">
          <dt class="text-sm text-secondary">Last installment</dt>
          <dd class="text-2xl font-medium text-primary tabular-nums">
            <% last = commitments.last_installment_date %>
            <time datetime="<%= last.strftime("%Y-%m") %>" aria-label="<%= last.strftime("%B %Y") %>"><%= last.strftime("%b %Y") %></time>
          </dd>
        </div>
      <% end %>
    </dl>

    <section class="space-y-3" aria-labelledby="<%= dom_id(account, :recurring_upcoming) %>">
      <h3 id="<%= dom_id(account, :recurring_upcoming) %>" class="flex items-center gap-2 text-sm font-medium text-primary">
        <%= icon "calendar-clock", size: "sm" %>Upcoming
      </h3>

      <% commitments.upcoming.by_date.each do |date, items| %>
        <%= render "recurring_transactions/commitment_group", date: date, items: items, view_plan: false %>
      <% end %>

      <%= render DS::Link.new(text: "See later months", variant: "outline", icon: "arrow-right", icon_position: "right",
            full_width: true, href: budget_path(commitments.later_months_budget_param), frame: :_top,
            aria: { label: "See later months in your budget" }) %>
    </section>

    <% if installment_plans.any? %>
      <table class="w-full text-sm">
        <caption class="text-left text-sm font-medium text-primary mb-2">Installments</caption>
        <thead class="text-xs uppercase font-medium text-secondary">
          <tr class="bg-container-inset">
            <th scope="col" class="text-left font-medium px-4 py-2 rounded-l-lg">Purchase</th>
            <th scope="col" class="text-right font-medium px-4 py-2">Per month</th>
            <th scope="col" class="text-right font-medium px-4 py-2 hidden md:table-cell">Payments left</th>
            <th scope="col" class="text-right font-medium px-4 py-2 hidden md:table-cell">Left to pay</th>
            <th scope="col" class="text-right font-medium px-4 py-2 hidden md:table-cell">Ends</th>
            <th scope="col" class="px-4 py-2 rounded-r-lg"><span class="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody class="tabular-nums">
          <% installment_plans.each_with_index do |plan, index| %>
            <% left_count = "#{plan.remaining_payments} of #{plan.total_payments}" %>
            <% left_amount = recurring_money(plan.remaining_balance, plan.currency) %>
            <% ends = recurring_date(plan.end_date) %>
            <tr class="<%= "border-b border-divider" unless index == installment_plans.size - 1 %>">
              <td class="px-4 py-3 align-top">
                <p class="font-medium text-primary"><%= plan.name %></p>
                <p class="text-xs text-secondary md:hidden"><%= left_count %> <span aria-hidden="true">·</span> <%= left_amount %> <span aria-hidden="true">·</span> <%= ends %></p>
              </td>
              <td class="px-4 py-3 align-top text-right text-primary"><%= recurring_money(plan.monthly_amount, plan.currency) %></td>
              <td class="px-4 py-3 align-top text-right text-secondary hidden md:table-cell"><%= left_count %></td>
              <td class="px-4 py-3 align-top text-right text-primary hidden md:table-cell"><%= left_amount %></td>
              <td class="px-4 py-3 align-top text-right text-secondary hidden md:table-cell whitespace-nowrap"><%= ends %></td>
              <td class="px-4 py-3 align-top text-right">
                <%= link_to "View plan", recurring_transaction_path(plan), class: "text-primary font-medium hover:underline whitespace-nowrap",
                      aria: { label: "View plan for #{plan.name}" }, data: { turbo_frame: :modal } %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    <% end %>

    <% if charge_plans.any? %>
      <table class="w-full text-sm">
        <caption class="text-left text-sm font-medium text-primary mb-2">Monthly charges</caption>
        <thead class="text-xs uppercase font-medium text-secondary">
          <tr class="bg-container-inset">
            <th scope="col" class="text-left font-medium px-4 py-2 rounded-l-lg">Name</th>
            <th scope="col" class="text-right font-medium px-4 py-2">Per month</th>
            <th scope="col" class="text-right font-medium px-4 py-2 hidden md:table-cell">Next payment</th>
            <th scope="col" class="text-right font-medium px-4 py-2 hidden md:table-cell">Ends</th>
            <th scope="col" class="px-4 py-2 rounded-r-lg"><span class="sr-only">Actions</span></th>
          </tr>
        </thead>
        <tbody class="tabular-nums">
          <% charge_plans.each_with_index do |plan, index| %>
            <% next_date = plan.next_payment_date %>
            <% next_text = next_date ? recurring_date(next_date, short: true) : "" %>
            <% ends = plan.end_date ? recurring_date(plan.end_date) : "No end date" %>
            <tr class="<%= "border-b border-divider" unless index == charge_plans.size - 1 %>">
              <td class="px-4 py-3 align-top">
                <p class="font-medium text-primary"><%= plan.name %></p>
                <p class="text-xs text-secondary md:hidden"><%= next_text %> <span aria-hidden="true">·</span> <%= ends %></p>
              </td>
              <td class="px-4 py-3 align-top text-right text-primary"><%= recurring_money(plan.amount, plan.currency) %></td>
              <td class="px-4 py-3 align-top text-right text-secondary hidden md:table-cell"><%= next_text %></td>
              <td class="px-4 py-3 align-top text-right text-secondary hidden md:table-cell"><%= ends %></td>
              <td class="px-4 py-3 align-top text-right">
                <%= link_to "View plan", recurring_transaction_path(plan), class: "text-primary font-medium hover:underline whitespace-nowrap",
                      aria: { label: "View plan for #{plan.name}" }, data: { turbo_frame: :modal } %>
              </td>
            </tr>
          <% end %>
        </tbody>
      </table>
    <% end %>
  <% end %>

  <% if past_plans.any? %>
    <%= render DS::Disclosure.new(title: "Past plans (#{past_plans.size})", align: :left, open: all_done) do %>
      <div class="bg-container-inset rounded-xl p-1">
        <ul class="bg-container shadow-border-xs rounded-lg">
          <% past_plans.each_with_index do |plan, index| %>
            <% state_icon, state_text = recurring_plan_state(plan) %>
            <li>
              <% if index.positive? %>
                <%= render "shared/ruler" %>
              <% end %>
              <div class="flex items-center gap-3 px-4 py-3">
                <div class="min-w-0 grow">
                  <p class="text-sm font-medium text-primary"><%= plan.name %></p>
                  <p class="text-xs text-secondary"><%= plan.installments? ? "Installments" : "Monthly charge" %></p>
                </div>
                <p class="text-xs text-secondary flex items-center gap-1 shrink-0">
                  <%= icon state_icon, size: "xs", color: "current" %><span><%= state_text %></span>
                </p>
              </div>
            </li>
          <% end %>
        </ul>
      </div>
    <% end %>
  <% end %>
</div>
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: all pass. (`$1,299.00` = $1,000.00 installment + $299.00 charge.)

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop app/components/UI/account_page.rb test/components/ui/account_page_test.rb test/controllers/credit_card_recurring_tab_test.rb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/components/UI/account_page.html.erb app/views/credit_cards/tabs/_recurring.html.erb app/views/recurring_transactions/_commitment_group.html.erb app/views/recurring_transactions/_commitment_row.html.erb -a
git add app/components/UI/account_page.rb app/components/UI/account_page.html.erb app/views/credit_cards/tabs app/views/recurring_transactions/_commitment_group.html.erb app/views/recurring_transactions/_commitment_row.html.erb test/components/ui/account_page_test.rb test/controllers/credit_card_recurring_tab_test.rb
git commit -m "Show a credit card's recurring payments in their own tab

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16: Budget commitments block and B + A warning (C4)

**Files:**
- Create: `app/views/budgets/_recurring_commitments.html.erb`
- Modify: `app/views/budgets/show.html.erb:16-18` (render between the donut card and the tabs)
- Test (create): `test/controllers/budgets_controller_test.rb`

**Interfaces:**
- Consumes: `Budget#committed_spending(_money)`, `#commitments_percent`, `#commitments_over_budget?`, `#commitments_overage_money`, `#uses_reference_budget?`, `#basis_budget`, `#recurring_commitments`, `#past?`, `#future?` (Tasks 3-4); `recurring_transactions/commitment_group` (Task 15).
- Produces: block shown for the current and future months only (D10). Normal: `repeat` heading, `c4.line` figure, neutral bar, `c4.line_percent` (or `c4.line_percent_reference` + `w.ba.reference` when the month borrows a budget). Over: same header with a full `bg-destructive` bar and the percent, then `DS::Alert :warning` with only `w.ba.title` + `w.b.cta` "Review budget" (→ categories of this budget, or setup if it has none). "See details" (`c4.line_link`) lists the month's payments with the shared group/row. No commitments: nothing in the current month; `f.empty_title` box in future months. Canvas: `Budget.dc.html`.

- [ ] **Step 1: Write the failing test** — create `test/controllers/budgets_controller_test.rb`:

```ruby
require "test_helper"

class BudgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Date.new(2026, 10, 8)
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    @family.budgets.destroy_all
    accounts(:credit_card).entries.delete_all
    @family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                            currency: "USD", budgeted_spending: 1000, expected_income: 3000)
    @family.recurring_transactions.create!(account: accounts(:credit_card), name: "Rent", plan_type: "charge",
                                           amount: 1200, currency: "USD", start_date: Date.new(2026, 10, 5))
    @frame = { "Turbo-Frame" => "budget" }
  end

  test "the current month shows recurring commitments and the warning" do
    get budget_url("oct-2026"), headers: @frame

    assert_response :success
    assert_includes response.body, "committed to recurring payments"
    assert_includes response.body, "120% of your budget"
    assert_includes response.body, "Recurring payments are $200.00 over your October 2026 budget"
    assert_includes response.body, "Review budget"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/budgets_controller_test.rb`
Expected: FAIL — text not found.

- [ ] **Step 3: Implement**

Create `app/views/budgets/_recurring_commitments.html.erb`:

```erb
<%# locals: (budget:) %>

<% if budget.committed_spending.zero? %>
  <% if budget.future? %>
    <div class="bg-container rounded-xl shadow-border-xs p-4">
      <div class="flex items-start gap-3 rounded-lg border border-tertiary p-3">
        <%= icon "calendar-clock" %>
        <h3 class="text-sm text-primary">Nothing committed for <%= budget.name %> yet</h3>
      </div>
    </div>
  <% end %>
<% else %>
  <% percent = budget.commitments_percent %>
  <% over = budget.commitments_over_budget? %>
  <% reference = budget.uses_reference_budget? %>
  <% basis_name = budget.basis_budget&.name %>

  <section class="bg-container rounded-xl shadow-border-xs p-4 space-y-3" aria-labelledby="recurring-commitments-title">
    <h3 id="recurring-commitments-title" class="text-sm text-secondary flex items-center gap-1.5">
      <%= icon "repeat", size: "sm" %><span>Recurring payments</span>
    </h3>

    <p class="tabular-nums">
      <span class="block text-xl font-medium text-primary"><%= format_money(budget.committed_spending_money) %></span>
      <span class="block text-sm text-secondary">committed to recurring payments</span>
    </p>

    <% if percent %>
      <div class="flex h-1.5 gap-1" aria-hidden="true">
        <% if over %>
          <div class="rounded-md h-1.5 bg-destructive w-full"></div>
        <% else %>
          <div class="rounded-md h-1.5 bg-inverse" style="width: <%= percent %>%"></div>
          <div class="rounded-md h-1.5 bg-surface-inset" style="width: <%= 100 - percent %>%"></div>
        <% end %>
      </div>

      <% percent_text = reference ? "#{percent}% of your #{basis_name} budget" : "#{percent}% of your budget" %>

      <% if reference && !over %>
        <div class="space-y-1">
          <p class="text-sm text-primary font-medium tabular-nums"><%= percent_text %></p>
          <p class="text-xs text-secondary">Compared with your <%= basis_name %> budget. Set up <%= budget.name %> to use its own.</p>
        </div>
      <% else %>
        <p class="text-sm text-primary font-medium tabular-nums"><%= percent_text %></p>
      <% end %>

      <% if over %>
        <% alert_body = capture do %>
          <p class="font-medium text-pretty tabular-nums">Recurring payments are <%= format_money(budget.commitments_overage_money) %> over your <%= budget.name %> budget</p>
          <%= render DS::Link.new(
            text: "Review budget",
            variant: "outline",
            size: "sm",
            class: "mt-3",
            href: budget.initialized? ? budget_budget_categories_path(budget) : edit_budget_path(budget),
            aria: { label: "Review #{budget.name} budget" }
          ) %>
        <% end %>
        <%= render DS::Alert.new(message: alert_body, variant: :warning) %>
      <% end %>
    <% end %>

    <%= render DS::Disclosure.new(align: :left) do |disclosure| %>
      <% disclosure.with_summary_content do %>
        <div class="flex items-center gap-3">
          <%= icon "chevron-right", class: "group-open:transform group-open:rotate-90" %>
          <span class="font-medium text-sm text-primary">See<span class="sr-only"> recurring payment</span> details</span>
        </div>
      <% end %>

      <div class="space-y-2">
        <% budget.recurring_commitments.by_date.each do |date, items| %>
          <%= render "recurring_transactions/commitment_group", date: date, items: items,
                     compact: true, avatar: false, account: true %>
        <% end %>
      </div>
    <% end %>
  </section>
<% end %>
```

`app/views/budgets/show.html.erb` — after the donut card `</div>` (line 16) and before `<div>` (line 18):

```erb
      <% unless @budget.past? %>
        <%= render "budgets/recurring_commitments", budget: @budget %>
      <% end %>
```

- [ ] **Step 4: Run test to verify it passes**

Run the Step 2 command. Expected: 1 run, 0 failures. (Rent's Oct 5 occurrence isn't generated in the test — the job is only enqueued — so it counts as upcoming: $1,200 vs $1,000.)

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop test/controllers/budgets_controller_test.rb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/budgets/_recurring_commitments.html.erb app/views/budgets/show.html.erb -a
git add app/views/budgets/_recurring_commitments.html.erb app/views/budgets/show.html.erb test/controllers/budgets_controller_test.rb
git commit -m "Show recurring commitments and their warning in budgets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 17: Future budget screens

**Files:**
- Modify: `app/views/budgets/show.html.erb` (page title, tabs), `_budget_header.html.erb`, `_budget_donut.html.erb`, `_budgeted_summary.html.erb`, `edit.html.erb:43-63`
- Modify: `app/views/budget_categories/_budget_category.html.erb:46-52`, `app/views/budget_categories/show.html.erb:34, 90-140`
- Test: `test/controllers/budgets_controller_test.rb`

**Interfaces:**
- Consumes: `Budget#future?`, `#next_budget_param`, `#previous_budget_param`, `#committed_spending(_money)`, `#recurring_commitments` (Tasks 3-4), `recurring_date`, commitment partials (Tasks 9, 15).
- Produces (interaction §9.3, copy `f.*`, canvas `Future.dc.html`): `<title>` "{December 2026} budget"; chevrons with `aria-label` "Previous budget: {…}" / "Next budget: {…}", horizon chevron `aria-disabled` + label/title "You can plan up to 12 months ahead."; future chip "Starts {Nov 28}" (`calendar-clock`); donut "Committed" with `repeat` (also without a budget when something is committed); no Budgeted/Actual tabs in future months (Budgeted summary only when set up, Expected income without bar/"earned", "{$} committed"); category rows "{$} committed"; category drawer "Committed in {December 2026}" list or "Nothing committed in this category."; setup autofill "Start from your {October 2026} budget" / "Copies {October 2026}'s budget" when the source isn't the previous month.

- [ ] **Step 1: Write the failing tests** — append inside `BudgetsControllerTest`:

```ruby
  test "a future month shows what is committed, not spent" do
    get budget_url("dec-2026"), headers: @frame

    assert_response :success
    assert_includes response.body, "Committed"
    assert_includes response.body, "Starts"
    assert_includes response.body, "120% of your October 2026 budget"
    assert_includes response.body, %(aria-label="Previous budget: November 2026")
  end

  test "the last plannable month disables the next chevron with a reason" do
    get budget_url("oct-2027"), headers: @frame

    assert_response :success
    assert_includes response.body, "You can plan up to 12 months ahead."
  end

  test "months past the planning horizon are not found" do
    get budget_url("nov-2027"), headers: @frame

    assert_response :not_found
  end

  test "a future category drawer lists its commitments" do
    get budget_budget_category_url("dec-2026", BudgetCategory.uncategorized.id), headers: { "Turbo-Frame" => "drawer" }

    assert_response :success
    assert_includes response.body, "Committed in December 2026"
    assert_includes response.body, "Rent"
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/controllers/budgets_controller_test.rb`
Expected: 3 of the 4 new tests FAIL on missing copy (the 404 test already passes thanks to Task 4; keep it as a guard).

- [ ] **Step 3: Implement**

`app/views/budgets/show.html.erb` — first line:

```erb
<% title "#{@budget.name} budget" %>
```

and replace the tabs block (the `<div>` that wraps `if @budget.initialized? && @budget.available_to_allocate.positive?`) with:

```erb
      <div>
        <% if @budget.future? %>
          <%# No real spending in the future: no Budgeted / Actual tabs %>
          <% if @budget.initialized? %>
            <div class="bg-container rounded-xl shadow-border-xs">
              <%= render "budgets/budgeted_summary", budget: @budget %>
            </div>
          <% end %>
        <% elsif @budget.initialized? && @budget.available_to_allocate.positive? %>
          <%= render DS::Tabs.new(active_tab: params[:tab].presence || "budgeted") do |tabs| %>
            <% tabs.with_nav do |nav| %>
              <% nav.with_btn(id: "budgeted", label: "Budgeted") %>
              <% nav.with_btn(id: "actuals", label: "Actual") %>
            <% end %>

            <% tabs.with_panel(tab_id: "budgeted") do %>
              <div class="bg-container rounded-xl shadow-border-xs">
                <%= render "budgets/budgeted_summary", budget: @budget %>
              </div>
            <% end %>

            <% tabs.with_panel(tab_id: "actuals") do %>
              <div class="bg-container rounded-xl shadow-border-xs">
                <%= render "budgets/actuals_summary", budget: @budget %>
              </div>
            <% end %>
          <% end %>
        <% else %>
          <div class="bg-container rounded-xl shadow-border-xs">
            <%= render "budgets/actuals_summary", budget: @budget %>
          </div>
        <% end %>
      </div>
```

Replace `app/views/budgets/_budget_header.html.erb` with:

```erb
<%# locals: (budget:, previous_budget:, next_budget:, latest_budget:) %>

<% previous_param = budget.previous_budget_param %>
<% next_param = budget.next_budget_param %>

<div class="flex flex-wrap items-center gap-1 gap-y-2 mb-4">
  <div class="flex items-center gap-2">
    <% if previous_param %>
      <%= render DS::Link.new(
        variant: "icon",
        icon: "chevron-left",
        href: budget_path(previous_param),
        aria: { label: "Previous budget: #{Budget.param_to_date(previous_param).strftime("%B %Y")}" }
      ) %>
    <% else %>
      <span class="text-subdued">
        <%= icon "chevron-left", color: "current" %>
      </span>
    <% end %>

    <% if next_param %>
      <%= render DS::Link.new(
        variant: "icon",
        icon: "chevron-right",
        href: budget_path(next_param),
        aria: { label: "Next budget: #{Budget.param_to_date(next_param).strftime("%B %Y")}" }
      ) %>
    <% else %>
      <span role="link" aria-disabled="true" aria-label="You can plan up to 12 months ahead." title="You can plan up to 12 months ahead."
            class="inline-flex w-8 h-8 items-center justify-center text-subdued">
        <%= icon "chevron-right", color: "current" %>
      </span>
    <% end %>
  </div>

  <%= render DS::Menu.new(variant: "button") do |menu| %>
    <% menu.with_button class: "flex items-center gap-1 hover:bg-alpha-black-25 cursor-pointer rounded-md p-2"  do %>
      <span class="text-primary font-medium text-lg lg:text-base"><%= budget.name %></span>
      <%= icon("chevron-down") %>
    <% end %>

    <% menu.with_custom_content do %>
      <%= render "budgets/picker", family: Current.family, year: budget.end_date.year %>
    <% end %>
  <% end %>

  <% if budget.future? %>
    <span class="inline-flex items-center gap-1.5 rounded-md bg-surface-inset px-2 py-1 text-sm font-medium text-primary">
      <%= icon "calendar-clock", size: "sm" %>
      <span>Starts <time datetime="<%= budget.start_date.iso8601 %>"><%= recurring_date(budget.start_date, short: true) %></time></span>
    </span>
  <% end %>

  <div class="ml-auto">
    <%= render DS::Link.new(
        text: "Today",
        variant: "outline",
        href: budget_path(Budget.current_param(Current.family)),
    ) %>
  </div>
</div>
```

`app/views/budgets/_budget_donut.html.erb` — replace lines 6-34 (the `if budget.initialized? … else … end` inside `defaultContent`) with:

```erb
      <% if budget.initialized? %>
        <% if budget.future? %>
          <p class="flex items-center gap-1 text-sm font-medium text-primary mb-2">
            <%= icon "repeat", size: "sm" %><span>Committed</span>
          </p>
        <% else %>
          <div class="text-gray-600 text-sm mb-2">
            <span>Spent</span>
          </div>
        <% end %>

        <div class="mb-2 text-3xl font-medium tabular-nums <%= budget.available_to_spend.negative? ? "text-red-500" : "text-primary" %>">
          <%= format_money(budget.actual_spending_money) %>
        </div>

        <%= render DS::Link.new(
          text: "of #{budget.budgeted_spending_money.format}",
          variant: "secondary",
          icon: "pencil",
          icon_position: "right",
          size: "sm",
          href: edit_budget_path(budget)
        ) %>
      <% elsif budget.future? && budget.committed_spending.positive? %>
        <p class="flex items-center gap-1 text-sm font-medium text-primary mb-2">
          <%= icon "repeat", size: "sm" %><span>Committed</span>
        </p>

        <div class="mb-2 text-3xl font-medium text-primary tabular-nums">
          <%= format_money(budget.committed_spending_money) %>
        </div>

        <%= render DS::Link.new(
          text: "New budget",
          size: "sm",
          icon: "plus",
          href: edit_budget_path(budget)
        ) %>
      <% else %>
        <div class="text-subdued text-3xl mb-2">
          <span><%= format_money Money.new(0, budget.currency || budget.family.currency) %></span>
        </div>

        <%= render DS::Link.new(
          text: "New budget",
          size: "sm",
          icon: "plus",
          href: edit_budget_path(budget)
        ) %>
      <% end %>
```

`app/views/budgets/_budgeted_summary.html.erb`:
- Wrap the Expected income bar block (lines 11-31, the `<div>` with the green bar and "earned") in `<% unless budget.future? %> … <% end %>`.
- Line 52 becomes:

```erb
        <p class="text-secondary"><%= format_money(budget.actual_spending_money) %> <%= budget.future? ? "committed" : "spent" %></p>
```

`app/views/budget_categories/_budget_category.html.erb:47`:

```erb
      <p class="text-sm font-medium text-primary"><%= format_money(budget_category.actual_spending_money) %><%= " committed" if budget_category.budget.future? %></p>
```

`app/views/budget_categories/show.html.erb`:
- Line 34: `<%= @budget_category.budget.start_date.strftime("%b %Y") %> <%= @budget.future? ? "committed" : "spending" %>`
- Wrap the existing "Recent Transactions" section (lines 90-140, from `<% dialog.with_section(title: "Recent Transactions", open: true) do %>` to its closing `<% end %>`) in a future/else branch, leaving those lines untouched. Insert immediately **before** line 90:

```erb
    <% if @budget.future? %>
      <% dialog.with_section(title: "Committed in #{@budget.name}", open: true) do %>
        <% items = @budget.recurring_commitments.items_for(@budget_category.category) %>
        <div class="space-y-2 pb-4">
          <% if items.any? %>
            <% items.group_by(&:date).each do |date, date_items| %>
              <%= render "recurring_transactions/commitment_group", date: date, items: date_items %>
            <% end %>
          <% else %>
            <p class="text-secondary text-sm px-3 py-2">Nothing committed in this category.</p>
          <% end %>
        </div>
      <% end %>
    <% else %>
```

and immediately **after** line 140 (the section's closing `<% end %>`):

```erb
    <% end %>
```

`app/views/budgets/edit.html.erb` — replace lines 43-63 (the autofill box) with:

```erb
        <% if @previous_budget&.initialized? %>
          <% from_previous_month = @previous_budget.to_param == @budget.previous_budget_param %>
          <div class="border border-tertiary rounded-lg p-3 flex">
            <%= icon "sparkles" %>
            <div class="ml-2 space-y-1 text-sm">
              <% if from_previous_month %>
                <h4 class="text-primary">Autofill budget from previous month</h4>
                <p class="text-secondary">
                  Copies <%= @previous_budget.name %>'s income, spending, and category amounts as a starting point. You can adjust anything after.
                </p>
              <% else %>
                <h4 class="text-primary">Start from your <%= @previous_budget.name %> budget</h4>
                <p class="text-secondary">Copies <%= @previous_budget.name %>'s budget</p>
              <% end %>
            </div>

            <%= render DS::Toggle.new(
              id: "autofill_previous_month",
              name: "budget[autofill_previous_month]",
              data: {
                action: "change->budget-form#toggleAutoFill",
                budget_form_income_param: { key: "budget_expected_income", value: sprintf("%.2f", @previous_budget.expected_income || 0) },
                budget_form_spending_param: { key: "budget_budgeted_spending", value: sprintf("%.2f", @previous_budget.budgeted_spending || 0) }
              }
            ) %>
          </div>
        <% end %>
```

- [ ] **Step 4: Run tests to verify they pass**

Run the Step 2 command. Expected: 5 runs, 0 failures.

- [ ] **Step 5: Lint and commit**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop test/controllers/budgets_controller_test.rb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint app/views/budgets/show.html.erb app/views/budgets/_budget_header.html.erb app/views/budgets/_budget_donut.html.erb app/views/budgets/_budgeted_summary.html.erb app/views/budgets/edit.html.erb app/views/budget_categories/_budget_category.html.erb app/views/budget_categories/show.html.erb -a
git add app/views/budgets app/views/budget_categories test/controllers/budgets_controller_test.rb
git commit -m "Plan future budget months with committed amounts

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 18: Final verification

**Files:** none (fixes go into the task they belong to, as new commits).

**Interfaces:** Consumes everything above. Produces the evidence that Phases B and C are done.

- [ ] **Step 1: Full suite vs baseline**

Run: `docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models test/jobs test/controllers test/helpers test/components`
Expected: the failures/errors in `test/models test/jobs test/controllers` are exactly the 124 pre-existing ones (16 F / 118 E) — compare the failing test **names** with the baseline list in `.superpowers/sdd/progress.md`; every test added by this plan passes; `test/helpers` and `test/components` have no new failures. Any new failure is fixed (systematic-debugging) before continuing.

- [ ] **Step 2: Lint and security**

```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rubocop -f github -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bundle exec erb_lint ./app/**/*.erb -a
docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/brakeman --no-pager
npm run lint
```

Expected: rubocop and erb_lint clean; brakeman no new warnings (the preview/plan controllers scope every lookup to `Current.family`); Biome clean for `recurring_form_controller.js` and `confirm_dialog_controller.js`. Commit any autocorrections: `git commit -am "Apply lint fixes" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.

- [ ] **Step 3: Copy check** — every new UI string must match the copy doc "Kept" tables. Run:

```bash
grep -rn "MSI\|(MSI)\|Months without interest\|Set up\b\| cycle" app/views app/helpers/recurring_transactions_helper.rb app/helpers/custom_confirm.rb app/javascript/controllers/recurring_form_controller.js
```

Expected: no matches in UI strings (code identifiers like `msi_purchase` are fine; the grep is case-sensitive on purpose).

- [ ] **Step 4: Manual browser checklist** (the orchestrator rebuilds the Docker image and opens http://localhost:3001 as `bob@bobdylan.com`; compare each item side by side with the canvas file named in brackets, at 375 / 768 / 1280 px, light and dark):
  - B1 [`Main.dc.html` 1-2]: New transaction → Expense shows a closed "Recurring payment" disclosure between Date and Details; Income tab has none. Open it: "Doesn't repeat" checked. Pick a credit card: "Installments" appears last; pick Checking: it disappears (and if it was chosen, the choice returns to "Doesn't repeat").
  - B1 fields: Installments shows "Number of installments" + "First payment" side by side ≥ `@sm`, stacked at 375 px, both `h-5`, no misalignment; First payment = date + 1 month and follows the date until edited. Monthly charge shows "Ends after [ ] payments" only.
  - B2 [`Main.dc.html` 3-4]: summary appears ~500 ms after typing stops, dims while recalculating (instant with reduced motion), two fixed lines ("12 installments of $1,250.00" / "Last on Oct 8, 2027"), past purchases add "3 already due…"; empty while data is missing; with the server stopped mid-typing shows "We couldn't calculate this. You can still save."
  - B1 impact [`Main.dc.html` 2]: with Installments and a configured budget, the block lists up to 3 months, bars use one scale (budget mark ≈ 83 %), "This purchase" segment red in every month, over months show "$X over" in red-700/red-400 and the header "This puts {Month} $X over budget"; legend present; reference line when a month has no budget; block absent without any budget; Charges never show it.
  - B1 submit [`Main.dc.html` 5]: invalid number → 422 with the disclosure open, message under the field (`aria-invalid`), focus on that field; valid → modal closes, notice "Split into 12 installments." / "Monthly charge started.".
  - Screen reader (VoiceOver): summary announced once per pause (incl. "This puts …" when over); notices announced (tray `role="status"`).
  - B3 [`Convert.dc.html`]: drawer Settings starts with "Recurring payment · One time · Edit"; Edit → radios ("Doesn't repeat" checked, Review disabled); choose Installments → fields + summary on white card; Review → confirmation with focus on the heading, bullets, "Cancel" / "Split into 18 installments"; confirm → drawer re-renders with the provenance block focused, row updates, notice. One-time Expense row shows "Turn off One-time Expense to set this up." without a button. Transfers/income/linked accounts show no block.
  - C1 [`Rows.dc.html`]: list rows show the provenance line on every width (account + "·" only from `lg`, no stray "·" on mobile), "View plan" opens the plan dialog; drawer of an installment shows "Installment 1 of 12" + View plan, Type/Amount disabled and stacked with "Set by the plan."; purchase drawer shows the debt-vs-spending note, "To change it, delete this purchase and add it again." and "Also deletes its 12 installments."; Exclude / One-time / Transfer matcher hidden on those rows.
  - C3 [`Dialogs.dc.html`]: dialog title focused on open; progress bar for installments; Name/Category editable (Amount only for charges); lock note for installments; Save asks "Save changes to future payments?" when payments exist; Stop → confirm with "Keep it" focused (Tab reaches "Stop payments"); stopped plan read-only; deleting a purchase → "Delete this purchase and its installments?" with red "Delete" and focus on "Keep it"; deleting one installment → "Delete this installment?". Existing delete confirms elsewhere unchanged (no secondary button).
  - C2 [`Card.dc.html`]: credit card page has tabs Activity (default) / Recurring payments; `?tab=recurring` deep link works; KPIs in 3 columns from `md`, 1 column below; Upcoming grouped by date ("Today"/"Tomorrow"), no warning; "See later months" opens the right budget month; tables hide Payments left / Left to pay / Ends below `md` and show them as a second line; Past plans disclosure; empty and all-done states.
  - C4 [`Budget.dc.html`]: block between donut and tabs in the current and future months only; normal: neutral bar + "87% of your budget"; over: red full bar + "123% of your budget" + yellow Alert with title and "Review budget" only; future vs reference budget: "76% of your October 2026 budget" + "Compared with your October 2026 budget. Set up March 2027 to use its own."; "See details" lists the month's payments with account links and View plan; nothing committed in a future month → "Nothing committed for October 2027 yet".
  - Future months [`Future.dc.html`]: chevron/picker go up to 12 months ahead, then the right chevron is disabled with "You can plan up to 12 months ahead." (tooltip + accessible name); chip "Starts Nov 28"; donut says "Committed" (with `repeat`) even without a budget; no Budgeted/Actual tabs; category rows "$4,950.00 committed / from $4,500.00"; category drawer "Committed in December 2026"; Setup offers "Start from your October 2026 budget / Copies October 2026's budget" and copies it; `<title>` reads "December 2026 budget".
  - Families without plans: transactions, budgets and credit cards look exactly as before (apart from the Recurring payments tab and future navigation).

- [ ] **Step 5: Record and hand off** — update `design-state.md` "Status / Pending" (Phases B + C done, commit range, open items from "Spec gaps" below) and commit:

```bash
git add design-state.md
git commit -m "Record Phases B and C completion in design state

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Spec coverage (self-review)

| Spec item | Task |
|---|---|
| B1 disclosure, radios, fields, defaults, Expense-only, credit-card-only Installments | 10 |
| B2 server summary, 500 ms debounce, `aria-busy`, one announcement, unavailable state | 9, 10 |
| B1 budget impact block (§2.4b, V15, V19 default, red segment default) + shared calc + parity | 3, 5, 9 |
| B1 atomic submit, 422 with open disclosure + autofocus, notices | 11 |
| B3 status + Edit (D14), fields, Review, confirmation with focus, success stream + focus, block errors, never 500 | 12 |
| C1 row provenance (all widths, account on `lg`), drawer block, locked Type/Amount, hidden toggles, delete variants | 14 |
| C2 tab, KPIs, Upcoming (current + 2), See later months, tables + mobile 2nd line, past, empty/all done, no warning | 6, 15 |
| C3 dialog, edit (name/category/charge amount), schedule locked, stop, read-only states, confirms with "Keep it" focus | 2, 7, 13 |
| C4 block, B + A warning, reference budget, See details, empty future | 3, 16 |
| Future budgets: horizon 12, nav + aria, chip, Committed, no tabs, category rows/drawer, autofill source, compare vs last configured | 4, 17 |
| Carry-over: `create_from_entry!` guards | 2 |
| Carry-over: RecordInvalid handled (kind toggle, TransferMatches) | 8, 11, 12 |
| Carry-over: one-time toggle hidden on locked rows | 14 |
| Carry-over: plans only on manual active accounts; one invalid plan doesn't stop the job | 1, 2 |
| Carry-over: `Category#replace_and_destroy!` moves plan category | 1 |
| Carry-over: family-timezone date | 1 |
| Carry-over: `last_generated_on` reset → schedule locked instead (D12) | 2 |
| Notification tray `role="status"` (§11.11) | 8 |
| Bulk updates can't change kind (§11.7) | already true: `Entry.bulk_update!` only touches date/notes/category/merchant/tags |

## Spec gaps and decisions taken in this plan

1. **B3 on linked rows (interaction §3.1 vs canvas D14):** §3.1 says no block for `msi_purchase`/`installment`/charge occurrences; the canvas and copy have `b3.status_charge` / `b3.status_installments` with "Edit". Plan: show status + "Edit", and Edit opens the plan dialog (C3). Victor can drop it later in one partial.
2. **B3 open/close:** §2.7 describes a JS `toggle`; the plan uses server-driven frame steps (Edit link → fields → Review → confirm, Cancel link → closed) with `autofocus` on each step's target. Same visuals, no extra JS targets.
3. **Account-change note (§2.3):** "Installments only work on credit cards." is announced through the live region but not shown visually (keeps `recurring-form` under 7 targets).
4. **Budget basis for the current month:** §6.1 says the reference budget applies to future months; the plan also applies it to the *current* month when it isn't set up (past months never borrow). Confirm with Victor.
5. **Impact "next 3 installments" for backdated purchases:** installments whose month already ended are skipped (the block projects upcoming months only).
6. **`bi.title_over_multi` and `bi.reference`** are design-lead proposals still marked "pending content-writer"; the plan uses them verbatim.
7. **"One time" (`b3.status_one_time`) vs the "One-time Expense" toggle** naming risk stays as in the Kept table (open question in design-state).
8. **Transfer matcher on locked rows:** redirect back with the `c1.err.transfer_match_locked` alert instead of re-rendering the modal with 422 (the matcher form targets `_top`; a 422 render would replace the whole page with the dialog).
9. **Stopped date** = `updated_at` of the plan (no `stopped_at` column, so no migration); safe because stopped plans are read-only.
10. **Field error text** keeps the canvas's `text-destructive` (4.36:1, same as existing `shared/form_errors`); only the impact block uses the red-700/red-400 build default. Flag with DD-5.
11. **Currency:** v1 assumes plan currency = family currency (no conversion in commitments), as allowed by interaction §11.16.
12. **Copy grammar for 1:** "The 1 already added stays." / "The 1 payment already added won't change." use singular forms (copy shows only plurals).
13. Open question still with content-writer: copy examples "27 – 26" vs code's 28 → 27 windows — all labels come from `Budget#name` / `cycle_range_containing`, so nothing is hardcoded.

**Migration required:** none.
