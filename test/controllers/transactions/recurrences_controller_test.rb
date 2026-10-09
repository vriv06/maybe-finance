require "test_helper"

class Transactions::RecurrencesControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper, ActionView::RecordIdentifier

  setup do
    travel_to Date.new(2026, 10, 8)
    sign_in users(:family_admin)
    @card = accounts(:credit_card)
    @card.entries.delete_all
    @entry = create_transaction(account: @card, amount: 3000, name: "Laptop", date: Date.new(2026, 8, 20))
    @frame = { "Turbo-Frame" => dom_id(@entry, :recurrence) }
    @installments = { plan_type: "installments", total_payments: "3", start_date: "2026-08-25" }
  end

  test "opens the fields with Doesn't repeat selected" do
    get new_transaction_recurrence_url(@entry), headers: @frame

    assert_response :success
    assert_includes response.body, ERB::Util.html_escape("Doesn't repeat")
    assert_includes response.body, "Review"
  end

  test "review shows field errors without saving" do
    get new_transaction_recurrence_url(@entry), params: { recurrence: @installments.merge(total_payments: "60") }, headers: @frame

    assert_response :unprocessable_entity
    assert_includes response.body, "Enter 2 to 48 installments."
  end

  test "review confirms what will change" do
    get new_transaction_recurrence_url(@entry), params: { recurrence: @installments }, headers: @frame

    assert_response :success
    assert_includes response.body, "Split $3,000.00 into 3 installments"
    assert_includes response.body, "Your card balance stays the same."
    assert_includes response.body, "Adds 2 past installments with their original dates. Past budgets will change."
  end

  test "converts the purchase and refreshes the drawer" do
    assert_difference "RecurringTransaction.count", 1 do
      post transaction_recurrence_url(@entry), params: { recurrence: @installments },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, %(target="drawer")
    assert @entry.reload.transaction.msi_purchase?
    assert_equal 2, @entry.transaction.recurring_transaction.transactions.where(kind: "installment").count
  end

  test "explains why a transfer can't repeat" do
    payment = create_transaction(account: @card, amount: 500, kind: "cc_payment")

    assert_no_difference "RecurringTransaction.count" do
      post transaction_recurrence_url(payment), params: { recurrence: { plan_type: "charge" } },
           headers: { "Turbo-Frame" => dom_id(payment, :recurrence) }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, ERB::Util.html_escape("Transfers can't repeat.")
  end

  test "cancel returns to the closed block" do
    get transaction_recurrence_url(@entry), headers: @frame

    assert_response :success
    assert_includes response.body, "One time"
    assert_includes response.body, %(aria-label="Edit recurring payment")
  end

  test "an unparseable start date renders the fields with 422 and saves nothing" do
    assert_no_difference "RecurringTransaction.count" do
      post transaction_recurrence_url(@entry), params: { recurrence: @installments.merge(start_date: "not-a-date") }, headers: @frame
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Review"
  end

  test "a non-numeric installment count renders the fields with 422 and saves nothing" do
    assert_no_difference "RecurringTransaction.count" do
      post transaction_recurrence_url(@entry), params: { recurrence: @installments.merge(total_payments: "abc") }, headers: @frame
    end

    assert_response :unprocessable_entity
  end

  test "a failed conversion shows the error on the confirm step and saves nothing" do
    RecurringTransaction.stubs(:create_from_entry!).raises(ActiveRecord::RecordInvalid.new(RecurringTransaction.new.tap { |plan| plan.errors.add(:base, "Boom.") }))

    assert_no_difference "RecurringTransaction.count" do
      post transaction_recurrence_url(@entry), params: { recurrence: @installments }, headers: @frame
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Boom."
    assert_includes response.body, "Split $3,000.00 into 3 installments"
  end

  test "another family's entry is not found" do
    other = create_transaction(account: accounts(:depository).tap { |a| a.update_columns(family_id: families(:empty).id) }, amount: 10)

    get transaction_recurrence_url(other)

    assert_response :not_found
  end

  test "a valuation entry is not found" do
    valuation = entries(:valuation)

    get transaction_recurrence_url(valuation)

    assert_response :not_found
  end

  test "a linked entry's closed block shows its status and edits the plan" do
    RecurringTransaction.create_from_entry!(@entry, **@installments.symbolize_keys)
    plan = @entry.reload.transaction.recurring_transaction

    get transaction_recurrence_url(@entry), headers: @frame

    assert_response :success
    assert_includes response.body, "Installments"
    assert_includes response.body, recurring_transaction_path(plan)
  end
end
