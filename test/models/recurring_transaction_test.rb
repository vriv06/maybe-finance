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
    assert_equal 0, plan.remaining_payments
    assert_equal 0, plan.remaining_balance
    assert_empty plan.upcoming(through: plan.end_date)
  end

  test "numbers up to the highest generated one count as done after a deletion" do
    plan = build_plan(start_date: Date.new(2026, 1, 15))
    plan.save!
    plan.generate_due!(as_of: Date.new(2026, 2, 20))

    plan.transactions.find_by(installment_number: 1).entry.destroy!

    assert_equal [ 3 ], plan.upcoming(through: plan.end_date).map(&:number)
    assert_equal 1, plan.remaining_payments
    assert_equal BigDecimal("333.34"), plan.remaining_balance
  end

  test "generate_due! does not regenerate a deleted installment" do
    plan = build_plan(start_date: Date.new(2026, 1, 15))
    plan.save!
    plan.generate_due!(as_of: Date.new(2026, 2, 20))

    plan.transactions.find_by(installment_number: 2).entry.destroy!

    assert_equal 0, plan.generate_due!(as_of: Date.new(2026, 2, 20))
    assert_equal [ 1 ], plan.generated_numbers
    assert_equal [ 3 ], plan.upcoming(through: plan.end_date).map(&:number)
  end

  test "generate_due! does not regenerate a deleted charge source" do
    entry = create_transaction(account: @credit_card, amount: 299, name: "Netflix", date: Date.current)
    plan = RecurringTransaction.create_from_entry!(entry, plan_type: "charge")

    entry.destroy!

    assert_equal 0, plan.reload.generate_due!
    assert_equal 0, plan.transactions.count
  end

  test "destroying the msi purchase removes its plan and installments" do
    unrelated = create_transaction(account: @credit_card, amount: 50, name: "Coffee", date: Date.current)
    purchase = create_transaction(account: @credit_card, amount: 3000, name: "Laptop", date: Date.current - 2.months - 5.days)
    plan = RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 3)
    assert_equal 2, plan.transactions.where(kind: "installment").count

    Account.any_instance.expects(:sync_later).once

    assert_difference -> { RecurringTransaction.count } => -1, -> { Entry.count } => -3 do
      purchase.destroy!
    end

    assert Entry.exists?(unrelated.id)
    assert_equal 0, Transaction.where(recurring_transaction_id: plan.id).count
  end

  test "destroying an installments plan reverts the purchase to standard" do
    purchase = create_transaction(account: @credit_card, amount: 3000, name: "Laptop", date: Date.current - 2.months - 5.days)
    plan = RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 3)

    assert_difference -> { Entry.count } => -2 do
      plan.destroy!
    end

    source = purchase.entryable.reload
    assert source.standard?
    assert_nil source.recurring_transaction_id
  end

  test "destroying a charge plan keeps its transactions unlinked" do
    plan = build_plan(plan_type: "charge", total_payments: nil, amount: 299, start_date: Date.new(2026, 1, 10))
    plan.save!
    plan.generate_due!(as_of: Date.new(2026, 2, 10))
    ids = plan.transactions.pluck(:id)

    assert_no_difference -> { Entry.count } do
      plan.destroy!
    end

    assert_equal [ nil ], Transaction.where(id: ids).pluck(:recurring_transaction_id).uniq
  end

  test "destroying an account with an msi purchase removes everything" do
    purchase = create_transaction(account: @credit_card, amount: 3000, name: "Laptop", date: Date.current - 2.months - 5.days)
    RecurringTransaction.create_from_entry!(purchase, plan_type: "installments", total_payments: 3)

    assert_difference -> { RecurringTransaction.count } => -1 do
      Account.find(@credit_card.id).destroy!
    end
    assert_equal 0, Entry.where(account_id: @credit_card.id).count
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

  test "create_from_entry! rejects transactions that can't repeat" do
    linked = create_transaction(account: @credit_card, amount: 100, name: "Netflix")
    RecurringTransaction.create_from_entry!(linked, plan_type: "charge")

    {
      create_transaction(account: @credit_card, amount: 100, kind: "cc_payment") => "Transfers can't repeat.",
      create_transaction(account: @credit_card, amount: 100, kind: "one_time") => "Turn off One-time Expense to set this up.",
      create_transaction(account: @credit_card, amount: -100) => "Only expenses can repeat.",
      linked => "This is already part of a recurring payment."
    }.each do |entry, message|
      error = assert_raises(ActiveRecord::RecordInvalid) do
        RecurringTransaction.create_from_entry!(entry, plan_type: "charge")
      end
      assert_includes error.record.errors[:base], message
    end
  end

  test "a transaction in another currency than the family's can't become a plan" do
    entry = create_transaction(account: @credit_card, amount: 100, name: "Imported", currency: "MXN")

    assert_equal :foreign_currency, RecurringTransaction.ineligibility_reason(entry)
    error = assert_raises(ActiveRecord::RecordInvalid) do
      RecurringTransaction.create_from_entry!(entry, plan_type: "charge")
    end
    assert_includes error.record.errors[:base], "Recurring payments only work in your main currency."
  end

  test "plans require a manual, active account" do
    plan = build_plan(plan_type: "charge", total_payments: nil, account: accounts(:connected))

    assert_not plan.valid?
    assert_includes plan.errors[:account], "Only manual accounts can have recurring payments."
  end

  test "validation messages are the interface copy" do
    assert_equal [ "Enter 2 to 48 installments." ], build_plan(total_payments: 49).tap(&:validate).errors[:total_payments]
    assert_equal [ "Too small to split into 6 installments. Use fewer." ],
                 build_plan(amount: BigDecimal("0.05"), total_payments: 6).tap(&:validate).errors[:total_payments]
    assert_includes build_plan(account: accounts(:depository)).tap(&:validate).errors[:account],
                    "Installments only work on credit cards."
    assert_equal [ "Enter a whole number, or leave it empty." ],
                 build_plan(plan_type: "charge", total_payments: "abc").tap(&:validate).errors[:total_payments]
  end

  test "a charge's end count beyond the integer column is invalid" do
    plan = build_plan(plan_type: "charge", total_payments: "3000000000")

    assert_not plan.valid?
    assert_equal [ "Enter a whole number, or leave it empty." ], plan.errors[:total_payments]
  end

  test "the first payment can't be missing or before the purchase" do
    purchase = create_transaction(account: @credit_card, amount: 1200, date: Date.new(2026, 10, 8))

    early = RecurringTransaction.build_from_entry(purchase, plan_type: "installments", total_payments: 3, start_date: "2026-10-01")
    assert_not early.valid?
    assert_equal [ "The first payment can't be before Oct 8, 2026." ], early.errors[:start_date]

    blank = RecurringTransaction.build_from_entry(purchase, plan_type: "installments", total_payments: 3, start_date: "")
    assert_not blank.valid?
    assert_equal [ "Choose a date for the first payment." ], blank.errors[:start_date]

    default = RecurringTransaction.build_from_entry(purchase, plan_type: "installments", total_payments: 3)
    assert_equal Date.new(2026, 11, 8), default.start_date
  end

  test "the schedule can't change after the plan is created" do
    plan = build_plan
    plan.save!

    assert_not plan.update(total_payments: 6)
    assert plan.reload.update(name: "New laptop")
  end

  test "backfill_count counts past occurrences except a charge's own first payment" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: @credit_card, amount: 3000, date: Date.new(2026, 7, 8))

    installments = RecurringTransaction.build_from_entry(purchase, plan_type: "installments", total_payments: 6)
    charge = RecurringTransaction.build_from_entry(purchase, plan_type: "charge")

    assert_equal 3, installments.backfill_count # Aug 8, Sep 8, Oct 8
    assert_equal 3, charge.backfill_count       # Jul 8 is the purchase itself
  end

  test "ended_on and monthly_amount describe the plan" do
    plan = build_plan(start_date: Date.new(2026, 1, 15))
    plan.save!

    assert_equal BigDecimal("333.33"), plan.monthly_amount
    assert_nil plan.ended_on

    plan.cancel!
    assert_equal plan.updated_at.to_date, plan.ended_on
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
