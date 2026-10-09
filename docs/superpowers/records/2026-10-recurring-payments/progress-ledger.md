# SDD progress — Phase A plan
Task 1: complete (commits ebf96a96, aa37d8f7 schema; migrated test+prod DBs)
Note: Task 2 deferred belongs_to :recurring_transaction to Task 5 (breaks TransactionImport without model)
Task 2: complete (commits aa37d8f..a1c8d32, review clean)
  Minor (for final review): no test asserts BUDGET/BALANCE_EXCLUDED_KINDS stay in sync with enum :kind; sql-quoting test duplicates constant literal (plan-mandated)
  Task 5 must add: belongs_to :recurring_transaction, optional: true in Transaction
Task 3: complete (commits a1c8d32..e98a0ff, review clean)
  Minor: search.rb:96/112 filters keep own kind lists (no msi_purchase/installment) — check in Phase B/C; search totals cache may serve stale values post-deploy; search test only asserts expense_money
  Baseline: test/controllers + test/jobs have 16 failures / 112 errors before Phase A
Task 4: complete (commits e98a0ff..2df92bc, review clean)
  Minor: sync_cache.rb map block indentation; no direct reverse-calculator test
Task 5: complete (commits 2df92bc..a87bc0a, review clean after fix round 1: Account/Category/Merchant has_many recurring_transactions for FK-safe deletes; linked-installment tests)
  Minor: RecurringTransaction#upcoming ignores status (callers must use .active); account delete test uses Account.find workaround for stale association
Task 6: complete (commits a87bc0a..4481ee3, review clean)
  Minor: sync_later once/never not pinned by test; generated entry amounts not asserted; RecordNotUnique branch untested; update! before sync_later (edge: validation failure skips sync)
Task 7: complete (commits 4481ee3..27035a8, review clean)
  Minor: create_from_entry! no guard for non-Transaction entry or entry already linked to a plan; negative amounts raise RecordInvalid (surface in Phase B); no past-dated charge / explicit start_date tests
Task 8: complete (commits 27035a8..aaee14d, review clean; deviation: include RecurringGeneration on own line after multi-arg include — multi-arg include applies right-to-left)
  Minor: once-per-day guard check-then-update not atomic (redundant job worst case, generate_due! idempotent); flag set before job runs; one exists? query/family/day; no unauthenticated-request test
Task 9: complete (verification: same 124 pre-existing failures as aa37d8f, rubocop clean, design-state updated)
Final review (aa37d8f..a633db5): ready to merge (no UI can create plans yet). 3 Important to fix at start of Phase B — see final-review.md:
  I1 deleted occurrence regenerates next day; I2 deleting msi_purchase orphans active plan (and plan destroy leaves purchase excluded); I3 kind can be overwritten on plan-linked rows (one-time toggle, transfer matchers, transfer destroy)
Task 10: complete (commits a633db5..65a21ac, review clean) — I1 watermark, I2 purchase delete cascades plan, I3 kind lock + transfer exclusion
  Phase B carry-over: reset last_generated_on on schedule edits; guard create_from_entry! (standard, non-transfer only); rescue RecordInvalid in TransferMatches#create + one-time toggle (500 today); bulk delete purchase+installments untested; job date UTC vs family tz; plans on non-manual/disabled accounts; Category#replace_and_destroy! nullifies plan category; one invalid plan stops family job

# Phases B+C plan (docs/superpowers/plans/2026-10-08-recurring-transactions-phases-b-c.md) — briefs/reports in .superpowers/sdd/bc/
Plan committed ece22c7. Default taken: budget basis falls back to latest configured budget for the current month too.
BC Task 1: complete (ece22c7..1dd125f, review clean) — Minor: broken plan retried daily silently (Sentry covers); generate_due! partial-failure leaves last_generated_on unadvanced (idempotent)
BC Task 2: complete (1dd125f..24af469, review clean) — Minor: range/credit validations run on every update (scope to create?); lock test only covers total_payments
BC Task 3: complete (24af469..21f9d78, review clean after fix round 1: foreign_currency ineligibility, family.today future?/past?, BigDecimal overage, boundary tests) — Minor: N+1 plan.upcoming per plan; budget_test.rb:246 wrong comment; family currency change edge case; b.err.foreign_currency needs content review
BC Task 4: complete (21f9d78..cc00d98, review clean) — Minor: Budget#current? now unused; no test pinning current/past actual_spending unchanged
BC Task 5: complete (cc00d98..d75f329, review clean) — Minor: no FUTURE_CYCLES_LIMIT cap in BudgetImpact; scale/width raise with no months (views must check available?); no backdated parity test
BC Task 6: complete (d75f329..a7f6ffe, review clean) — Minor: headline figures use all active plans vs upcoming uses generatable (disabled/non-manual card mismatch); parity test single-card/Nov only
BC Task 7: complete (a7f6ffe..9f941d6, review: Important fixed — returnValue reset before showModal, verified by controller diff check) — Minor: for_msi_purchase_deletion assumes plan present; no JS test for focus/Esc (Task 18 browser check); biome not installed locally (npm install needed for Task 18)
BC Task 8: complete (9f941d6..dc798b3, review clean) — Minor: LOCKED_MESSAGE duplicated in controller; rescue path (matched entry locked) untested
BC Task 9: complete (dc798b3..ecf5847, review clean) — Minor: no tests for cross-family ids/no-persistence in preview; bogus currency -> 500 in helper; b2.summary_unavailable fallback not wired
BC Task 10: complete (ecf5847..8bcd251, review clean after fix rounds 1-2: stale preview discard, visible credit-only note, watched fields, retry, live region outside disclosure, shared credit rule) — Task 18 browser checklist: Esc/backdrop, closing disclosure with invalid installment count, aria-busy, JS lint (biome missing)
BC Task 11: complete (8bcd251..762e977, review clean after fix round 1) — Task 18 checklist: non-credit installments 422 focus/duplicate note; 422 resets date to today; Income 422 shows Expense tab. Minor: unexpected-failure test lacks travel_to
BC Task 12: complete (762e977..c81317e, review clean after fix round 1) — Task 18: stale drawer after one-time toggle; fieldset aria-describedby; confirm heading autofocus in browser. Minor: StandardError branch untested (local? re-raise); weak assertions in 2 new tests; T14 must consume @focus_provenance
BC Task 13: complete (c81317e..dba5db5, review clean after fix round 1) — Minor: edit-confirm test uses any_instance stub; DB query in show.html.erb (move to controller); Rails default 'Amount is not a number' outside copy doc
BC Task 14: complete (dba5db5..b4b9789, review clean after fix round 1: server-side amount lock on installment/msi_purchase, kind_in_database copy) — Minor: API full_messages 'Amount Set by the plan.'; weak Exclude assertion; show.html.erb:134-157 indentation. Task 18: mobile provenance, autofocus after convert, delete confirms
BC Task 15: complete (b4b9789..eeb048b, review clean after fix round 1: status-based figures/tables, Upcoming gated by generation & hidden when empty, :transactions preload) — Minor: 'See later months' lost when only far-future plans; every credit card now shows the tab (design-mandated, flag to Victor); commitment_row account order/breakpoint -> C4 review
BC Task 16: complete (eeb048b..e2a21f8, review clean) — FOR FINAL FIX: over budget on borrowed basis, alert title names the viewed month while percent names the basis month (fix: title should name basis month); use *_money helpers; memoize basis_budget; tests for past month + borrowed-over. Future months for no-plan families show 'Nothing committed' box (brief-mandated)
BC Task 17: complete (e2a21f8..f273012, review clean) — FOR FINAL FIX: future-only donut amount missing tabular-nums; drawer Overview label uses start month ('Nov 2026 committed' vs 'Committed in December 2026') -> use budget.name; extra mb-2 under Expected income in future; tests: current-month regression guard, edit autofill branch
BC final review + fix round: complete (f273012..8bbe755): I1-I6 + minors + biome; suite identical failing names vs ece22c7 (16F/118E); rubocop/erb_lint/biome clean; brakeman 0 errors
Browser verification (2026-10-09): budget C4 + future month + capture preview/impact + submit + list rows + installment drawer + plan dialog + stop confirm (Keep it focus, Escape cancels) + B3 status/Edit + mobile budget/card OK. Bug found+fixed: card tab KPIs/tables overflowed in narrow column -> container queries (07aee65). Demo data removed from maybe_test.
