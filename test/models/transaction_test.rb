require "test_helper"

class TransactionTest < ActiveSupport::TestCase
  test "msi purchases are excluded from spending but installments are not" do
    assert_includes Transaction::BUDGET_EXCLUDED_KINDS, "msi_purchase"
    assert_not_includes Transaction::BUDGET_EXCLUDED_KINDS, "installment"
  end

  test "only installments are excluded from balances" do
    assert_equal %w[installment], Transaction::BALANCE_EXCLUDED_KINDS
  end

  test "budget_excluded_kinds_sql quotes every excluded kind" do
    assert_equal "'funds_movement', 'one_time', 'cc_payment', 'msi_purchase'", Transaction.budget_excluded_kinds_sql
  end
end
