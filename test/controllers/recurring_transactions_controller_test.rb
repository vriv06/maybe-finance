require "test_helper"

class RecurringTransactionsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 10, 8)
    sign_in users(:family_admin)
    @card = accounts(:credit_card)
    @card.entries.delete_all
    @frame = { "Turbo-Frame" => "recurring_preview" }
  end

  test "preview summarizes installments for a new purchase" do
    get preview_recurring_transactions_url, params: {
      entry: { account_id: @card.id, amount: "15000", currency: "USD", date: "2026-10-08" },
      recurrence: { plan_type: "installments", total_payments: "12", start_date: "2026-11-08" }
    }, headers: @frame

    assert_response :success
    assert_includes response.body, "12 installments of $1,250.00"
    assert_includes response.body, "Last on Oct 8, 2027"
  end

  test "preview stays empty while data is missing" do
    get preview_recurring_transactions_url, params: {
      entry: { account_id: @card.id, amount: "15000", currency: "USD", date: "2026-10-08" },
      recurrence: { plan_type: "installments", total_payments: "" }
    }, headers: @frame

    assert_response :success
    assert_includes response.body, %(<turbo-frame id="recurring_preview">)
    assert_not_includes response.body, "installments of"
  end

  test "preview shows the budget impact when asked" do
    family = families(:dylan_family)
    family.budgets.destroy_all
    family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                           currency: "USD", budgeted_spending: 1000, expected_income: 3000)

    get preview_recurring_transactions_url, params: {
      impact: "1",
      entry: { account_id: @card.id, amount: "3600", currency: "USD", date: "2026-10-08" },
      recurrence: { plan_type: "installments", total_payments: "3", start_date: "2026-11-08" }
    }, headers: @frame

    assert_includes response.body, "This puts 3 budgets over. The first is November 2026."
    assert_includes response.body, "Budget impact of the next 3 installments"
    assert_includes response.body, "Months without a budget use your October 2026 budget."
  end

  test "preview of an existing entry" do
    entry = create_transaction(account: @card, amount: 199, name: "Spotify", date: Date.new(2026, 6, 30))

    get preview_recurring_transactions_url, params: { entry_id: entry.id, recurrence: { plan_type: "charge" } }, headers: @frame

    assert_includes response.body, "$199.00 every month"
    assert_includes response.body, ERB::Util.html_escape("3 already due. They'll be added with their original dates.")
  end
end
