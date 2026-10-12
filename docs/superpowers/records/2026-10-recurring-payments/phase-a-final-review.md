# Final whole-branch review: Phase A (recurring transactions + MSI)

Range: `aa37d8f7..a633db57` (9 commits), plus migration `db/migrate/20261006120000_create_recurring_transactions.rb` and `db/schema.rb`.
Reviewed against `docs/superpowers/plans/2026-10-06-recurring-transactions-phase-a.md` and the strategy doc. Read-only; no tests re-run (I relied on the controller's full-suite run: the same 124 failures as the base, none new).

## Strengths

- **One source of truth per number.** `Transaction.budget_excluded_kinds_sql` (`app/models/transaction.rb:23-28`) replaces the 4 hand-written kind lists in `IncomeStatement::Totals`, `FamilyStats`, `CategoryStats` and `Transaction::Search#totals`. Budget, the AI assistant and the dashboard all read spending through `IncomeStatement`, so the rule reaches every spending view. I grepped for other `kind`-based spending filters and found none.
- **Balance exclusion is in the right place.** `Balance::SyncCache#converted_entries` (`app/models/balance/sync_cache.rb:21-38`) is the only entry feed for `BaseCalculator`, `ForwardCalculator` and `ReverseCalculator`, so `installment` rows can't reach any balance. `includes(:entryable)` avoids an N+1. Valuations and trades are unaffected. The `excluded` flag doesn't touch balances, so excluding an `msi_purchase` can't remove the debt.
- **Invariant 1 (MSI) holds.** `msi_purchase` adds the full debt and is excluded from spending. `installment` counts as spending and never changes the balance. Tests cover both sides end to end: `sync_cache_test.rb` runs `ForwardCalculator`, and `income_statement_test.rb` / `search_test.rb` cover the spending queries.
- **Invariant 2 (charges) holds.** Charges generate plain `standard` rows (`recurring_transaction.rb:129`) that flow through balance and spending unchanged.
- **Idempotency is solid.** The unique index `(recurring_transaction_id, installment_number)` is the idempotency key. `create_occurrence` uses a savepoint (`requires_new: true`), so a `RecordNotUnique` inside `create_from_entry!`'s outer transaction doesn't poison it. Backfill uses the original dates (`occurrence_date`), and end-of-month clamping is tested.
- **Invariant 4 (no plans = no change) holds.** Per family per day there is one `update_column` (it skips `updated_at`, so no cache keys get invalidated) and one `exists?`. No job runs and no query or calculator output changes. The fixtures have no plans, so existing tests are unaffected.
- **Migration is clean.** It has FKs on every reference, a non-null `status` default, `index: false` on the reference (the composite unique index covers it), and `decimal(19,4)` to match `entries.amount`. `schema.rb` matches.
- **Deviations are justified and recorded.** Moving `belongs_to :recurring_transaction` from Task 2 to Task 5 and including `RecurringGeneration` on its own line both make sense. The include-order comment is accurate: the callback runs after `Authentication` and inside `Localize#switch_timezone`.
- **Deletion paths are FK-safe.** `Account` (`dependent: :destroy`, declared after `entries`, so entries go first), `Category`/`Merchant` (`nullify`, which `FamilyMerchant` inherits) and `Family` (accounts are destroyed first, so plans are already gone) all delete cleanly.

## Issues

### Critical (Must Fix)

None.

### Important (Should Fix)

None of these can be reached in production today: Phase A has no UI or API that creates a plan, so a plan exists only if someone makes it in the console. But all three break the core invariants as soon as Phase B's capture UI ships. Make them the first Phase B task (they are model-level, not UI).

1. **A deleted occurrence comes back the next day.**
   - File: `app/models/recurring_transaction.rb:89-96` (`upcoming` only skips `generated_numbers`) and `:103-112` (`generate_due!`).
   - What: the delete button in `transactions/show` destroys the Transaction. That number then drops out of `generated_numbers`, and the next daily run recreates it with its original date. The same happens to a charge's source entry (occurrence #1) if the user deletes it. The user can't remove a wrong or duplicated installment or charge.
   - Why it matters: it breaks invariant 3 (generation should be predictable and edits should only affect the future). It also breaks the strategy's rule that generated history doesn't change behind the user's back.
   - Fix (pick one):
     - After creation, generate only numbers greater than `generated_numbers.max`. That keeps the backfill in `create_from_entry!` and still lets the unique index handle concurrency.
     - Or block or soft-skip deletion of plan-linked rows with a `before_destroy` on `Transaction`.

2. **Deleting the `msi_purchase` entry orphans an active plan.**
   - File: `app/models/transaction.rb` (no destroy hook). `has_many :transactions, dependent: :nullify` in `recurring_transaction.rb:325` only covers the plan→transaction direction.
   - What: the full debt leaves the card balance, but the plan stays `active` and keeps generating `installment` rows. They count as spending while the balance shows no debt.
   - The reverse case: destroying a plan leaves the `msi_purchase` permanently excluded from spending, and the remaining installments are never counted. That breaks invariant 5's "no orphan data" in both directions.
   - Fix: on destroying an `msi_purchase` that has a plan, cancel or destroy the plan (and decide what happens to the installments already generated). Phase B also needs a plan-destroy path that converts the `msi_purchase` back or forbids the destroy while installments remain.

3. **Existing code paths can overwrite `kind` on plan-linked rows and double-count.** Paths:
   - The one-time toggle, `app/views/transactions/show.html.erb:130-133`. Its unchecked value is `"standard"`, so toggling it turns an `msi_purchase` into a `standard` row.
   - The transfer matcher, `app/controllers/transfer_matches_controller.rb:13-14`.
   - The auto-matcher that runs on sync, `app/models/family/auto_transfer_matchable.rb:68-69`.
   - Transfer destroy, `app/models/transfer.rb:37-38`, which resets the kind to `"standard"`.

   Effects:
   - An `msi_purchase` turned into `standard` (directly, or through match then unmatch) double-counts spending.
   - An `installment` turned into `one_time`, `standard` or `funds_movement` re-enters the balance and doubles the debt.

   The strategy already plans to hide the toggles in Phase B, but the auto-matcher has no UI and runs during family sync. Fix:
   - Add a model guard on `Transaction`: a row with `recurring_transaction_id` whose kind is `msi_purchase` or `installment` can't change kind except through `RecurringTransaction`.
   - Exclude those two kinds from `transfer_match_candidates`.

### Minor (Nice to Have)

New in this review:

- **M1. Timezone mismatch.**
  - File: `app/jobs/generate_recurring_transactions_job.rb:3` → `generate_due!(as_of: Date.current)` at `recurring_transaction.rb:103`.
  - What: the request guard compares `Date.current` in the family's timezone (`Localize#switch_timezone`), but the job runs in the server zone (UTC). On an evening visit in Mexico (UTC-6) the job can generate an occurrence dated "tomorrow" in local time.
  - Fix: `Time.use_zone(family.timezone) { Date.current }` in the job. **Phase B.**
- **M2. Plans on unsuitable accounts.** Nothing stops a plan on a Plaid-linked account, where generated rows would duplicate provider-imported ones. `GenerateRecurringTransactionsJob` also generates for plans on `disabled` or `pending_deletion` accounts, which can race with `DestroyJob`. Fix: validate a manual account, and skip non-active accounts in `generate_due!`. **Phase B.**
- **M3. Replaced categories don't carry over to plans.** `Category#replace_and_destroy!` (`category.rb:99-103`) moves transactions to the replacement category, but plans get nullified, so future occurrences come out uncategorized. Fix: also run `recurring_transactions.update_all(category_id: replacement&.id)`. **Phase B.**
- **M4. Editing a plan would rewrite past figures.** `remaining_balance` (`recurring_transaction.rb:82-86`) recomputes paid amounts from the current `amount`/`total_payments`. Once Phase B allows editing a plan, history math would shift, which contradicts "edit affects only future". Fix: sum the actual amounts of the linked installment entries. **Phase B (when edit exists).**
- **M5. One bad plan stops the whole job.** A `RecordInvalid` from one plan (`create_occurrence` or `update!`) aborts `find_each` for every remaining plan in the family, and Sidekiq retries forever. Fix: rescue and log per plan. **Phase B.**
- **M6. No family consistency check.** Nothing validates `plan.family == account.family`. Fix: scope plan creation in the Phase B controller or add a validation. **Phase B.**

## Triage of accumulated Minor findings (`progress.md`)

| # | Finding | Triage |
|---|---------|--------|
| 1 | No test asserts BUDGET/BALANCE_EXCLUDED_KINDS ⊆ enum `:kind` | Accept |
| 2 | SQL-quoting test duplicates the constant literal (plan-mandated) | Accept |
| 3 | `search.rb:96/112` keep their own kind lists | Fix in Phase B. Behaviour is consistent today (MSI rows show as expenses in the type filter and totals still exclude `msi_purchase`), but revisit when rows get badges or filters |
| 4 | Search totals cache may be stale after deploy | Accept. The key includes `entries_cache_version` and self-heals on the next entry change |
| 5 | Search test only asserts `expense_money` | Accept |
| 6 | `sync_cache.rb` map block indentation | Accept (rubocop clean) |
| 7 | No direct reverse-calculator test | Accept. Both calculators share `SyncCache`, which is tested directly |
| 8 | `upcoming` ignores status | Fix in Phase B/C. The commitments view must call it on `.active` plans (or `upcoming` returns `[]` when not active) |
| 9 | Account delete test uses an `Account.find` workaround | Accept |
| 10 | `sync_later` once/never not pinned by a test | Accept |
| 11 | Generated entry amounts not asserted | Accept. `occurrence_amount` is tested directly |
| 12 | `RecordNotUnique` branch untested | Accept |
| 13 | `update!` before `sync_later`: a validation failure skips the sync | Fix in Phase B (together with M5) |
| 14 | `create_from_entry!` has no guard for a non-Transaction entry or an already-linked entry | Fix in Phase B (Phase B is the first caller) |
| 15 | Negative amounts raise `RecordInvalid` | Fix in Phase B (form validation or a friendly message) |
| 16 | No past-dated charge or explicit `start_date` tests | Fix in Phase B |
| 17 | Once-per-day guard is not atomic | Accept. Worst case is a redundant job, and generation is idempotent |
| 18 | Flag is set before the job runs | Accept. Sidekiq retries a failed job |
| 19 | One `exists?` query per family per day | Accept |
| 20 | No unauthenticated-request test | Accept. `return unless family` makes it trivially safe |

Counts: must-fix-before-merge **0**, fix-in-Phase-B **6**, accept **14**. There are also 6 new Minors (M1–M6), all for Phase B.

## Invariant checklist

1. MSI debt and spending: **holds.** Spending is excluded in all 4 queries and the balance is excluded once in `SyncCache` for all 3 calculators. Kind overwrites can break it later (Important 3).
2. Charges behave like `standard` rows: **holds.**
3. Generation is idempotent, uses original dates, and cancel affects only the future: **holds for generation and cancel.** Deleting a row resurrects it (Important 1). Edit doesn't exist yet (M4).
4. Families without plans are unchanged: **holds.** The only additions are one `update_column` and one `exists?` per family per day.
5. Deletion paths: **FK-safe for family, account, category, merchant and plan.** The entry-side deletions orphan data (Important 1 and 2), and `replace_and_destroy!` drops the plan's category (M3).
6. Other `kind` consumers: the one-time toggle, the transfer matcher, the auto-matcher and transfer destroy can all rewrite the new kinds (Important 3). The search filters (Minor 3) and the API jbuilder (no `kind` field; classification by amount) are fine for now. Rules don't touch `kind`. The data exporter exports `kind`, but plans don't survive a re-import (accept).

## Recommendations

- Start Phase B with a short model task covering Important 1–3: a kind-immutability guard, a destroy hook on `msi_purchase` and plan-linked rows, a forward-only generation cursor, and auto-matcher exclusion. Include M1, M2 and M5 because they are one-liners in the same files.
- When Phase B adds plan editing, persist what was actually generated (sum the entries) rather than re-deriving it from the plan.

## Assessment

**Ready to merge?** Yes. Nothing is merge-blocking, because Phase A exposes no way to create a plan outside the console. Important 1–3 must land before or with the Phase B capture UI.

**Reasoning:** The number invariants (spending through one SQL helper, balance through one `SyncCache` filter) are implemented correctly, tested end to end, and invisible to families without plans. What's left is lifecycle handling for deleted rows and for `kind` changes from existing UI and sync paths. That becomes reachable only once users can create plans.
