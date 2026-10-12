# Final whole-branch review — Phases B + C (ece22c7f..f273012a)

Reviewer: final code review (read-only). Scope: 26 commits, 70 files (+3665/−208). Phase A was reviewed separately.
Inputs: the diff package, the plan (Global Constraints), the design sources (interaction, visual rev 3, copy "Kept" tables, canvas) and the ledger `.superpowers/sdd/progress.md`.

## Strengths

- **There really is one commitments calculation.** `Family::RecurringCommitments` (generated rows in the range, plus not-yet-generated occurrences of `generatable` plans) feeds `Budget#committed_spending` / `#committed_spending_for`. That covers C4, the future-month donut, the summary, the category rows and the drawer (`items_for`), which all use the same memoized `recurring_commitments`. It also feeds `RecurringTransaction::BudgetImpact` (`budget.committed_spending` + `budget.basis_budget`) and the card's Upcoming list (`include_generated: false`). Future months switch at a single point (`Budget#actual_spending` / `#budget_category_actual_spending`). Parity tests pin capture against saved, and card Upcoming against the future month.
- **Scopes are consistent and documented.** Generated rows count whatever the plan's status (a stopped plan's past rows still cost money). Upcoming counts only `generatable` plans. The card headline figures count plans by status (a disabled card still owes its installments). Generated rows go through the same exclusions as budget spending (`BUDGET_EXCLUDED_KINDS`, `excluded: false`), and the parent/subcategory/uncategorized roll-up matches `expense_totals`.
- **Tenancy is solid.** Every new lookup is scoped to `Current.family`: `set_recurring_transaction`, `preview_entry` (entry and account), `set_entry` in the recurrences controller (also limited to `Transaction` entries), and the category in `recurring_transaction_params` (`expenses.find`, so an income category or another family's category is a 404). Tests cover the cross-family cases for show/update/stop, the category, and recurrences.
- **Capture is atomic.** `save_entry_with_recurrence` rolls back the entry when the plan is invalid. `create_from_entry!` builds and validates through the same `build_from_entry` used by preview, convert and capture, so the summary, the confirm step and the persisted plan can't drift apart. The schedule lock (D12) removes the whole "reset `last_generated_on`" class of bugs.
- **Server-side locks back up the UI.** `Entry#plan_amount_unchanged`, `Transaction#plan_kind_unchanged` with copy-exact text, and the transfer guard, plus the `RecordInvalid` rescue in `TransferMatchesController`. The drawer shows the reason next to the disabled amount (`aria-describedby`).
- **Accessibility work is careful.** One live region per form (`recurring-form` status, filled from a hidden announcement span), `role=alert` only on submit errors, `aria-invalid`/`aria-describedby` per field, the first invalid field gets autofocus, the confirm dialog gets a safe secondary button with initial focus plus `aria-describedby`, `returnValue` is reset before `showModal`, the notification tray is now a status region, and the bars are `aria-hidden` with text equivalents.
- **Copy is exact against the Kept tables.** I checked b2, bi, b3, c1, c2, c3, c4, f and w. No "MSI" or "cycle" in UI text. "Cancel" appears only as `b3.confirm_secondary`: the fields-step Cancel is mandated by interaction §155/§164, and the hidden default label in the confirm dialog is never shown. The new UI uses the `icon` helper and functional tokens throughout (the `gray-*` hits in the diff are pre-existing lines that were only re-indented).
- **Job resilience.** Generation follows the family timezone (`Family#today`), and a failing plan is isolated with a per-plan rescue plus Sentry.

## Cross-task invariants

| # | Invariant | Result |
|---|---|---|
| 1 | One shared commitments calculation, same scopes and basis rule | **Holds.** BudgetImpact, C4, future actual_spending, category rows and drawer all use `Family::RecurringCommitments` + `Budget#basis_budget`. Card headline figures intentionally use status, not generation (ledger T15, accepted). |
| 2 | No-plan families unchanged on current/past screens | **Holds.** The list adds a no-op `includes(:recurring_transaction)` (the preloader skips null FKs). C4 is hidden when committed is 0 on current/past months. The drawer and the form only gain the B1/B3 entry points (the feature itself). Approved exceptions confirmed: future months (including the "Nothing committed" box) and the card tab with an empty state. Gap: no regression test pins current/past `actual_spending` (see I5). |
| 3 | Never 500 on user/tampered input; family scoping; narrow rescues | **One real hole (I1):** an unbounded charge "Ends after" overflows the integer column. Malformed param shapes (`recurrence=foo`, `entry=foo`) also raise, same as existing app code (Minor m3). Scoping holds everywhere. |
| 4 | Copy, a11y | **Holds, with one wording defect (I3)** and small items (m6, m7, m8). |
| 5 | N+1 | **Holds** on the transactions list, card tab (`includes(:category, :transactions)`, and `generated_numbers` reads the loaded association), budget block (`recurring_transaction: :account` + `:account` on upcoming) and drawers. Two exceptions: the account activity feed (pre-existing: the feed preloads nothing; plan-linked rows add 1 query each, m4) and `Budget#basis_budget` being recomputed about 7 times per budget page (I4). |
| 6 | Hotwire/Stimulus/DS conventions | **Holds.** One controller with 6 targets, declarative actions, values via `data-*-value`, native `<details>`/`<dialog>`, Turbo frames/streams, DS::Disclosure/Alert/Link/Button/Dialog. |

## Issues

### Critical (must fix)

None.

### Important (must fix before merge)

**I1. Overflowing the monthly charge "Ends after" value causes a 500 on create.**
- `app/models/recurring_transaction.rb:218` accepts any whole number ≥ 1 for a charge. `total_payments` is a 4-byte integer (`db/schema.rb:593`).
- With a value such as `3000000000`, `valid?` passes and preview/review render fine. `save!` then raises `ActiveModel::RangeError` (verified in activemodel 7.2.2.1, `Type::Integer#serialize` → `ensure_in_range`).
- In `TransactionsController#save_entry_with_recurrence` (`app/controllers/transactions_controller.rb:126`) only `RecordInvalid` is rescued, so capture returns a **500**. Convert re-raises in development and shows the generic error in production.
- This breaks invariant 3. The input has no `max` either (`app/views/transactions/_recurrence_fields.html.erb:~86`).
- Fix:
  - Bound charge `total_payments` in `total_payments_in_range`. Suggested: `whole.between?(1, 2_147_483_647)` or a product cap such as 600, reusing `b.err.payments_range_charge` "Enter a whole number, or leave it empty.".
  - Add the matching `max:` to the charge input.
  - Add a model test for an out-of-range charge count.

**I2. The new-transaction form resets the date to today on every 422.**
- `app/views/transactions/_form.html.erb:44` hard-codes `value: Date.current`, so a re-render after a validation error (the Task 11 paths: invalid installment count, non-credit installments, too small, first payment before purchase) silently replaces a backdated purchase date with today.
- With a recurrence this changes the schedule:
  - For a charge, `start_date = entry.date`, so the backfill is lost.
  - For installments, the kept first-payment date may now fail "can't be before {today}", or the user re-submits a purchase dated today.
- The ledger listed this only as a browser item. It is a data-correctness bug in the new flow.
- Fix: `value: entry.date || Date.current` (keep `max:`). Add a controller test that a 422 keeps the submitted date.
- Related, pre-existing and cheap: on an Income 422 the tabs, categories and hidden `nature` read `params[:nature]` only (lines 24, 26, 41), so a re-submitted income flips to an expense. Using `params[:nature] || params.dig(:entry, :nature)` fixes it. Optional in the same fix.

**I3. In the C4 over-budget alert, the month named doesn't match the numbers when the budget is borrowed (ledger T16, FOR FINAL FIX).**
- `app/views/budgets/_recurring_commitments.html.erb:51` says "over your **{viewed month}** budget", but the overage is computed against `basis_budget` (the borrowed month). Example: Dec shows "120% of your October 2026 budget" and then "…$200.00 over your December 2026 budget". December has no budget.
- Fix: use `basis_name` (`budget.basis_budget.name`) in `w.ba.title`, and the same in the `Review {month} budget` aria-label if it should point at the month being fixed. The link target `edit_budget_path(budget)` is correct: setting up the viewed month is the fix.
- Add a test for a borrowed-and-over future month (ledger T16).

**I4. `Budget#basis_budget` isn't memoized (ledger T16, FOR FINAL FIX).**
- `app/models/budget.rb:330`. Every call to `budget_basis`, `uses_reference_budget?`, `commitments_over_budget?`, `commitments_overage` and `commitments_percent` re-runs `latest_initialized_budget_before`, roughly 7 identical queries per budget page and about 3 more per month in BudgetImpact.
- Fix: `@basis_budget ||= …`, with a `defined?` guard because the result can be nil.

**I5. Test gaps on the parity and no-regression guarantees (ledger T4/T9/T16/T17).**
Add:
- (a) A current-month and past-month regression guard: `actual_spending` equals `expense_totals.total`, a category row's actual equals its expense total, and committed amounts are never substituted.
- (b) A past month never renders C4 and never borrows (model `past months never borrow` exists; add the view/controller side).
- (c) The edit autofill branch: a future month shows `f.autofill_title` / `f.autofill_body` sourced from the latest configured budget, and `update` with `autofill_previous_month=1` copies from it.
- (d) Preview with another family's `entry_id` / `entry[account_id]` renders an empty frame and creates nothing (`assert_no_difference ["RecurringTransaction.count", "Entry.count"]`).

**I6. The category drawer's Overview label names the wrong month on custom cycles (ledger T17, FOR FINAL FIX).**
- `app/views/budget_categories/show.html.erb:34` uses `budget.start_date.strftime("%b %Y")`, while `Budget#name` and the section title ("Committed in {budget.name}") are keyed off `end_date`.
- With a custom month start the drawer reads "Nov 2026 committed" under "Committed in December 2026".
- Fix: use `@budget.name` (or the end_date month) for the label in both future and current modes.

### Minor

Each one is triaged as **must-fix** (cheap, in the fix list), **defer** (track) or **accept**.

| # | Item | Triage |
|---|---|---|
| m1 | `_budget_donut.html.erb:34`: future-only committed amount lacks `tabular-nums` (ledger T17) | must-fix |
| m2 | `_budgeted_summary.html.erb:7`: `mb-2` under Expected income stays when the bar is hidden in future months, leaving an empty gap (ledger T17) | must-fix |
| m3 | `_recurring_commitments.html.erb:24,51`: `Money.new(...).format` instead of the monetized `committed_spending_money` / `commitments_overage_money` helpers (ledger T16) | must-fix |
| m4 | Account activity feed (`accounts_controller.rb:21`, `accountable_resource.rb:28`) doesn't preload `entryable: :recurring_transaction`, so each plan-linked row costs 1 query. Pre-existing pattern (the feed preloads nothing) | defer |
| m5 | Tampered param shapes `recurrence=foo` (`recurrence_params.rb:7` `fetch(...).permit` on a String) and `entry=foo` (`params.dig`) raise 500. Same pattern as the existing `create`. | defer (low risk, consider `params.fetch(:recurrence, {})` → `params[:recurrence].is_a?(ActionController::Parameters)` guard) |
| m6 | `transactions/recurrences/_confirm.html.erb:23`: the focused `h4` lacks the visual spec's `outline-none focus-visible:ring-4 focus-visible:ring-alpha-black-200` (used on the C3 `h2` and provenance), so it gets inconsistent focus styling | must-fix (1 line) |
| m7 | `_budget_header.html.erb:29`: the disabled "next" chevron is a non-focusable `span role=link`, so keyboard/SR users can't reach `f.nav_next_disabled` | defer (browser check) |
| m8 | `credit_cards/tabs/_recurring.html.erb:41`: `aria-label` on a `<time>` (generic role) is ignored by most AT; "Mar 2027" is still read correctly | accept |
| m9 | `Budget.budget_date_valid?` / `current_param` / `latest_valid_budget_end_date` use `Date.current`, while `future?`/`past?` use `family.today`. Near midnight, a family behind UTC can see "Today" open a month labelled future. `recurring_date(short:)` also uses `Date.current.year` | defer |
| m10 | `RecurringTransactionsController#stop` (`:24`): `cancel!` (`update!`) isn't rescued. An invalid legacy plan would 500. No such data exists yet | defer |
| m11 | C3 edit for a plan whose category isn't in `categories.expenses` (e.g. the source was categorized with an income category) pre-selects "Uncategorized", so saving only the name clears the category | defer |
| m12 | `recurring_transactions/show.html.erb:4`: DB query in the view (ledger T13) | defer |
| m13 | `transfer_matches_controller.rb:9`: `LOCKED_MESSAGE` duplicates `Transfer`'s message; the rescue path (the matched entry is the locked one) is untested (ledger T8) | defer |
| m14 | Charge occurrences (standard kind with a plan) can still be toggled one-time or matched as transfers, and then drop out of commitments. This is consistent with the budget, but it isn't in the design | accept |
| m15 | Large backdated charges generate all past occurrences synchronously (bounded by `min_supported_date` = 30 years, about 360 rows) | accept |
| m16 | Bulk delete of a purchase plus its installments in one selection is untested (Phase A carry-over). Reading the code, `destroy_by` of already-deleted installments is a no-op | defer |
| m17 | `Budget#current?` is now unused (ledger T4) | defer |
| m18 | `transactions/show.html.erb:135-157`: indentation of the new `if recurrence_block` wrapper (ledger T14) | accept (erb_lint) |

**Ledger Minors (per task):**
- T1 broken plan retried daily / partial failure: accept.
- T2 validations on every update: accept; lock test only covers total_payments: defer.
- T3 N+1 `upcoming` per plan: accept (resolved, transactions preloaded); wrong comment in `budget_test.rb:246`: defer; family currency change: defer; `b.err.foreign_currency` content review: defer (content-writer).
- T4 `current?` unused: defer (m17); current/past pin test: **must-fix (I5a)**.
- T5 no horizon cap in BudgetImpact: accept (≤ 3 installments; unsaved `for_cycle` budgets are fine); `scale` with no months: accept (views guard with `available?`); backdated parity test: defer.
- T6 headline vs upcoming: accept (resolved in T15); single-card parity test: defer.
- T7 `for_msi_purchase_deletion` assumes plan: accept (the view guards `msi_purchase && plan`); JS focus/Esc: browser; biome: browser/lint.
- T8: defer (m13).
- T9 cross-family preview test: **must-fix (I5d)**; bogus currency 500: accept (now rejected first by the `foreign_currency` eligibility check, so the helper is never reached); `b2.summary_unavailable` not wired: accept (wired via `recurring-form#previewFailed`).
- T10: browser.
- T11 non-credit 422 focus/duplicate note: browser; date reset: **escalated to I2**; Income 422 tab: in I2 (optional); missing `travel_to`: defer.
- T12 stale drawer, `aria-describedby`, heading autofocus: browser; StandardError branch / weak assertions: defer; `@focus_provenance` consumed: resolved.
- T13 `any_instance` stub: accept; DB query in view: defer (m12); Rails default "Amount is not a number": defer (content).
- T14 API `full_messages` "Amount Set by the plan.": defer; weak Exclude assertion: defer; indentation: accept (m18); mobile provenance etc.: browser.
- T15 "See later months" lost when only far-future plans: defer; tab on every credit card: accept (design-mandated, **flag to Victor**); `commitment_row` account breakpoint: accept.
- T16 FOR FINAL FIX: **I3, I4, m3, I5b + borrowed-over test**; "Nothing committed" box for no-plan families: accept (brief-mandated).
- T17 FOR FINAL FIX: **m1, I6, m2, I5a, I5c**.

## Recommendations

- After the fixes, run the full `test/models test/jobs test/controllers test/helpers test/components` suite and compare against the 124-failure baseline. Then run `bin/rubocop`, `erb_lint` and `bin/brakeman` per CLAUDE.md, plus `npm install && npm run lint` (biome was never run on `recurring_form_controller.js` / `confirm_dialog_controller.js`).
- Raise with Victor: every credit card now shows a "Recurring payments" tab (approved exception), and `b.err.foreign_currency` / `bi.title_over_multi` / `bi.reference` are still pending content review.

## Assessment

**Ready to merge: With fixes.** The architecture is right: one calculation, consistent scopes, family-scoped lookups and atomic capture. The fixes are small and local: a missing upper bound that 500s, a date reset that silently changes a plan's schedule, a wrong month in the over-budget alert and the drawer label, a memoization, and the regression/parity tests the ledger already called for.

---

## FIX LIST (ordered; each item is one fix subagent's job)

1. **Bound the charge payment count (I1).**
   - In `app/models/recurring_transaction.rb#total_payments_in_range`, reject charge values above the integer limit (or a product cap, e.g. 600) with the existing "Enter a whole number, or leave it empty.".
   - Add `max:` with the same bound to the charge input in `app/views/transactions/_recurrence_fields.html.erb`.
   - Model test: `total_payments: "3000000000"` on a charge is invalid with that message.
   - Controller test: `POST /transactions` with it returns 422 and saves nothing.
2. **Keep the submitted date on a 422 (I2).**
   - `app/views/transactions/_form.html.erb:44` becomes `value: entry.date || Date.current`.
   - Optionally make the nature tabs, categories and hidden field fall back to `params.dig(:entry, :nature)` (lines 24, 26, 41).
   - Controller test: an invalid installments submission with a backdated date re-renders with that date (Turbo-Frame header to avoid the tailwind layout).
3. **Make the C4 alert name the basis month and use the money helpers (I3 + m3).**
   - In `app/views/budgets/_recurring_commitments.html.erb`, `w.ba.title` uses `basis_name`.
   - Replace `Money.new(budget.committed_spending, …)` / `Money.new(budget.commitments_overage, …)` with `budget.committed_spending_money.format` / `budget.commitments_overage_money.format`.
   - Controller test: a future month with no budget, over the borrowed basis, shows "over your October 2026 budget".
4. **Memoize `Budget#basis_budget` (I4).** In `app/models/budget.rb:330`, use `return @basis_budget if defined?(@basis_budget)` and assign it. Existing budget tests must still pass.
5. **Fix the future-month view polish (I6 + m1 + m2 + m6).**
   - `app/views/budget_categories/show.html.erb:34`: the label uses `@budget.name` instead of `start_date.strftime("%b %Y")`.
   - `app/views/budgets/_budget_donut.html.erb:34`: add `tabular-nums`.
   - `app/views/budgets/_budgeted_summary.html.erb:7`: drop `mb-2` when `budget.future?`.
   - `app/views/transactions/recurrences/_confirm.html.erb:23`: add `outline-none focus-visible:ring-4 focus-visible:ring-alpha-black-200` to the focused `h4`.
6. **Add the regression and parity tests (I5).**
   - (a) In `test/models/budget_test.rb`, current and past months: `actual_spending == expense_totals.total` and `budget_category_actual_spending` equals the category's expense total even when plans have upcoming occurrences.
   - (b) In `test/controllers/budgets_controller_test.rb`, a past month never renders "committed to recurring payments".
   - (c) Edit autofill for a future month: GET edit shows "Start from your {latest} budget" / "Copies {latest}'s budget", and PATCH with `autofill_previous_month=1` copies the categories from the latest configured budget.
   - (d) In `test/controllers/recurring_transactions_controller_test.rb`, a preview with another family's `entry_id`, and with another family's `entry[account_id]`, renders an empty frame with no change to `RecurringTransaction.count` / `Entry.count`.
7. **Verify.**
   - Run the full models/jobs/controllers/helpers/components suite in Docker and confirm there are no new failures beyond the 124 baseline.
   - Run `bin/rubocop -a`, `bundle exec erb_lint` on the changed `.erb` files, `bin/brakeman --no-pager`, and `npm install && npm run lint` for the two JS controllers.

## BROWSER CHECKLIST (verify only in a real browser)

From the ledger's Task 18 items:
1. Confirm dialog (stop plan, delete purchase, delete occurrence, edit plan): the safe button ("Keep it" / "Keep editing") gets the initial focus. Esc and backdrop click cancel (no action taken), focus returns to the trigger, and reopening after a dismissal doesn't auto-confirm.
2. B1 recurring disclosure: closing it with an invalid installment count, and Esc/backdrop closing the New transaction dialog, leave no stuck preview and nothing is announced twice.
3. B1/B3 preview: `aria-busy` and the opacity change appear while loading, a stale response after switching to "Doesn't repeat" or to a non-credit account is discarded, and the "Installments only work on credit cards." note and its announcement appear once.
4. B1 422 paths: installments on a non-credit account show one error (no duplicate note), focus lands on the first invalid field, and the date is kept (after FIX 2). An Income 422 shows the Income tab (if FIX 2's optional part is done).
5. B3 convert: Edit opens the fields with the type radio focused. Review moves focus to the confirm `h4` (visible ring only with keyboard). Cancel returns focus to Edit. After conversion the drawer refreshes and focus lands on the provenance block, and the list row updates in place.
6. Drawer after the one-time toggle on an eligible row: the Recurring payment block switches between "Turn off One-time Expense…" and the Edit block without a stale drawer.
7. B3 fieldset error: the screen reader reads the base error via the fieldset's `aria-describedby`.
8. C1 on mobile: the provenance line under the name in the list and the drawer provenance block wrap cleanly, and "View plan" opens C3 in the modal.
9. C1 locked rows: the amount is disabled with the lock help, the One-time/Exclude/Transfer controls are hidden, the delete subtitle and the high-severity confirm show for the purchase, and the occurrence confirm names the right budget month.
10. C3 dialog: the heading gets focus on open, a failed edit keeps the typed values while the header/confirm keep the saved name, Stop shows the notice, and closing reloads the underlying page (card tab / budget update).
11. Notifications: "Monthly charge started." / "Split into N installments." / "Changes saved." / "{name} stopped." are announced once by the `role=status` tray, including after the redirect from capture.
12. JS lint: `npm install && npm run lint` is clean for `recurring_form_controller.js` and `confirm_dialog_controller.js` (biome was missing locally).

My additions:
13. C2 card tab: KPI grid at 1 vs 3 columns, mobile collapse of table columns into the secondary line, the empty state's "New transaction" opening the modal preset to the card and Expense, the all-done state with Past plans open, and "See later months" opening the right budget month.
14. C4 block (current and future): bar widths, the over state as a full destructive bar plus warning Alert with "Review budget" (keyboard reachable, correct aria-label), the reference note when under, "See details" disclosure keyboard toggling, and the account link visible only at lg+.
15. Future months: the "Starts {date}" chip, prev/next chevron aria-labels, the disabled next chevron at the horizon (tooltip and SR reachability, m7), the donut "Committed" centre in light/dark themes, no Budgeted/Actual tabs, the category rows' "{amount} committed" text, and the drawer's "Committed in {month}" list.
16. Budget-impact block in B1: red text contrast in light and `theme-dark`, the budget marker position at ~83% with no overflow when far over, the legend, and the single-month vs multi-month titles.
17. Phone width (375 px): the New transaction dialog with the recurring fields (container-query two-column grid), the B3 confirm buttons stacking, and the C3 dialog have no horizontal scroll.
