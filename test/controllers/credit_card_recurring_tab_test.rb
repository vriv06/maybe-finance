require "test_helper"

class CreditCardRecurringTabTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 10, 8)
    sign_in users(:family_admin)
    @card = accounts(:credit_card)
    @card.entries.delete_all
  end

  test "shows the card's commitments" do
    purchase = create_transaction(account: @card, amount: 6000, name: "Sofa", date: Date.new(2026, 9, 15))
    RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 6)
    families(:dylan_family).recurring_transactions.create!(account: @card, name: "Netflix", plan_type: "charge",
                                                           amount: 299, currency: "USD", start_date: Date.new(2026, 10, 12))

    get account_url(@card, tab: "recurring"), headers: { "Turbo-Frame" => "account" }

    assert_response :success
    assert_includes response.body, "Committed per month"
    assert_includes response.body, "$1,299.00"
    assert_includes response.body, "Left on installments"
    assert_includes response.body, "Upcoming"
    assert_includes response.body, "Installment 1 of 6"
    assert_includes response.body, "See later months"
    assert_includes response.body, "Charges"
    assert_not_includes response.body, "Per month"
    assert_not_includes response.body, "Monthly charges"
    assert_includes response.body, "every month"
    assert_not_includes response.body, "over budget"
  end

  test "an empty card says where recurring payments come from" do
    get account_url(@card, tab: "recurring"), headers: { "Turbo-Frame" => "account" }

    assert_includes response.body, "No recurring payments on this card"
    assert_includes response.body, "Add one when you create a transaction."
  end

  test "a weekly charge shows its payment and frequency" do
    families(:dylan_family).recurring_transactions.create!(account: @card, name: "Cleaner", plan_type: "charge", frequency: "weekly",
                                                           amount: 50, currency: "USD", start_date: Date.new(2026, 10, 1))

    get account_url(@card, tab: "recurring"), headers: { "Turbo-Frame" => "account" }

    assert_includes response.body, "$250.00" # Committed per month: Oct 1, 8, 15, 22, 29
    assert_includes response.body, "$50.00"
    assert_includes response.body, "every week"
    assert_includes response.body, "Weekly charge"
  end
end
