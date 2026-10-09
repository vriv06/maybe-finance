require "test_helper"

class TransferMatchesControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
  end

  test "matches existing transaction and creates transfer" do
    inflow_transaction = create_transaction(amount: 100, account: accounts(:depository))
    outflow_transaction = create_transaction(amount: -100, account: accounts(:investment))

    assert_difference "Transfer.count", 1 do
      post transaction_transfer_match_path(inflow_transaction), params: {
        transfer_match: {
          method: "existing",
          matched_entry_id: outflow_transaction.id
        }
      }
    end

    assert_redirected_to transactions_url
    assert_equal "Transfer created", flash[:notice]
  end

  test "creates transfer for target account" do
    inflow_transaction = create_transaction(amount: 100, account: accounts(:depository))

    assert_difference [ "Transfer.count", "Entry.count", "Transaction.count" ], 1 do
      post transaction_transfer_match_path(inflow_transaction), params: {
        transfer_match: {
          method: "new",
          target_account_id: accounts(:investment).id
        }
      }
    end

    assert_redirected_to transactions_url
    assert_equal "Transfer created", flash[:notice]
  end

  test "explains instead of failing when the transaction belongs to a recurring payment" do
    installment = create_transaction(amount: 100, account: accounts(:credit_card), kind: "installment")

    assert_no_difference "Transfer.count" do
      post transaction_transfer_match_path(installment), params: {
        transfer_match: { method: "new", target_account_id: accounts(:depository).id }
      }
    end

    assert_redirected_to transactions_url
    assert_equal "This is part of a recurring payment, so it can't be a transfer.", flash[:alert]
  end
end
