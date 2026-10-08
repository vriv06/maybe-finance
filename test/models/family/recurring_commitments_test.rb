require "test_helper"

class Family::RecurringCommitmentsTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 10, 8)
    @family = families(:dylan_family)
    @card = accounts(:credit_card)
    @card.entries.delete_all
  end

  test "counts generated rows and upcoming occurrences in the range, never the purchase" do
    purchase = create_transaction(account: @card, amount: 3000, name: "Laptop", date: Date.new(2026, 8, 20))
    RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 3) # Sep 20 generated, Oct 20 upcoming

    commitments = @family.recurring_commitments(start_date: Date.new(2026, 8, 1), end_date: Date.new(2026, 10, 31))

    assert_equal [ 1, 2 ], commitments.items.map(&:number)
    assert_equal [ true, false ], commitments.items.map(&:generated?)
    assert_equal BigDecimal("2000"), commitments.total
  end

  test "rolls subcategory commitments into the parent and keeps uncategorized apart" do
    create_charge(name: "Dinner club", amount: 100, start_date: Date.new(2026, 10, 15), category: categories(:subcategory))
    create_charge(name: "Gym", amount: 50, start_date: Date.new(2026, 10, 16))

    commitments = @family.recurring_commitments(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31))

    assert_equal BigDecimal("100"), commitments.total_for(categories(:food_and_drink))
    assert_equal BigDecimal("100"), commitments.total_for(categories(:subcategory))
    assert_equal BigDecimal("50"), commitments.total_for(@family.categories.uncategorized)
  end

  test "generated rows the user excluded are not counted, like budget spending" do
    plan = create_charge(name: "Gym", amount: 50, start_date: Date.new(2026, 10, 1))
    plan.generate_due!
    entry = plan.transactions.first.entry
    range = { start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31) }

    assert_equal BigDecimal("50"), @family.recurring_commitments(**range).total
    entry.update!(excluded: true)
    assert_equal BigDecimal("0"), @family.recurring_commitments(**range).total
  end

  test "stopped plans add nothing new" do
    create_charge(name: "Gym", amount: 50, start_date: Date.new(2026, 10, 16)).cancel!

    commitments = @family.recurring_commitments(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 12, 31))

    assert_empty commitments.items
  end

  private
    def create_charge(name:, amount:, start_date:, category: nil)
      @family.recurring_transactions.create!(
        account: @card, name: name, plan_type: "charge", amount: amount, currency: "USD", start_date: start_date, category: category
      )
    end
end
