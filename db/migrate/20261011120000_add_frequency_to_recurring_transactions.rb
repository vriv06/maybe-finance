class AddFrequencyToRecurringTransactions < ActiveRecord::Migration[7.2]
  def change
    add_column :recurring_transactions, :frequency, :string, null: false, default: "monthly"
  end
end
