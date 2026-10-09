require "test_helper"

class TransactionsControllerTest < ActionDispatch::IntegrationTest
  include EntryableResourceInterfaceTest, EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @entry = entries(:transaction)
  end

  test "creates with transaction details" do
    assert_difference [ "Entry.count", "Transaction.count" ], 1 do
      post transactions_url, params: {
        entry: {
          account_id: @entry.account_id,
          name: "New transaction",
          date: Date.current,
          currency: "USD",
          amount: 100,
          nature: "inflow",
          entryable_type: @entry.entryable_type,
          entryable_attributes: {
            tag_ids: [ Tag.first.id, Tag.second.id ],
            category_id: Category.first.id,
            merchant_id: Merchant.first.id
          }
        }
      }
    end

    created_entry = Entry.order(:created_at).last

    assert_redirected_to account_url(created_entry.account)
    assert_equal "Transaction created", flash[:notice]
    assert_enqueued_with(job: SyncJob)
  end

  test "updates with transaction details" do
    assert_no_difference [ "Entry.count", "Transaction.count" ] do
      patch transaction_url(@entry), params: {
        entry: {
          name: "Updated name",
          date: Date.current,
          currency: "USD",
          amount: 100,
          nature: "inflow",
          entryable_type: @entry.entryable_type,
          notes: "test notes",
          excluded: false,
          entryable_attributes: {
            id: @entry.entryable_id,
            tag_ids: [ Tag.first.id, Tag.second.id ],
            category_id: Category.first.id,
            merchant_id: Merchant.first.id
          }
        }
      }
    end

    @entry.reload

    assert_equal "Updated name", @entry.name
    assert_equal Date.current, @entry.date
    assert_equal "USD", @entry.currency
    assert_equal -100, @entry.amount
    assert_equal [ Tag.first.id, Tag.second.id ], @entry.entryable.tag_ids.sort
    assert_equal Category.first.id, @entry.entryable.category_id
    assert_equal Merchant.first.id, @entry.entryable.merchant_id
    assert_equal "test notes", @entry.notes
    assert_equal false, @entry.excluded

    assert_equal "Transaction updated", flash[:notice]
    assert_redirected_to account_url(@entry.account)
    assert_enqueued_with(job: SyncJob)
  end

  test "transaction count represents filtered total" do
    family = families(:empty)
    sign_in users(:empty)
    account = family.accounts.create! name: "Test", balance: 0, currency: "USD", accountable: Depository.new

    3.times do
      create_transaction(account: account)
    end

    get transactions_url(per_page: 10)

    assert_dom "#total-transactions", count: 1, text: family.entries.transactions.size.to_s

    searchable_transaction = create_transaction(account: account, name: "Unique test name")

    get transactions_url(q: { search: searchable_transaction.name })

    # Only finds 1 transaction that matches filter
    assert_dom "#" + dom_id(searchable_transaction), count: 1
    assert_dom "#total-transactions", count: 1, text: "1"
  end

  test "can paginate" do
  family = families(:empty)
  sign_in users(:empty)

  # Clean up any existing entries to ensure clean test
  family.accounts.each { |account| account.entries.delete_all }

  account = family.accounts.create! name: "Test", balance: 0, currency: "USD", accountable: Depository.new

  # Create multiple transactions for pagination
  25.times do |i|
    create_transaction(
      account: account,
      name: "Transaction #{i + 1}",
      amount: 100 + i,  # Different amounts to prevent transfer matching
      date: Date.current - i.days  # Different dates
    )
  end

  total_transactions = family.entries.transactions.count
  assert_operator total_transactions, :>=, 20, "Should have at least 20 transactions for testing"

  # Test page 1 - should show limited transactions
  get transactions_url(page: 1, per_page: 10)
  assert_response :success

  page_1_count = css_select("turbo-frame[id^='entry_']").count
  assert_equal 10, page_1_count, "Page 1 should respect per_page limit"

  # Test page 2 - should show different transactions
  get transactions_url(page: 2, per_page: 10)
  assert_response :success

  page_2_count = css_select("turbo-frame[id^='entry_']").count
  assert_operator page_2_count, :>, 0, "Page 2 should show some transactions"
  assert_operator page_2_count, :<=, 10, "Page 2 should not exceed per_page limit"

  # Test Pagy overflow handling - should redirect or handle gracefully
  get transactions_url(page: 9999999, per_page: 10)

  # Either success (if Pagy shows last page) or redirect (if Pagy redirects)
  assert_includes [ 200, 302 ], response.status, "Pagy should handle overflow gracefully"

  if response.status == 302
    follow_redirect!
    assert_response :success
  end

  overflow_count = css_select("turbo-frame[id^='entry_']").count
  assert_operator overflow_count, :>, 0, "Overflow should show some transactions"
end

  test "calls Transaction::Search totals method with correct search parameters" do
    family = families(:empty)
    sign_in users(:empty)
    account = family.accounts.create! name: "Test", balance: 0, currency: "USD", accountable: Depository.new

    create_transaction(account: account, amount: 100)

    search = Transaction::Search.new(family)
    totals = OpenStruct.new(
      count: 1,
      expense_money: Money.new(10000, "USD"),
      income_money: Money.new(0, "USD")
    )

    Transaction::Search.expects(:new).with(family, filters: {}).returns(search)
    search.expects(:totals).once.returns(totals)

    get transactions_url
    assert_response :success
  end

  test "calls Transaction::Search totals method with filtered search parameters" do
    family = families(:empty)
    sign_in users(:empty)
    account = family.accounts.create! name: "Test", balance: 0, currency: "USD", accountable: Depository.new
    category = family.categories.create! name: "Food", color: "#ff0000"

    create_transaction(account: account, amount: 100, category: category)

    search = Transaction::Search.new(family, filters: { "categories" => [ "Food" ], "types" => [ "expense" ] })
    totals = OpenStruct.new(
      count: 1,
      expense_money: Money.new(10000, "USD"),
      income_money: Money.new(0, "USD")
    )

    Transaction::Search.expects(:new).with(family, filters: { "categories" => [ "Food" ], "types" => [ "expense" ] }).returns(search)
    search.expects(:totals).once.returns(totals)

    get transactions_url(q: { categories: [ "Food" ], types: [ "expense" ] })
    assert_response :success
  end

  test "explains why a recurring row can't become one-time" do
    installment = create_transaction(amount: 100, account: accounts(:credit_card), kind: "installment")

    patch transaction_url(installment), params: {
      entry: { entryable_attributes: { id: installment.entryable_id, kind: "one_time" } }
    }, headers: { "Turbo-Frame" => "drawer" }

    assert_response :unprocessable_entity
    assert_includes response.body, ERB::Util.html_escape("This is part of a recurring payment, so it can't be one-time.")
    assert installment.reload.transaction.installment?
  end

  test "creates an installment purchase and its plan together" do
    travel_to Date.new(2026, 10, 8)
    card = accounts(:credit_card)

    assert_difference [ "Entry.count", "RecurringTransaction.count" ], 1 do
      post transactions_url, params: {
        entry: recurring_entry_params(card, amount: 15000),
        recurrence: { plan_type: "installments", total_payments: "12", start_date: "2026-11-08" }
      }
    end

    entry = Entry.find_by!(name: "iPad Air")
    assert entry.transaction.msi_purchase?
    assert_equal 12, entry.transaction.recurring_transaction.total_payments
    assert_equal "Split into 12 installments.", flash[:notice]
  end

  test "creates a monthly charge" do
    travel_to Date.new(2026, 10, 8)

    post transactions_url, params: {
      entry: recurring_entry_params(accounts(:depository), amount: 299),
      recurrence: { plan_type: "charge", total_payments: "" }
    }

    entry = Entry.find_by!(name: "iPad Air")
    assert_equal 1, entry.transaction.installment_number
    assert_equal "Monthly charge started.", flash[:notice]
  end

  test "a blank plan type creates an ordinary transaction" do
    assert_difference "Entry.count", 1 do
      assert_no_difference "RecurringTransaction.count" do
        post transactions_url, params: {
          entry: recurring_entry_params(accounts(:depository), amount: 50),
          recurrence: { plan_type: "" }
        }
      end
    end

    assert_equal "Transaction created", flash[:notice]
  end

  test "an invalid plan saves nothing and explains why" do
    travel_to Date.new(2026, 10, 8)

    assert_no_difference [ "Entry.count", "RecurringTransaction.count" ] do
      post transactions_url, params: {
        entry: recurring_entry_params(accounts(:credit_card), amount: 15000),
        recurrence: { plan_type: "installments", total_payments: "1", start_date: "2026-11-08" }
      }, headers: { "Turbo-Frame" => "modal" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Enter 2 to 48 installments."
    assert_select "details[open]", text: /Recurring payment/
    assert_select "input#recurrence_total_payments_installments[autofocus]"
  end

  test "an unexpected failure creating the plan saves nothing and shows the generic message" do
    RecurringTransaction.expects(:create_from_entry!).raises(ActiveRecord::RecordInvalid.new(RecurringTransaction.new))

    assert_no_difference [ "Entry.count", "RecurringTransaction.count" ] do
      post transactions_url, params: {
        entry: recurring_entry_params(accounts(:credit_card), amount: 15000),
        recurrence: { plan_type: "installments", total_payments: "12", start_date: "2026-11-08" }
      }, headers: { "Turbo-Frame" => "modal" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, ERB::Util.html_escape(RecurringTransaction::GENERIC_ERROR)
  end

  test "new with a recurrence choice but no account does not raise" do
    get new_transaction_url(recurrence: { plan_type: "charge" }), headers: { "Turbo-Frame" => "modal" }

    assert_response :success
  end

  test "installments are refused on accounts that aren't credit cards" do
    travel_to Date.new(2026, 10, 8)

    assert_no_difference "Entry.count" do
      post transactions_url, params: {
        entry: recurring_entry_params(accounts(:depository), amount: 1200),
        recurrence: { plan_type: "installments", total_payments: "3", start_date: "2026-11-08" }
      }, headers: { "Turbo-Frame" => "modal" }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Installments only work on credit cards."
  end

  private
    def recurring_entry_params(account, amount:)
      {
        account_id: account.id, name: "iPad Air", date: "2026-10-08", currency: "USD", amount: amount,
        nature: "outflow", entryable_type: "Transaction",
        entryable_attributes: { category_id: categories(:food_and_drink).id }
      }
    end
end
