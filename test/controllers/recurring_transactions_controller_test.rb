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

  test "shows a plan with a safe stop confirm" do
    plan = create_charge

    get recurring_transaction_url(plan), headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_includes response.body, "Netflix"
    assert_includes response.body, "Save changes"
    assert_includes response.body, "Stop payments"
    assert_includes response.body, "Keep it"
  end

  test "a stopped plan is read-only" do
    plan = create_charge
    plan.cancel!

    get recurring_transaction_url(plan), headers: { "Turbo-Frame" => "modal" }

    assert_response :success
    assert_includes response.body, "Netflix"
    assert_not_includes response.body, "Save changes"
    assert_not_includes response.body, "Stop payments"
  end

  test "saves a charge's name and amount for future payments" do
    plan = create_charge

    patch recurring_transaction_url(plan), params: { recurring_transaction: { name: "Netflix Premium", amount: "349" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal "Netflix Premium", plan.reload.name
    assert_equal BigDecimal("349"), plan.amount
    assert_includes response.body, "Changes saved."
  end

  test "never changes an installment plan's total" do
    purchase = create_transaction(account: @card, amount: 1200, name: "Desk", date: Date.new(2026, 10, 1))
    plan = RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 3)

    patch recurring_transaction_url(plan), params: { recurring_transaction: { name: "Standing desk", amount: "1" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal "Standing desk", plan.reload.name
    assert_equal BigDecimal("1200"), plan.amount
  end

  test "invalid changes re-render the form with a 422" do
    plan = create_charge

    patch recurring_transaction_url(plan), params: { recurring_transaction: { name: "", amount: "299" } },
          headers: { "Turbo-Frame" => "modal" }

    assert_response :unprocessable_entity
    assert_equal "Netflix", plan.reload.name
  end

  test "a category from another family is rejected with a 422" do
    plan = create_charge
    foreign = families(:empty).categories.create!(name: "Foreign", color: "#aabbcc", lucide_icon: "shapes")

    patch recurring_transaction_url(plan), params: { recurring_transaction: { name: "Netflix", category_id: foreign.id } },
          headers: { "Turbo-Frame" => "modal" }

    assert_response :unprocessable_entity
    assert_nil plan.reload.category_id
  end

  test "a missing payload changes nothing and does not crash" do
    plan = create_charge

    patch recurring_transaction_url(plan), headers: { "Turbo-Frame" => "modal" }

    assert_response :redirect
    assert_equal "Netflix", plan.reload.name
  end

  test "a stopped plan cannot be edited or stopped again" do
    plan = create_charge
    plan.cancel!

    patch recurring_transaction_url(plan), params: { recurring_transaction: { name: "Renamed" } },
          headers: { "Turbo-Frame" => "modal" }
    assert_response :unprocessable_entity
    assert_equal "Netflix", plan.reload.name

    patch stop_recurring_transaction_url(plan), headers: { "Turbo-Frame" => "modal" }
    assert_response :unprocessable_entity
  end

  test "stops a plan" do
    plan = create_charge

    patch stop_recurring_transaction_url(plan), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal "cancelled", plan.reload.status
    assert_includes response.body, "Netflix stopped."
  end

  test "plans from other families are not found" do
    get recurring_transaction_url(SecureRandom.uuid), headers: { "Turbo-Frame" => "modal" }

    assert_response :not_found
  end

  private
    def create_charge
      families(:dylan_family).recurring_transactions.create!(
        account: @card, name: "Netflix", plan_type: "charge", amount: 299, currency: "USD", start_date: Date.new(2026, 10, 12)
      )
    end
end
