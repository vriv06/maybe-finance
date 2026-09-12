require "test_helper"

class BudgetTest < ActiveSupport::TestCase
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

  test "budget_date_valid? does not allow future dates beyond current month" do
    refute Budget.budget_date_valid?(2.months.from_now, family: @family)
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
end
