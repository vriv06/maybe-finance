require "test_helper"

class RecurringTransactionsHelperTest < ActionView::TestCase
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 10, 8)
    @card = accounts(:credit_card)
    @card.entries.delete_all
    @family = families(:dylan_family)
  end

  test "summarizes installments in two lines" do
    plan = build(amount: 15000, total_payments: 12, start_date: Date.new(2026, 11, 8))
    summary = recurring_summary(plan, as_of: Date.new(2026, 10, 8))

    assert_equal "credit-card", summary.icon
    assert_equal "12 payments of $1,250.00", summary.line1
    assert_equal "Last on Oct 8, 2027", summary.line2
    assert_nil summary.past_due
    assert_equal "12 payments of $1,250.00, last on Oct 8, 2027", summary.announcement
  end

  test "names an uneven last installment" do
    plan = build(amount: 10000, total_payments: 6, start_date: Date.new(2026, 10, 27))

    assert_equal "Last one $1,666.70 on Mar 27, 2027", recurring_summary(plan, as_of: Date.new(2026, 10, 8)).line2
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
    assert_equal [ "Monthly charge", "Weekly charge", "Bimonthly charge", "Annual charge" ],
                 %w[monthly weekly bimonthly annual].map { |frequency| recurring_occurrence_label(build(plan_type: "charge", total_payments: nil, frequency: frequency), 3) }
    assert_equal [ "None", "Daily", "Weekly", "Monthly", "Bimonthly", "Quarterly", "Biannually", "Annually" ],
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

  test "describes where a transaction comes from" do
    purchase = create_transaction(account: @card, amount: 1200, name: "Desk", date: Date.new(2026, 8, 20))
    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 12)

    assert_equal "Paid in 12 installments", recurring_provenance_label(purchase.transaction)
    assert_equal "Installment 1 of 12", recurring_provenance_label(plan.transactions.find_by(installment_number: 1))
    assert_equal "One time", recurring_status_text(create_transaction(account: @card, amount: 10).transaction)
  end

  test "the drawer status of a payment off a card counts payments" do
    purchase = create_transaction(account: accounts(:depository), amount: 1200, name: "Desk", date: Date.new(2026, 8, 20))
    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 12)

    assert_equal "Payment 1 of 12", recurring_provenance_label(purchase.reload.entryable)
    assert_equal "Payments · , 1 of 12", strip_tags(recurring_status_text(purchase.entryable)).squish
    assert_equal "Payment 2 of 12", recurring_provenance_label(plan.transactions.find_by(installment_number: 2))
  end

  test "a foreign-currency one-time expense shows no recurrence block" do
    entry = create_transaction(account: @card, amount: 100, currency: "EUR")
    entry.entryable.update!(kind: "one_time")

    assert_nil recurrence_block_state(entry)
  end

  test "each projection bar has a spoken summary" do
    budget = stub(name: "November 2026", currency: "USD")
    over = stub(budget: budget, total: BigDecimal("7801"), basis: BigDecimal("7500"), over?: true, overage: BigDecimal("301"))
    under = stub(budget: budget, total: BigDecimal("7301"), basis: BigDecimal("7500"), over?: false, overage: BigDecimal("-199"))

    assert_equal "November 2026: $7,801.00 of $7,500.00, $301.00 over", budget_impact_month_summary(over)
    assert_equal "November 2026: $7,301.00 of $7,500.00, $199.00 left", budget_impact_month_summary(under)
  end

  private
    def build(plan_type: "installments", amount: 1000, total_payments: 3, start_date: Date.new(2026, 11, 8), frequency: "monthly", account: @card)
      RecurringTransaction.new(family: @family, account: account, name: "Plan", plan_type: plan_type, frequency: frequency,
                               amount: amount, currency: "USD", total_payments: total_payments, start_date: start_date)
    end
end
