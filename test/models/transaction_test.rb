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

  test "an installment cannot change kind" do
    transaction = plan_transaction(kind: "installment", installment_number: 1)

    assert_not transaction.update(kind: "standard")
    assert_includes transaction.errors.attribute_names, :kind
    assert transaction.reload.installment?
  end

  test "an msi purchase cannot change kind" do
    transaction = plan_transaction(kind: "msi_purchase")

    assert_not transaction.update(kind: "one_time")
    assert_includes transaction.errors.attribute_names, :kind
  end

  private
    def plan_transaction(**attributes)
      account = accounts(:credit_card)
      plan = RecurringTransaction.create!(
        family: account.family, account: account, name: "Laptop", plan_type: "installments",
        amount: 1000, currency: "USD", start_date: Date.current, total_payments: 3
      )
      entry = account.entries.create!(
        name: "Laptop", date: Date.current, amount: 100, currency: "USD",
        entryable: Transaction.new(recurring_transaction: plan, **attributes)
      )
      entry.entryable
    end
end
