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
