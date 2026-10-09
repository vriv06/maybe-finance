# Handoff — Pagos recurrentes y MSI

_Last updated: 2026-10-09. Branch: `feature/meses-sin-intereses` (pushed to `origin`)._

Read this first when resuming on another computer. Also read `design-state.md` at the repo root, which is the Designpowers state and holds every decision.

---

## 1. Where we are

**The feature is built, reviewed and browser-tested. It is NOT merged to `main` yet.**

| Phase | What | Status |
|---|---|---|
| Discovery / brief / strategy | Designpowers | ✅ Approved |
| Taste / content / interaction / visual | Designpowers | ✅ Approved (final canvas = visual source of truth) |
| **Phase A**: data and numbers | `RecurringTransaction` model, `msi_purchase` / `installment` kinds, shared exclusions, idempotent generation, daily trigger | ✅ Done (Tasks 1–10 + final review) |
| **Phase B**: capture | Form fields + live summary + budget impact; convert an existing transaction | ✅ Done |
| **Phase C**: views | Generated rows, plan dialog, card tab, budget block + warning, future budgets (12 months) | ✅ Done |
| Browser verification | On :3001 against `maybe_test`, compared with the canvas | ✅ Done. One bug found and fixed: the card tab overflowed in a narrow column, now handled with container queries |
| Merge / PR | — | ⏳ Pending (Victor decides) |

### Pending for Victor (decisions, not code)
1. **Copy review** of 3 provisional strings in `docs/designpowers/content/2026-10-08-pagos-recurrentes-msi-copy.md`:
   - `b.err.foreign_currency` ("Recurring payments only work in your main currency.")
   - `bi.title_over_multi`
   - `bi.reference`
2. **Confirm** that every credit card shows the "Recurring payments" tab (with an empty state when the card has no plans). The design calls for it, but it is a visible change.
3. Decide **merge to `main` or a PR**.

### Defaults taken without asking (all recorded in `design-state.md`)
- Only transactions in the family's main currency can become a plan.
- A monthly charge's "Ends after" is capped at 600 payments.
- The amount of installments and of the MSI purchase is locked on the server. The date stays editable.
- When a month has no budget of its own (current or future), commitments are compared with the latest configured budget. Past months never borrow one.
- Card tab: the figures and tables count plans by status. "Upcoming" only lists plans that can still generate (manual, active account).
- Impact-block red text uses `text-red-700 theme-dark:text-red-400` (passes AA); the bars use `bg-destructive`.

---

## 2. Key documents

| What | Where |
|---|---|
| Design state (decisions, open questions, handoffs) | `design-state.md` |
| Brief / strategy / design plan | `docs/designpowers/briefs/`, `strategy/`, `plans/` |
| Taste | `docs/designpowers/taste/2026-10-08-pagos-recurrentes-msi-taste.md` |
| Copy (final strings by id; the "Kept" tables are the source of truth) | `docs/designpowers/content/2026-10-08-pagos-recurrentes-msi-copy.md` |
| Interaction spec | `docs/designpowers/interaction/2026-10-08-pagos-recurrentes-msi-interaction.md` |
| Visual spec | `docs/designpowers/visual/2026-10-08-pagos-recurrentes-msi-visual.md` |
| **Final canvas** (exported copy, visual source of truth) | `docs/designpowers/visual/canvas/*.dc.html`, plus `CHANGES-from-rev2.md` |
| Editable canvas (Claude Design, private) | https://claude.ai/artifact/1gVBYF2NsiBFS45AoPC1JT |
| Code plan, Phase A | `docs/superpowers/plans/2026-10-06-recurring-transactions-phase-a.md` |
| Code plan, Phases B + C | `docs/superpowers/plans/2026-10-08-recurring-transactions-phases-b-c.md` |
| Execution ledger (per-task reviews, accumulated minors) | `docs/superpowers/records/2026-10-recurring-payments/progress-ledger.md` |
| Final reviews and fix report | `docs/superpowers/records/2026-10-recurring-payments/*.md` |

> `.superpowers/` (the working ledger) is git-excluded and does NOT travel. A copy lives in `docs/superpowers/records/…`.

---

## 3. Set up on a new computer

Local Ruby is NOT used. Everything runs in Docker (OrbStack / Docker Desktop).

```bash
git clone git@github.com:vriv06/maybe-finance.git
cd maybe-finance
git checkout feature/meses-sin-intereses
```

1. Create `.env` from `.env.example`. It needs `SECRET_KEY_BASE` (compose fails without it):
   ```bash
   openssl rand -hex 64
   ```
2. Start the database and Redis, then build the image:
   ```bash
   docker compose -f compose.yaml up -d db redis
   docker compose -f compose.yaml build web
   ```
3. **Migrations.** This branch adds `db/migrate/20261006120000_create_recurring_transactions.rb`. Per CLAUDE.md, Claude never runs migrations; run them yourself:
   ```bash
   docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails db:prepare
   docker compose -f compose.yaml run --rm -v "$PWD:/rails" web bin/rails db:migrate
   ```
   (The second command migrates the default database, `maybe_production`.)
4. JS dependencies (for Biome / `npm run lint`): `npm ci`.

### Tests
```bash
docker compose -f compose.yaml run --rm -v "$PWD:/rails" -e RAILS_ENV=test -e POSTGRES_DB=maybe_test web bin/rails test test/models test/jobs test/controllers test/helpers test/components
```
**Known baseline:** 16 failures + 118 errors that already existed before this work, mostly `The asset 'tailwind.css' was not found` (assets aren't built in the bind mount) plus `Provider::PlaidTest`. This branch adds no new failing test names. Compare by name, not by count.

Lint and security: `bin/rubocop`, `bundle exec erb_lint <files>`, `bundle exec brakeman --no-pager` (`bin/brakeman` aborts because the installed version is outdated), `npm run lint`. All run in the same docker container except npm.

### Test environment in the browser (:3001 against `maybe_test`)
```bash
docker compose -f compose.yaml build web
docker compose -f compose.yaml -f docs/dev/compose.test-db.yaml up -d --no-deps web worker
```
- http://localhost:3001. Use a fixture user with real data: `bob@bobdylan.com`. Its password is the one in `test/test_helper.rb` (`user_password_test`).
- ⚠️ Running `bin/rails test` reloads the fixtures in `maybe_test` and wipes anything created in the UI. Demo data that references fixtures (plans, a bootstrapped future budget) can make the fixture load fail with FK errors. To clean up:
  ```bash
  docker compose -f compose.yaml exec -T web bin/rails runner 'Transaction.where.not(recurring_transaction_id: nil).update_all(recurring_transaction_id: nil, installment_number: nil); RecurringTransaction.delete_all; BudgetCategory.where.not(budget_id: Budget.select(:id)).delete_all'
  ```
- ⚠️ The `maybe-finance:local` image tag is shared with a real instance (compose project `maybe-finance`, port 3000). Rebuilding the image does not touch running containers. Recreating the real instance would run this branch's code.

---

## 4. What's left (optional, non-blocking)

Deferred minors from the final reviews. Full detail is in `docs/superpowers/records/2026-10-recurring-payments/phases-b-c-final-review.md`, items m4–m17.
- Preload `entryable: :recurring_transaction` in the account activity feed (one query per plan row).
- Tampered `recurrence=foo` / `entry=foo` params give a 500 (the same pattern already exists in `create`).
- The disabled "next" chevron (12-month limit) can't be reached by keyboard.
- `Budget.budget_date_valid?` / `current_param` use `Date.current` while `future?` / `past?` use `family.today`.
- `RecurringTransactionsController#stop` doesn't rescue `cancel!`.
- Editing a plan whose category is not an expense category preselects "Uncategorized".
- There is a DB query in `recurring_transactions/show.html.erb`; move it to the controller.
- `Budget#current?` is no longer used.
- "See later months" disappears when the only plans are far in the future.
- Test gaps listed in the ledger (bulk delete of purchase + installments, a backdated parity test, and others).

### Browser checks still worth a manual pass
Most of the checklist was covered (see `phases-b-c-final-review.md`, BROWSER CHECKLIST). Not yet exercised:
- The stale drawer after toggling "One-time Expense".
- A 422 on Income showing the Expense tab.
- Bulk delete of a purchase together with its installments.

---

## 5. Commit history (summary)

- Phase A: `ebf96a96` … `283d5cd5` (migration through review fixes).
- Design: `8809c05c` (taste, content, interaction, visual, canvas).
- Phases B + C plan: `ece22c7f`.
- Phases B + C build: `1dd125f6` … `8bbe7555` (18 tasks + reviews + final fix round).
- Card tab fix from browser testing: `07aee65a`. Design state closed out: `7b3c580e`.

To resume with Claude on another computer, say something like: "read `docs/HANDOFF-recurring-payments.md` and `design-state.md` and pick up where we left off".
