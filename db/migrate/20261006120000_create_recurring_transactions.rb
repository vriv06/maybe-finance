class CreateRecurringTransactions < ActiveRecord::Migration[7.2]
  def change
    create_table :recurring_transactions, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.references :category, foreign_key: true, type: :uuid
      t.references :merchant, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :plan_type, null: false
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :currency, null: false
      t.date :start_date, null: false
      t.integer :total_payments
      t.string :status, null: false, default: "active"
      t.date :last_generated_on
      t.timestamps
    end

    add_reference :transactions, :recurring_transaction, type: :uuid, foreign_key: true, index: false
    add_column :transactions, :installment_number, :integer
    add_index :transactions, [ :recurring_transaction_id, :installment_number ],
              unique: true, name: "index_transactions_on_recurring_and_installment"

    add_column :families, :recurring_generated_on, :date
  end
end
