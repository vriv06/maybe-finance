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

  test "a disabled card still counts its plans by status but lists nothing upcoming" do
    @card.update!(status: "disabled")
    commitments = @card.recurring_commitments

    assert_equal BigDecimal("1299"), commitments.committed_per_month
    assert_equal BigDecimal("6000"), commitments.left_on_installments
    assert_equal Date.new(2027, 3, 15), commitments.last_installment_date
    assert_empty commitments.upcoming.items
  end
end
