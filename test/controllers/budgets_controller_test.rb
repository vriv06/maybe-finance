require "test_helper"

class BudgetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Date.new(2026, 10, 8)
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    @family.budgets.destroy_all
    accounts(:credit_card).entries.delete_all
    @family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                            currency: "USD", budgeted_spending: 1000, expected_income: 3000)
    @family.recurring_transactions.create!(account: accounts(:credit_card), name: "Rent", plan_type: "charge",
                                           amount: 1200, currency: "USD", start_date: Date.new(2026, 10, 5))
    @frame = { "Turbo-Frame" => "budget" }
  end

  test "the current month shows recurring commitments and the warning" do
    get budget_url("oct-2026"), headers: @frame

    assert_response :success
    assert_includes response.body, "committed to recurring payments"
    assert_includes response.body, "120% of your budget"
    assert_includes response.body, "Recurring payments are $200.00 over your October 2026 budget"
    assert_includes response.body, "Review budget"
  end

  test "a month using another month's budget names it and has no warning when under" do
    @family.recurring_transactions.update_all(amount: 500)

    get budget_url("nov-2026"), headers: @frame

    assert_response :success
    assert_includes response.body, "50% of your October 2026 budget"
    assert_includes response.body, "Compared with your October 2026 budget. Set up November 2026 to use its own."
    assert_not_includes response.body, "Review budget"
  end

  test "a future month without commitments shows the empty box and a family without plans shows nothing" do
    @family.recurring_transactions.destroy_all

    get budget_url("oct-2026"), headers: @frame
    assert_response :success
    assert_not_includes response.body, "committed to recurring payments"
    assert_not_includes response.body, "Nothing committed"

    get budget_url("dec-2026"), headers: @frame
    assert_response :success
    assert_includes response.body, "Nothing committed for December 2026 yet"
  end

  test "a future month shows what is committed, not spent" do
    get budget_url("dec-2026"), headers: @frame

    assert_response :success
    assert_includes response.body, "Committed"
    assert_includes response.body, "Starts"
    assert_includes response.body, "120% of your October 2026 budget"
    assert_includes response.body, %(aria-label="Previous budget: November 2026")
  end

  test "the last plannable month disables the next chevron with a reason" do
    get budget_url("oct-2027"), headers: @frame

    assert_response :success
    assert_includes response.body, "You can plan up to 12 months ahead."
  end

  test "months past the planning horizon are not found" do
    get budget_url("nov-2027"), headers: @frame

    assert_response :not_found
  end

  test "a borrowed future month names the basis month in the over-budget alert" do
    get budget_url("dec-2026"), headers: @frame

    assert_response :success
    assert_includes response.body, "Recurring payments are $200.00 over your October 2026 budget"
    assert_not_includes response.body, "over your December 2026 budget"
    assert_includes response.body, %(aria-label="Review December 2026 budget")
  end

  test "a future category drawer lists its commitments" do
    get budget_budget_category_url("dec-2026", BudgetCategory.uncategorized.id), headers: { "Turbo-Frame" => "drawer" }

    assert_response :success
    assert_includes response.body, "Committed in December 2026"
    assert_includes response.body, "Rent"
  end
end
