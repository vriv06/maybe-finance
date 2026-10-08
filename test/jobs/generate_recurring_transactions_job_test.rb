require "test_helper"

class GenerateRecurringTransactionsJobTest < ActiveJob::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:credit_card)
    @account.entries.delete_all
  end

  test "generates due occurrences for active plans" do
    plan = create_plan(name: "Gym", start_date: Date.current)

    GenerateRecurringTransactionsJob.perform_now(@family)

    assert_equal 1, plan.transactions.count
  end

  test "uses the family's date, not the server's" do
    @family.update!(timezone: "Pacific/Kiritimati")

    travel_to Time.utc(2026, 10, 8, 12) do
      plan = create_plan(name: "Gym", start_date: Date.new(2026, 10, 9))

      GenerateRecurringTransactionsJob.perform_now(@family)

      assert_equal 1, plan.transactions.count
    end
  end

  test "one failing plan does not stop the others" do
    broken = create_plan(name: "Broken", start_date: Date.current)
    broken.update_column(:name, "")
    healthy = create_plan(name: "Gym", start_date: Date.current)

    assert_nothing_raised { GenerateRecurringTransactionsJob.perform_now(@family) }

    assert_equal 0, broken.transactions.count
    assert_equal 1, healthy.transactions.count
  end

  test "skips plans whose account is no longer active" do
    plan = create_plan(name: "Gym", start_date: Date.current)
    @account.update_column(:status, "disabled")

    GenerateRecurringTransactionsJob.perform_now(@family)

    assert_equal 0, plan.transactions.count
  end

  private
    def create_plan(name:, start_date:)
      @family.recurring_transactions.create!(
        account: @account, name: name, plan_type: "charge", amount: 500, currency: "USD", start_date: start_date
      )
    end
end
