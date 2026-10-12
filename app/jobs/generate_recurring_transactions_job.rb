class GenerateRecurringTransactionsJob < ApplicationJob
  def perform(family)
    today = family.today

    family.recurring_transactions.generatable.find_each do |plan|
      plan.generate_due!(as_of: today)
    rescue StandardError => e
      # One broken plan must not stop the rest of the family's plans
      Rails.logger.error("Recurring plan #{plan.id} failed to generate: #{e.class}: #{e.message}")
      Sentry.capture_exception(e)
    end
  end
end
