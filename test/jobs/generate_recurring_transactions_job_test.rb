require "test_helper"

class GenerateRecurringTransactionsJobTest < ActiveJob::TestCase
  test "generates due occurrences for active plans" do
    family = families(:dylan_family)
    account = accounts(:credit_card)
    account.entries.delete_all
    plan = family.recurring_transactions.create!(
      account: account, name: "Gym", plan_type: "charge", amount: 500, currency: "USD", start_date: Date.current
    )

    GenerateRecurringTransactionsJob.perform_now(family)

    assert_equal 1, plan.transactions.count
  end
end
