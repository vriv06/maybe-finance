class AddCycleEndDayToFamily < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :cycle_end_day, :integer
  end
end
