require "test_helper"

class Transactions::RecurrencesControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper, ActionView::RecordIdentifier

  setup do
    travel_to Date.new(2026, 10, 8)
    sign_in users(:family_admin)
    @card = accounts(:credit_card)
    @card.entries.delete_all
    @entry = create_transaction(account: @card, amount: 3000, name: "Laptop", date: Date.new(2026, 7, 20))
    @frame = { "Turbo-Frame" => dom_id(@entry, :recurrence) }
    @installments = { frequency: "monthly", total_payments: "3" }
  end

  test "opens the fields with Repeat set to None" do
    get new_transaction_recurrence_url(@entry), headers: @frame

    assert_response :success
    assert_select "select#recurrence_frequency option[selected]", text: "None"
    assert_select "select#recurrence_frequency[autofocus]"
    assert_includes response.body, "Review"
  end

  test "review shows field errors without saving" do
    get new_transaction_recurrence_url(@entry), params: { recurrence: @installments.merge(total_payments: "60") }, headers: @frame

    assert_response :unprocessable_entity
    assert_includes response.body, "Enter 2 to 48 payments."
  end

  test "review confirms what will change" do
    get new_transaction_recurrence_url(@entry), params: { recurrence: @installments }, headers: @frame

    assert_response :success
    assert_includes response.body, "Split $3,000.00 into 3 installments"
    assert_includes response.body, "Your card balance stays the same."
    assert_includes response.body, "Adds 3 past installments with their original dates. Past budgets will change."
  end

  test "converts the purchase and refreshes the drawer" do
    assert_difference "RecurringTransaction.count", 1 do
      post transaction_recurrence_url(@entry), params: { recurrence: @installments },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, %(target="drawer")
    assert @entry.reload.transaction.msi_purchase?
    assert_equal 3, @entry.transaction.recurring_transaction.transactions.where(kind: "installment").count
  end

  test "explains why a transfer can't repeat" do
    payment = create_transaction(account: @card, amount: 500, kind: "cc_payment")

    assert_no_difference "RecurringTransaction.count" do
      post transaction_recurrence_url(payment), params: { recurrence: { frequency: "monthly" } },
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

  test "a non-numeric installment count renders the fields with 422 and saves nothing" do
    assert_no_difference "RecurringTransaction.count" do
      post transaction_recurrence_url(@entry), params: { recurrence: @installments.merge(total_payments: "abc") }, headers: @frame
    end

    assert_response :unprocessable_entity
  end

  test "an unknown frequency renders the fields with 422 and saves nothing" do
    get new_transaction_recurrence_url(@entry), params: { recurrence: @installments.merge(frequency: "bogus") }, headers: @frame

    assert_response :unprocessable_entity
    assert_includes response.body, "Choose how often it repeats."
    assert_select "select#recurrence_frequency[autofocus][aria-invalid='true']"

    assert_no_difference "RecurringTransaction.count" do
      post transaction_recurrence_url(@entry), params: { recurrence: @installments.merge(frequency: "bogus") }, headers: @frame
    end

    assert_response :unprocessable_entity
    assert_nil @entry.entryable.reload.recurring_transaction_id
  end

  test "a tampered recurrence param opens the fields" do
    get new_transaction_recurrence_url(@entry), params: { recurrence: "foo" }, headers: @frame

    assert_response :success
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

  test "the fields carry one live status region outside the preview frame" do
    get new_transaction_recurrence_url(@entry), headers: @frame

    assert_select "p.sr-only[role=status][aria-live=polite][aria-atomic=true][data-recurring-form-target=status]", count: 1
    assert_select "turbo-frame#recurring_preview p[role=status]", count: 0
  end

  test "a 422 on the fields keeps the chosen frequency and payments" do
    get new_transaction_recurrence_url(@entry), params: { recurrence: { frequency: "weekly", total_payments: "60" } }, headers: @frame

    assert_response :unprocessable_entity
    assert_select "select#recurrence_frequency option[selected][value=weekly]"
    assert_select "input#recurrence_total_payments[value='60']"
  end

  test "review of a weekly charge names its frequency" do
    get new_transaction_recurrence_url(@entry), params: { recurrence: { frequency: "weekly" } }, headers: @frame

    assert_response :success
    assert_includes response.body, "Repeat $3,000.00 every week"
    assert_includes response.body, "Start weekly charge"
    assert_select "input[type=hidden][name='recurrence[frequency]'][value='weekly']"
  end

  test "review of installments off a card says the transaction becomes payment 1" do
    entry = create_transaction(account: accounts(:depository), amount: 1200, name: "Desk", date: Date.new(2026, 10, 1))
    frame = { "Turbo-Frame" => dom_id(entry, :recurrence) }

    get new_transaction_recurrence_url(entry), params: { recurrence: { frequency: "monthly", total_payments: "3" } }, headers: frame

    assert_response :success
    assert_includes response.body, "Split $1,200.00 into 3 payments"
    assert_includes response.body, "This transaction becomes payment 1 ($400.00)."
    assert_includes response.body, "Split into 3 payments"
    assert_not_includes response.body, "Your card balance stays the same."
  end

  test "converting installments off a card rewrites the transaction as payment 1" do
    entry = create_transaction(account: accounts(:depository), amount: 1200, name: "Desk", date: Date.new(2026, 10, 1))

    post transaction_recurrence_url(entry), params: { recurrence: { frequency: "monthly", total_payments: "3" } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_equal BigDecimal("400"), entry.reload.amount
    assert_includes response.body, "Split into 3 payments."
  end

  # fields -> review -> confirm: the confirm step's own hidden fields must create the plan
  def confirm_and_post(entry, params)
    frame = { "Turbo-Frame" => dom_id(entry, :recurrence) }
    get new_transaction_recurrence_url(entry), params: { recurrence: params }, headers: frame
    assert_response :success

    document = Nokogiri::HTML(response.body)
    posted = document.css("form input[type=hidden]").to_h { |input| [ input["name"], input["value"] ] }
    assert_equal params[:frequency], posted["recurrence[frequency]"]
    assert_nil posted["recurrence[plan_type]"]
    assert_nil posted["recurrence[start_date]"]

    assert_difference "RecurringTransaction.count", 1 do
      post transaction_recurrence_url(entry), params: { recurrence: posted.transform_keys { |k| k[/\[(.+)\]/, 1] }.compact_blank },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
    entry.reload.transaction.recurring_transaction
  end

  test "confirm posts create card installments end to end" do
    plan = confirm_and_post(@entry, @installments)

    assert plan.installments?
    assert_equal 3, plan.total_payments
  end

  test "confirm posts create non-card installments end to end" do
    entry = create_transaction(account: accounts(:depository), amount: 1200, name: "Desk", date: Date.new(2026, 10, 1))
    plan = confirm_and_post(entry, @installments)

    assert plan.installments?
    assert_equal BigDecimal("400"), entry.reload.amount
  end

  test "confirm posts create a weekly charge end to end" do
    plan = confirm_and_post(@entry, { frequency: "weekly" })

    assert plan.charge?
    assert_equal "weekly", plan.frequency
  end
end
