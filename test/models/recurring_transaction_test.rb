require "test_helper"

class RecurringTransactionTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @credit_card = accounts(:credit_card)
    @credit_card.entries.delete_all
  end

  test "splits installments so the last payment absorbs rounding" do
    plan = build_plan

    assert_equal [ BigDecimal("333.33"), BigDecimal("333.33"), BigDecimal("333.34") ],
                 (1..3).map { |n| plan.occurrence_amount(n) }
  end

  test "clamps occurrence dates to the end of shorter months" do
    plan = build_plan(start_date: Date.new(2026, 1, 31))

    assert_equal [ Date.new(2026, 1, 31), Date.new(2026, 2, 28), Date.new(2026, 3, 31) ],
                 (1..3).map { |n| plan.occurrence_date(n) }
    assert_equal Date.new(2026, 3, 31), plan.end_date
  end

  test "installments require a credit card and at least two payments" do
    assert build_plan.valid?

    not_card = build_plan(account: accounts(:depository))
    assert_not not_card.valid?
    assert_includes not_card.errors.attribute_names, :account

    one_payment = build_plan(total_payments: 1)
    assert_not one_payment.valid?
    assert_includes one_payment.errors.attribute_names, :total_payments
  end

  test "upcoming lists occurrences up to a date" do
    plan = build_plan(start_date: Date.new(2026, 1, 15))
    plan.save!

    assert_equal [ 1, 2 ], plan.upcoming(through: Date.new(2026, 2, 20)).map(&:number)
  end

  test "charges without total payments repeat open-ended" do
    plan = build_plan(plan_type: "charge", total_payments: nil, amount: 299, start_date: Date.new(2026, 1, 10))

    assert plan.valid?
    assert_equal 12, plan.upcoming(through: Date.new(2026, 12, 31)).size
    assert_nil plan.end_date
  end

  test "cancel! stops the plan" do
    plan = build_plan
    plan.save!
    plan.cancel!

    assert_equal "cancelled", plan.reload.status
  end

  test "tracks generated installments from linked transactions" do
    plan = build_plan
    plan.save!
    link_installment(plan, 1)
    link_installment(plan, 3)

    assert_equal [ 1, 3 ], plan.generated_numbers.sort
    assert_equal 1, plan.remaining_payments
    assert_equal BigDecimal("333.33"), plan.remaining_balance
    assert_equal [ 2 ], plan.upcoming(through: plan.end_date).map(&:number)
  end

  test "remaining balance is a decimal zero for charges" do
    plan = build_plan(plan_type: "charge", total_payments: nil, amount: 299)

    assert_instance_of BigDecimal, plan.remaining_balance
    assert_equal 0, plan.remaining_balance
  end

  test "destroying an account removes its recurring plans" do
    plan = build_plan
    plan.save!
    link_installment(plan, 1)

    assert_difference "RecurringTransaction.count", -1 do
      Account.find(@credit_card.id).destroy!
    end
  end

  test "destroying a category nullifies the plan category" do
    category = categories(:food_and_drink)
    plan = build_plan(category: category)
    plan.save!

    category.destroy!

    assert_nil plan.reload.category_id
  end

  test "destroying a merchant nullifies the plan merchant" do
    merchant = merchants(:netflix)
    plan = build_plan(merchant: merchant)
    plan.save!

    merchant.destroy!

    assert_nil plan.reload.merchant_id
  end

  test "generate_due! backfills missed occurrences with their original dates" do
    plan = build_plan(start_date: Date.new(2026, 1, 15))
    plan.save!

    assert_equal 2, plan.generate_due!(as_of: Date.new(2026, 2, 20))

    entries = @credit_card.entries.order(:date)
    assert_equal [ Date.new(2026, 1, 15), Date.new(2026, 2, 15) ], entries.map(&:date)
    assert entries.all? { |entry| entry.entryable.installment? }
  end

  test "generate_due! is idempotent" do
    plan = build_plan(start_date: Date.new(2026, 1, 15))
    plan.save!
    plan.generate_due!(as_of: Date.new(2026, 2, 20))

    assert_equal 0, plan.generate_due!(as_of: Date.new(2026, 2, 20))
    assert_equal 2, plan.transactions.count
  end

  test "generate_due! completes the plan after the last payment" do
    plan = build_plan(start_date: Date.new(2026, 1, 15))
    plan.save!
    plan.generate_due!(as_of: Date.new(2026, 6, 1))

    assert_equal "completed", plan.reload.status
    assert_equal 0, plan.remaining_payments
    assert_equal 0, plan.remaining_balance
  end

  test "generate_due! skips cancelled plans" do
    plan = build_plan(status: "cancelled")
    plan.save!

    assert_equal 0, plan.generate_due!(as_of: Date.new(2026, 6, 1))
  end

  test "charges generate standard transactions" do
    plan = build_plan(plan_type: "charge", total_payments: nil, amount: 299, start_date: Date.new(2026, 1, 10))
    plan.save!
    plan.generate_due!(as_of: Date.new(2026, 2, 10))

    assert_equal 2, plan.transactions.count
    assert plan.transactions.all?(&:standard?)
  end

  test "create_from_entry! turns a past purchase into an msi plan and backfills due installments" do
    purchase = create_transaction(account: @credit_card, amount: 3000, name: "Laptop", date: Date.current - 2.months - 5.days)

    plan = RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 3)

    assert purchase.entryable.reload.msi_purchase?
    assert_equal plan, purchase.entryable.recurring_transaction
    assert_equal purchase.date.next_month, plan.start_date
    assert_equal 2, plan.transactions.where(kind: "installment").count
  end

  test "create_from_entry! links a charge's original entry as the first occurrence" do
    entry = create_transaction(account: @credit_card, amount: 299, name: "Netflix", date: Date.current)

    plan = RecurringTransaction.create_from_entry!(entry, plan_type: "charge")

    assert_equal 1, entry.entryable.reload.installment_number
    assert_equal 1, plan.transactions.count
  end

  private
    def link_installment(plan, number)
      create_transaction(
        account: @credit_card,
        date: plan.occurrence_date(number),
        amount: plan.occurrence_amount(number),
        entryable: Transaction.new(kind: "installment", recurring_transaction: plan, installment_number: number)
      )
    end

    def build_plan(**attributes)
      RecurringTransaction.new({
        family: @family,
        account: @credit_card,
        name: "Laptop",
        plan_type: "installments",
        amount: 1000,
        currency: "USD",
        start_date: Date.new(2026, 1, 15),
        total_payments: 3
      }.merge(attributes))
    end
end
