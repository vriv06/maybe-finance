require "test_helper"

class CustomConfirmTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 10, 8)
    @card = accounts(:credit_card)
    @card.entries.delete_all
    purchase = create_transaction(account: @card, amount: 1200, name: "MacBook Air", date: Date.new(2026, 7, 20))
    @plan = RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 12) # 2 added
    @purchase = purchase
  end

  test "stop confirm keeps the safe choice" do
    data = CustomConfirm.for_plan_stop(@plan).to_data_attribute

    assert_equal "Stop MacBook Air?", data[:title]
    assert_equal "The 10 installments left ($1,000.00) won't count in future budgets. The full purchase stays on your card balance.", data[:body]
    assert_equal "Stop payments", data[:confirmText]
    assert_equal "Keep it", data[:cancelText]
    assert_equal "outline-destructive", data[:variant]
  end

  test "deleting an installment purchase is high severity" do
    data = CustomConfirm.for_msi_purchase_deletion(@purchase).to_data_attribute

    assert_equal "Delete this purchase and its installments?", data[:title]
    assert_equal "All 12 installments will be deleted, including the 2 already added. Your card balance and past budgets will change. This can't be undone.", data[:body]
    assert_equal "Delete", data[:confirmText]
    assert_equal "destructive", data[:variant]
  end

  test "deleting one installment names its budget month" do
    installment = @plan.transactions.find_by(installment_number: 1).entry
    data = CustomConfirm.for_occurrence_deletion(installment).to_data_attribute

    assert_equal "Delete this installment?", data[:title]
    assert_equal "It won't be added again. Your August 2026 budget will change.", data[:body]
    assert_equal "Delete installment", data[:confirmText]
    assert_equal "Keep it", data[:cancelText]
  end

  test "editing a plan with payments asks first" do
    data = CustomConfirm.for_plan_edit(@plan).to_data_attribute

    assert_equal "Save changes to future payments?", data[:title]
    assert_equal "The 2 payments already added won't change.", data[:body]
    assert_equal "Keep editing", data[:cancelText]
    assert_equal "primary", data[:variant]
  end

  test "existing confirms have no secondary button" do
    assert_not CustomConfirm.for_resource_deletion("transaction").to_data_attribute.key?(:cancelText)
  end
end
