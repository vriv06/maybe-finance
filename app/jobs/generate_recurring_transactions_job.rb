class GenerateRecurringTransactionsJob < ApplicationJob
  def perform(family)
    family.recurring_transactions.active.find_each(&:generate_due!)
  end
end
