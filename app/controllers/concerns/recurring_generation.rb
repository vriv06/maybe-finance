module RecurringGeneration
  extend ActiveSupport::Concern

  included do
    before_action :generate_recurring_transactions_later
  end

  private
    # One date comparison per request; at most one job per family per day
    def generate_recurring_transactions_later
      family = Current.family
      return unless family

      today = family.today
      return if family.recurring_generated_on == today

      family.update_column(:recurring_generated_on, today)
      GenerateRecurringTransactionsJob.perform_later(family) if family.recurring_transactions.generatable.exists?
    end
end
