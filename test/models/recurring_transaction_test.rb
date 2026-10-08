require "test_helper"

class RecurringTransactionTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @credit_card = accounts(:credit_card)
    @credit_card.entries.delete_all
  end

  test "splits installments so the last payment absorbs rounding" do
    plan = build_plan

    assert_equal [ BigDecimal("333.33"), BigDecimal("333.33"), BigDecimal("333.34") ],
                 (1..3).map { |n| plan.occurrence_amount(n) }
  end

  test "clamps occurrence dates to the end of shorter months" do
    plan = build_plan(start_date: Date.new(2026, 1, 31))

    assert_equal [ Date.new(2026, 1, 31), Date.new(2026, 2, 28), Date.new(2026, 3, 31) ],
                 (1..3).map { |n| plan.occurrence_date(n) }
    assert_equal Date.new(2026, 3, 31), plan.end_date
  end

  test "installments require a credit card and at least two payments" do
    assert build_plan.valid?
    assert_not build_plan(account: accounts(:depository)).valid?
    assert_not build_plan(total_payments: 1).valid?
  end

  test "upcoming lists occurrences up to a date" do
    plan = build_plan(start_date: Date.new(2026, 1, 15))
    plan.save!

    assert_equal [ 1, 2 ], plan.upcoming(through: Date.new(2026, 2, 20)).map(&:number)
  end

  test "charges without total payments repeat open-ended" do
    plan = build_plan(plan_type: "charge", total_payments: nil, amount: 299, start_date: Date.new(2026, 1, 10))

    assert plan.valid?
    assert_equal 12, plan.upcoming(through: Date.new(2026, 12, 31)).size
    assert_nil plan.end_date
  end

  test "cancel! stops the plan" do
    plan = build_plan
    plan.save!
    plan.cancel!

    assert_equal "cancelled", plan.reload.status
  end

  private
    def build_plan(**attributes)
      RecurringTransaction.new({
        family: @family,
        account: @credit_card,
        name: "Laptop",
        plan_type: "installments",
        amount: 1000,
        currency: "USD",
        start_date: Date.new(2026, 1, 15),
        total_payments: 3
      }.merge(attributes))
    end
end
