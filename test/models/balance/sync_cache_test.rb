require "test_helper"

class Balance::SyncCacheTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @account = accounts(:credit_card)
    @account.entries.delete_all
    create_transaction(account: @account, amount: 3000, kind: "msi_purchase", date: Date.current)
    create_transaction(account: @account, amount: 1000, kind: "installment", date: Date.current)
  end

  test "installments are not part of the balance ledger" do
    entries = Balance::SyncCache.new(@account).get_entries(Date.current)

    assert_equal [ 3000 ], entries.map(&:amount)
  end

  test "card balance reflects the full msi purchase only" do
    calculated = Balance::ForwardCalculator.new(@account).calculate

    assert_equal 3000, calculated.find { |balance| balance.date == Date.current }.balance
  end
end
