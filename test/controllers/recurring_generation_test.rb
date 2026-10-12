require "test_helper"

class RecurringGenerationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    @family.recurring_transactions.create!(
      account: accounts(:credit_card), name: "Gym", plan_type: "charge", amount: 500, currency: "USD", start_date: Date.current + 1.day
    )
    @family.update_column(:recurring_generated_on, nil)
  end

  test "enqueues generation at most once per day" do
    assert_enqueued_jobs 1, only: GenerateRecurringTransactionsJob do
      get budgets_path
      get budgets_path
    end

    assert_equal Date.current, @family.reload.recurring_generated_on
  end

  test "does not enqueue when the family has no active plans" do
    @family.recurring_transactions.update_all(status: "cancelled")

    assert_no_enqueued_jobs only: GenerateRecurringTransactionsJob do
      get budgets_path
    end
  end
end
