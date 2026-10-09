# Final fix report — Phases B+C

Commits (on feature/meses-sin-intereses, after f273012a):
- bfa82d25 Bound monthly charge count and keep submitted values on a 422 (I1 + I2)
- 09111fb0 Name the basis month in the over-budget alert and memoize the basis budget (I3 + m3 + I4)
- bc0ce794 Polish future-month views and add regression and parity tests (I6, m1, m2, m6, I5)
- 8bbe7555 Fix biome lint and formatting in the recurring form controller

## Per item
- I1: `RecurringTransaction::MAX_CHARGE_PAYMENTS = 600`; charge "Ends after" outside 1..600 gets "Enter a whole number, or leave it empty."; input has `max:`. RED: model test valid (expected invalid); controller POST raised ActiveModel::RangeError. GREEN after fix.
- I2: `_form.html.erb` date `value: entry.date || Date.current`; tabs/hidden nature/categories now use the `outflow` local (covers params.dig(:entry,:nature)). RED: date input missing 2026-09-01; GREEN.
- I3/m3: alert uses `basis_name`; money helpers (`committed_spending_money`, `commitments_overage_money`). RED: "over your December 2026 budget"; GREEN ("over your October 2026 budget", aria-label still names December).
- I4: `basis_budget` memoized with `defined?`. RED: mocha expects once, invoked twice; GREEN.
- I6/m1/m2/m6: drawer label `@budget.name` (asserted "December 2026 committed"); donut `tabular-nums`; `mb-2` dropped on future Expected income; confirm h4 focus ring classes.
- I5: (a) budget_test current/past parity vs expense_totals; (b) past month never shows C4/borrow; (c) edit autofill text for a future month + PATCH autofill copies latest budget categories (edit test stubs `stylesheet_link_tag` because the wizard layout needs tailwind.css, missing in this env); (d) preview with other family's entry_id / account_id renders empty frame, no Entry/RecurringTransaction change.
- Biome: `biome check --write` on recurring_form_controller.js: formatting (line wrapping) + one optional-chain fix (`event?.target`) done manually (unsafe fix). `npm run lint` clean (93 files). confirm_dialog_controller.js clean.

## Suite
test/models test/jobs test/controllers test/helpers test/components:
- HEAD: 1007 runs, 16 F, 118 E, 5 skips. Baseline (ece22c7f worktree): 888 runs, 16 F, 118 E, 5 skips.
- Failing test names: identical sets (125 lines each). New failures: 0. Fixed: 0. (Remaining are tailwind.css / Plaid environmental.)

## Lint
- rubocop app test: 595 files, no offenses.
- erb_lint on 28 ERB files changed since ece22c7f: no errors.
- brakeman: 0 errors, 1 warning (Unmaintained Dependency: Rails 7.2.2.1 EOL, Gemfile.lock, pre-existing). Note `bin/brakeman` exits 5 ("not latest version 8.1.0", because it forces --ensure-latest) before analysing; ran via `bundle exec brakeman --no-pager`.
- biome: clean.

Worktree removed. .claude/ untracked left alone.
