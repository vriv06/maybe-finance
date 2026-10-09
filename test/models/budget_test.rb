require "test_helper"

class BudgetTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
  end

  test "budget_date_valid? allows going back 2 years even without entries" do
    two_years_ago = 2.years.ago.beginning_of_month
    assert Budget.budget_date_valid?(two_years_ago, family: @family)
  end

  test "budget_date_valid? allows going back to earliest entry date if more than 2 years ago" do
    # Create an entry 3 years ago
    old_account = Account.create!(
      family: @family,
      accountable: Depository.new,
      name: "Old Account",
      status: "active",
      currency: "USD",
      balance: 1000
    )

    old_entry = Entry.create!(
      account: old_account,
      entryable: Transaction.new(category: categories(:income)),
      date: 3.years.ago,
      name: "Old Transaction",
      amount: 100,
      currency: "USD"
    )

    # Should allow going back to the old entry date
    assert Budget.budget_date_valid?(3.years.ago.beginning_of_month, family: @family)
  end

  test "budget_date_valid? does not allow dates before earliest entry or 2 years ago" do
    # Create an entry 1 year ago
    account = Account.create!(
      family: @family,
      accountable: Depository.new,
      name: "Test Account",
      status: "active",
      currency: "USD",
      balance: 500
    )

    Entry.create!(
      account: account,
      entryable: Transaction.new(category: categories(:income)),
      date: 1.year.ago,
      name: "Recent Transaction",
      amount: 100,
      currency: "USD"
    )

    # Should not allow going back more than 2 years
    refute Budget.budget_date_valid?(3.years.ago.beginning_of_month, family: @family)
  end

  test "budget_date_valid? allows planning up to 12 months ahead" do
    travel_to Date.new(2026, 10, 8)

    assert Budget.budget_date_valid?(Date.new(2027, 10, 1), family: @family)
    refute Budget.budget_date_valid?(Date.new(2027, 11, 1), family: @family)
  end

  test "the planning horizon follows custom month windows" do
    travel_to Date.new(2026, 10, 8)
    @family.update!(cycle_end_day: 27) # current month: Sep 28 - Oct 27

    assert Budget.budget_date_valid?(Date.new(2027, 10, 1), family: @family)  # Sep 28 - Oct 27, 2027
    refute Budget.budget_date_valid?(Date.new(2027, 11, 1), family: @family)  # Oct 28 - Nov 27, 2027
  end

  test "previous_budget_param returns nil when date is too old" do
    # Create a budget at the oldest allowed date
    two_years_ago = 2.years.ago.beginning_of_month
    budget = Budget.create!(
      family: @family,
      start_date: two_years_ago,
      end_date: two_years_ago.end_of_month,
      currency: "USD"
    )

    assert_nil budget.previous_budget_param
  end

  test "previous_budget_param returns param when date is valid" do
    budget = Budget.create!(
      family: @family,
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      currency: "USD"
    )

    assert_not_nil budget.previous_budget_param
  end

  test "name and param are keyed off end_date, not start_date" do
    budget = Budget.create!(
      family: @family,
      start_date: Date.new(2026, 8, 28),
      end_date: Date.new(2026, 9, 27),
      currency: "USD"
    )

    assert_equal "September 2026", budget.name
    assert_equal "sep-2026", budget.to_param
  end

  test "previous_budget returns the prior month's budget when it exists" do
    previous = Budget.create!(
      family: @family,
      start_date: 1.month.ago.beginning_of_month,
      end_date: 1.month.ago.end_of_month,
      currency: "USD"
    )

    current = Budget.create!(
      family: @family,
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      currency: "USD"
    )

    assert_equal previous, current.previous_budget
  end

  test "previous_budget returns nil when no prior budget exists" do
    current = Budget.create!(
      family: @family,
      start_date: Date.current.beginning_of_month,
      end_date: Date.current.end_of_month,
      currency: "USD"
    )

    assert_nil current.previous_budget
  end

  test "copy_categories_from! copies budgeted_spending per category and leaves other budgets untouched" do
    previous = Budget.find_or_bootstrap(@family, start_date: 1.month.ago)
    current = Budget.find_or_bootstrap(@family, start_date: Date.current)

    previous.budget_categories.find_by(category: categories(:one)).update!(budgeted_spending: 250)

    current.copy_categories_from!(previous)

    assert_equal 250, current.budget_categories.find_by(category: categories(:one)).budgeted_spending
    assert_equal 250, previous.budget_categories.find_by(category: categories(:one)).budgeted_spending
  end

  test "realign_to_cycle! shifts existing budgets to the new cycle window and preserves budgeted_spending" do
    budget = Budget.create!(
      family: @family,
      start_date: Date.new(2026, 9, 1),
      end_date: Date.new(2026, 9, 30),
      budgeted_spending: 5000,
      currency: "USD"
    )

    @family.update_column(:cycle_end_day, 27)
    Budget.realign_to_cycle!(@family)
    budget.reload

    assert_equal Date.new(2026, 8, 28), budget.start_date
    assert_equal Date.new(2026, 9, 27), budget.end_date
    assert_equal 5000, budget.budgeted_spending
  end

  test "compares commitments with the latest configured budget when a month has none" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.budgets.destroy_all
    accounts(:credit_card).entries.delete_all
    october = family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                                     currency: "USD", budgeted_spending: 1000, expected_income: 2000)
    family.recurring_transactions.create!(account: accounts(:credit_card), name: "Rent", plan_type: "charge",
                                          amount: 1200, currency: "USD", start_date: Date.new(2026, 10, 5))

    december = Budget.for_cycle(family, Date.new(2026, 12, 1))

    assert december.new_record?
    assert_equal BigDecimal("1200"), december.committed_spending
    assert_equal october, december.basis_budget
    assert december.uses_reference_budget?
    assert december.commitments_over_budget?
    assert_equal BigDecimal("200"), december.commitments_overage
    assert_equal 120, december.commitments_percent
  end

  test "commitments percent rounds down while under budget" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.budgets.destroy_all
    accounts(:credit_card).entries.delete_all
    october = family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                                     currency: "USD", budgeted_spending: 1000, expected_income: 2000)
    family.recurring_transactions.create!(account: accounts(:credit_card), name: "Gym", plan_type: "charge",
                                          amount: BigDecimal("999.50"), currency: "USD", start_date: Date.new(2026, 10, 20))

    assert_not october.commitments_over_budget?
    assert_equal 99, october.commitments_percent
    assert_not october.uses_reference_budget?
  end

  test "the basis budget is looked up once per instance" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.budgets.destroy_all
    family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                           currency: "USD", budgeted_spending: 1000, expected_income: 2000)
    december = Budget.for_cycle(family, Date.new(2026, 12, 1))

    december.expects(:latest_initialized_budget_before).once.returns(nil)

    2.times { december.basis_budget }
  end

  test "past months never borrow another budget" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.budgets.destroy_all
    family.budgets.create!(start_date: Date.new(2026, 8, 1), end_date: Date.new(2026, 8, 31),
                           currency: "USD", budgeted_spending: 1000, expected_income: 2000)

    september = Budget.for_cycle(family, Date.new(2026, 9, 1))

    assert september.past?
    assert_nil september.basis_budget
    assert_nil september.commitments_percent
  end

  test "commitments overage is always a BigDecimal" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.budgets.destroy_all
    accounts(:credit_card).entries.delete_all

    october = family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                                     currency: "USD", budgeted_spending: 1000, expected_income: 2000)

    assert_kind_of BigDecimal, october.commitments_overage
    assert_equal 0, october.commitments_overage
  end

  test "future and past follow the family's today" do
    family = families(:dylan_family)
    family.update!(timezone: "Pacific/Auckland")
    travel_to Time.utc(2026, 10, 31, 20, 0) # Nov 1 in Auckland, Oct 31 in UTC

    assert_equal Date.new(2026, 11, 1), family.today
    assert Budget.for_cycle(family, Date.new(2026, 10, 15)).past?
    assert_not Budget.for_cycle(family, Date.new(2026, 11, 15)).past?
    assert_not Budget.for_cycle(family, Date.new(2026, 11, 15)).future?
  end

  test "a charge dated after the cycle end lands in the next cycle" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.update!(cycle_end_day: 27)
    family.budgets.destroy_all
    accounts(:credit_card).entries.delete_all
    family.recurring_transactions.create!(account: accounts(:credit_card), name: "Gym", plan_type: "charge",
                                          amount: 50, currency: "USD", start_date: Date.new(2026, 9, 28))

    current = Budget.for_cycle(family, Date.new(2026, 10, 8)) # Sep 28 - Oct 27
    following = Budget.for_cycle(family, Date.new(2026, 10, 28)) # Oct 28 - Nov 27

    assert_equal Date.new(2026, 10, 27), current.end_date
    assert_equal BigDecimal("50"), current.committed_spending # Oct 28 occurrence is not here (Sep 28 is generated)
    assert_equal BigDecimal("50"), following.committed_spending
    assert_equal [ Date.new(2026, 10, 28) ], following.recurring_commitments.items.map(&:date)
  end

  test "next_budget_param moves past the current month until the horizon" do
    travel_to Date.new(2026, 10, 8)
    current = Budget.create!(family: @family, start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31), currency: "USD")
    last = Budget.create!(family: @family, start_date: Date.new(2027, 10, 1), end_date: Date.new(2027, 10, 31), currency: "USD")

    assert_equal "nov-2026", current.next_budget_param
    assert_nil last.next_budget_param
  end

  test "future months show committed amounts where spending would be" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.budgets.destroy_all
    accounts(:credit_card).entries.delete_all
    family.recurring_transactions.create!(account: accounts(:credit_card), name: "Club", plan_type: "charge",
                                          amount: 300, currency: "USD", start_date: Date.new(2026, 10, 15),
                                          category: categories(:food_and_drink))

    december = Budget.find_or_bootstrap(family, start_date: Date.new(2026, 12, 1))
    food = december.budget_categories.find { |bc| bc.category == categories(:food_and_drink) }

    assert december.future?
    assert_equal BigDecimal("300"), december.actual_spending
    assert_equal BigDecimal("300"), food.actual_spending
  end

  test "current and past months keep reporting real spending, never commitments" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.budgets.destroy_all
    accounts(:credit_card).entries.delete_all
    food = categories(:food_and_drink)
    family.recurring_transactions.create!(account: accounts(:credit_card), name: "Club", plan_type: "charge",
                                          amount: 300, currency: "USD", start_date: Date.new(2026, 10, 15),
                                          category: food)
    create_transaction(account: accounts(:depository), date: Date.new(2026, 10, 2), amount: 40, category: food)
    create_transaction(account: accounts(:depository), date: Date.new(2026, 9, 12), amount: 25, category: food)

    [ Date.new(2026, 10, 1), Date.new(2026, 9, 1) ].each do |month|
      budget = Budget.find_or_bootstrap(family, start_date: month)
      totals = family.income_statement.expense_totals(period: budget.period)
      row = budget.budget_categories.find { |bc| bc.category == food }
      food_total = totals.category_totals.find { |ct| ct.category.id == food.id }&.total || 0

      assert_not budget.future?
      assert_equal totals.total, budget.actual_spending
      assert_equal food_total, row.actual_spending
    end

    assert budget_with_upcoming = Budget.find_or_bootstrap(family, start_date: Date.new(2026, 10, 1))
    assert_operator budget_with_upcoming.committed_spending, :>, budget_with_upcoming.actual_spending
  end

  test "previous_budget of a future month is the latest configured one" do
    travel_to Date.new(2026, 10, 8)
    family = families(:dylan_family)
    family.budgets.destroy_all
    october = family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                                     currency: "USD", budgeted_spending: 1000, expected_income: 2000)
    family.budgets.create!(start_date: Date.new(2026, 11, 1), end_date: Date.new(2026, 11, 30), currency: "USD")
    december = family.budgets.create!(start_date: Date.new(2026, 12, 1), end_date: Date.new(2026, 12, 31), currency: "USD")

    assert_equal october, december.previous_budget
  end
end
