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

  test "installments need at least two payments, on any manual account" do
    assert build_plan.valid?
    assert build_plan(account: accounts(:depository)).valid?

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
    plan = RecurringTransaction.create_from_entry!(entry, frequency: "monthly")

    entry.destroy!

    assert_equal 0, plan.reload.generate_due!
    assert_equal 0, plan.transactions.count
  end

  test "destroying the msi purchase removes its plan and installments" do
    unrelated = create_transaction(account: @credit_card, amount: 50, name: "Coffee", date: Date.current)
    purchase = create_transaction(account: @credit_card, amount: 3000, name: "Laptop", date: Date.current - 2.months - 5.days)
    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)
    assert_equal 3, plan.transactions.where(kind: "installment").count

    Account.any_instance.expects(:sync_later).once

    assert_difference -> { RecurringTransaction.count } => -1, -> { Entry.count } => -4 do
      purchase.destroy!
    end

    assert Entry.exists?(unrelated.id)
    assert_equal 0, Transaction.where(recurring_transaction_id: plan.id).count
  end

  test "destroying an installments plan reverts the purchase to standard" do
    purchase = create_transaction(account: @credit_card, amount: 3000, name: "Laptop", date: Date.current - 2.months - 5.days)
    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)

    assert_difference -> { Entry.count } => -3 do
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
    RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)

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

    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)

    assert purchase.entryable.reload.msi_purchase?
    assert_equal plan, purchase.entryable.recurring_transaction
    assert_equal purchase.date, plan.start_date
    assert_equal 3, plan.transactions.where(kind: "installment").count
  end

  test "a monthly card purchase puts installment 1 on the purchase date" do
    travel_to Date.new(2026, 10, 1)
    purchase = create_transaction(account: @credit_card, amount: 3000, name: "Laptop", date: Date.new(2026, 10, 1))

    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)

    assert purchase.entryable.reload.msi_purchase?
    assert_equal [ Date.new(2026, 10, 1) ], plan.transactions.where(kind: "installment").map { |t| t.entry.date }
    assert_equal [ 1 ], plan.transactions.where(kind: "installment").pluck(:installment_number)
    assert_equal Date.new(2026, 12, 1), plan.end_date
    assert_equal Date.new(2026, 11, 1), plan.next_payment_date
  end

  test "create_from_entry! links a charge's original entry as the first occurrence" do
    entry = create_transaction(account: @credit_card, amount: 299, name: "Netflix", date: Date.current)

    plan = RecurringTransaction.create_from_entry!(entry, frequency: "monthly")

    assert_equal 1, entry.entryable.reload.installment_number
    assert_equal 1, plan.transactions.count
  end

  test "create_from_entry! rejects transactions that can't repeat" do
    linked = create_transaction(account: @credit_card, amount: 100, name: "Netflix")
    RecurringTransaction.create_from_entry!(linked, frequency: "monthly")

    {
      create_transaction(account: @credit_card, amount: 100, kind: "cc_payment") => "Transfers can't repeat.",
      create_transaction(account: @credit_card, amount: 100, kind: "one_time") => "Turn off One-time Expense to set this up.",
      create_transaction(account: @credit_card, amount: -100) => "Only expenses can repeat.",
      linked => "This is already part of a recurring payment."
    }.each do |entry, message|
      error = assert_raises(ActiveRecord::RecordInvalid) do
        RecurringTransaction.create_from_entry!(entry, frequency: "monthly")
      end
      assert_includes error.record.errors[:base], message
    end
  end

  test "a transaction in another currency than the family's can't become a plan" do
    entry = create_transaction(account: @credit_card, amount: 100, name: "Imported", currency: "MXN")

    assert_equal :foreign_currency, RecurringTransaction.ineligibility_reason(entry)
    error = assert_raises(ActiveRecord::RecordInvalid) do
      RecurringTransaction.create_from_entry!(entry, frequency: "monthly")
    end
    assert_includes error.record.errors[:base], "Recurring payments only work in your main currency."
  end

  test "plans require a manual, active account" do
    plan = build_plan(plan_type: "charge", total_payments: nil, account: accounts(:connected))

    assert_not plan.valid?
    assert_includes plan.errors[:account], "Only manual accounts can have recurring payments."
  end

  test "validation messages are the interface copy" do
    assert_equal [ "Enter 2 to 48 payments." ], build_plan(total_payments: 49).tap(&:validate).errors[:total_payments]
    assert_equal [ "Too small to split into 6 payments. Use fewer." ],
                 build_plan(amount: BigDecimal("0.05"), total_payments: 6).tap(&:validate).errors[:total_payments]
    assert_equal [ "Enter a whole number, or leave it empty." ],
                 build_plan(plan_type: "charge", total_payments: "abc").tap(&:validate).errors[:total_payments]
  end

  test "a charge's end count beyond the integer column is invalid" do
    plan = build_plan(plan_type: "charge", total_payments: "3000000000")

    assert_not plan.valid?
    assert_equal [ "Enter a whole number, or leave it empty." ], plan.errors[:total_payments]
  end

  test "the schedule can't change after the plan is created" do
    plan = build_plan
    plan.save!

    assert_not plan.update(total_payments: 6)
    assert_not plan.reload.update(frequency: "weekly")
    assert plan.reload.update(name: "New laptop")
  end

  test "backfill_count leaves out the source transaction when it is payment 1" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: @credit_card, amount: 3000, date: Date.new(2026, 7, 8))
    other = create_transaction(account: accounts(:depository), amount: 3000, date: Date.new(2026, 7, 8))

    card_installments = RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: 6)
    charge = RecurringTransaction.build_from_entry(purchase, frequency: "monthly")
    other_installments = RecurringTransaction.build_from_entry(other, frequency: "monthly", total_payments: 6)

    # Oct 8 is today, so it isn't a past payment
    assert_equal 3, card_installments.backfill_count  # Jul 8 (installment 1), Aug 8, Sep 8
    assert_equal 2, charge.backfill_count             # Aug 8, Sep 8 (Jul 8 is the purchase itself)
    assert_equal 2, other_installments.backfill_count # Aug 8, Sep 8 (Jul 8 is payment 1)
  end

  test "a purchase made today has no past payments" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: @credit_card, amount: 3000, date: Date.new(2026, 10, 8))

    assert_equal 0, RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: 6).backfill_count
  end

  test "ended_on and monthly_amount describe the plan" do
    plan = build_plan(start_date: Date.new(2026, 1, 15))
    plan.save!

    assert_equal BigDecimal("333.33"), plan.monthly_amount
    assert_equal BigDecimal("333.33"), plan.next_payment_amount
    assert_nil plan.ended_on

    plan.cancel!
    assert_equal plan.updated_at.to_date, plan.ended_on
  end

  test "occurrence dates follow the frequency and clamp to shorter months" do
    {
      "daily" => [ Date.new(2026, 1, 31), Date.new(2026, 2, 1), Date.new(2026, 2, 2) ],
      "weekly" => [ Date.new(2026, 1, 31), Date.new(2026, 2, 7), Date.new(2026, 2, 14) ],
      "monthly" => [ Date.new(2026, 1, 31), Date.new(2026, 2, 28), Date.new(2026, 3, 31) ],
      "bimonthly" => [ Date.new(2025, 12, 31), Date.new(2026, 2, 28), Date.new(2026, 4, 30) ],
      "quarterly" => [ Date.new(2025, 11, 30), Date.new(2026, 2, 28), Date.new(2026, 5, 30) ],
      "semiannual" => [ Date.new(2025, 8, 31), Date.new(2026, 2, 28), Date.new(2026, 8, 31) ],
      "annual" => [ Date.new(2024, 2, 29), Date.new(2025, 2, 28), Date.new(2026, 2, 28) ]
    }.each do |frequency, dates|
      plan = build_plan(frequency: frequency, start_date: dates.first)

      assert_equal dates, (1..3).map { |n| plan.occurrence_date(n) }, frequency
    end
  end

  test "a weekly plan ends on its last weekly payment" do
    assert_equal Date.new(2026, 10, 15), build_plan(frequency: "weekly", start_date: Date.new(2026, 10, 1)).end_date
  end

  test "frequency must be one of the supported ones" do
    plan = build_plan(frequency: "fortnightly")

    assert_not plan.valid?
    assert_equal [ "Choose how often it repeats." ], plan.errors[:frequency]
    assert build_plan(frequency: "weekly").valid?
  end

  test "a month of a weekly plan costs every payment in the month of the next one" do
    travel_to Date.new(2026, 10, 8)
    plan = build_plan(plan_type: "charge", frequency: "weekly", amount: 50, total_payments: nil, start_date: Date.new(2026, 10, 1))
    plan.save!

    assert_equal BigDecimal("250"), plan.monthly_amount # Oct 1, 8, 15, 22, 29
    assert_equal BigDecimal("50"), plan.next_payment_amount
  end

  test "a month of a daily plan costs every day of the month" do
    travel_to Date.new(2026, 10, 8)
    plan = build_plan(plan_type: "charge", frequency: "daily", amount: 10, total_payments: nil, start_date: Date.new(2026, 10, 1))
    plan.save!

    assert_equal BigDecimal("310"), plan.monthly_amount # Oct 1..31
  end

  test "a weekly installments plan cut short by its end count only counts the payments that exist" do
    travel_to Date.new(2026, 10, 8)
    plan = build_plan(frequency: "weekly", amount: 300, total_payments: 3, start_date: Date.new(2026, 10, 22))
    plan.save!

    assert_equal BigDecimal("200"), plan.monthly_amount # Oct 22 and 29; the third payment is in November
  end

  test "a monthly plan counts one payment per month even with a custom cycle end day" do
    travel_to Date.new(2026, 1, 20)
    plan = build_plan(frequency: "monthly", amount: 900, total_payments: 3, start_date: Date.new(2026, 1, 31))
    plan.save!
    plan.family.update!(cycle_end_day: 29)

    assert_equal BigDecimal("300"), plan.reload.monthly_amount # Jan 31 and Feb 28 share the Jan 30 - Feb 28 cycle
  end

  test "an end count makes installments and no end makes a charge" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: @credit_card, amount: 1200, date: Date.new(2026, 10, 8))

    charge = RecurringTransaction.build_from_entry(purchase, frequency: "weekly")
    card_installments = RecurringTransaction.build_from_entry(purchase, frequency: "weekly", total_payments: "4")

    assert charge.charge?
    assert_equal Date.new(2026, 10, 8), charge.start_date
    assert card_installments.installments?
    assert_equal Date.new(2026, 10, 8), card_installments.start_date # the first installment is on the purchase date
  end

  test "end counts must be 2 to 48 on any account" do
    purchase = create_transaction(account: accounts(:depository), amount: 1200, date: Date.new(2026, 10, 8))

    [ "1", "0", "-3", "49", "abc" ].each do |count|
      plan = RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: count)

      assert_equal [ "Enter 2 to 48 payments." ], plan.tap(&:validate).errors[:total_payments], count
    end
    assert RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: "3").valid?
  end

  test "an unknown frequency is a validation error, not an exception" do
    purchase = create_transaction(account: @credit_card, amount: 100, date: Date.new(2026, 10, 8))
    plan = RecurringTransaction.build_from_entry(purchase, frequency: "fortnightly", total_payments: "3")

    assert_not plan.valid?
    assert_equal [ "Choose how often it repeats." ], plan.errors[:frequency]
    assert_equal purchase.date, plan.start_date
  end

  test "installments off a card turn the purchase into payment 1 of standard payments" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: accounts(:depository), amount: 1000, name: "Sofa", date: Date.new(2026, 8, 20))

    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)

    purchase.reload
    assert_equal BigDecimal("333.33"), purchase.amount
    assert purchase.entryable.standard?
    assert_equal 1, purchase.entryable.installment_number
    assert_equal BigDecimal("1000"), plan.amount
    assert_equal Date.new(2026, 8, 20), plan.start_date
    assert_equal [ 1, 2 ], plan.transactions.order(:installment_number).pluck(:installment_number)
    assert plan.transactions.all?(&:standard?)
    assert_equal 1, plan.remaining_payments
    assert_equal BigDecimal("333.34"), plan.remaining_balance
    assert_equal Date.new(2026, 10, 20), plan.end_date
  end

  test "a failed plan creation leaves the entry and transaction as they were" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: accounts(:depository), amount: 900, date: Date.new(2026, 8, 20))
    RecurringTransaction.any_instance.stubs(:generate_due!).raises(ActiveRecord::RecordInvalid.new(RecurringTransaction.new))

    assert_raises(ActiveRecord::RecordInvalid) do
      RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)
    end

    assert_equal BigDecimal("900"), purchase.amount
    assert_equal BigDecimal("900"), purchase.reload.amount
    assert_nil purchase.entryable.recurring_transaction_id
    assert_nil purchase.entryable.installment_number
    assert_not purchase.changed?
  end

  test "deleting payment 1 of an installments plan off a card leaves the plan active and the gap closed" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: accounts(:depository), amount: 900, date: Date.new(2026, 8, 20))
    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)

    purchase.destroy!
    plan.reload
    plan.generate_due!

    assert_equal "active", plan.status
    assert_equal [ 2 ], plan.transactions.pluck(:installment_number)
    assert_equal 1, plan.remaining_payments
    assert_equal BigDecimal("300"), plan.remaining_balance
  end

  test "destroying an installments plan off a card keeps its payments" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: accounts(:depository), amount: 900, date: Date.new(2026, 8, 20))
    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)

    assert_no_difference -> { Entry.count } do
      plan.destroy!
    end
    assert_nil purchase.entryable.reload.recurring_transaction_id
  end

  test "payments of installments off a card are locked like installments; charge rows are not" do
    travel_to Date.new(2026, 10, 8)
    purchase = create_transaction(account: accounts(:depository), amount: 900, name: "Sofa", date: Date.new(2026, 8, 20))
    plan = RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)
    payment = plan.transactions.find_by(installment_number: 2).entry

    assert_equal 300, purchase.reload.amount # creation rewrote the amount before linking, with the lock in place
    assert payment.entryable.plan_locked?
    assert purchase.reload.entryable.plan_locked?
    assert_not payment.update(amount: 5)
    assert_equal [ "Set by the plan." ], payment.errors[:amount]
    assert_not payment.reload.entryable.update(kind: "one_time")
    assert payment.reload.update(date: Date.new(2026, 9, 21))

    gym = create_transaction(account: accounts(:depository), amount: 50, name: "Gym", date: Date.new(2026, 10, 1))
    RecurringTransaction.create_from_entry!(gym, frequency: "monthly")
    assert_not gym.reload.entryable.plan_locked?
    assert gym.update(amount: 60)
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
