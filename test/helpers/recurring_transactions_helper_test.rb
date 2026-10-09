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
