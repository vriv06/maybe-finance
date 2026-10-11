class RecurringTransaction < ApplicationRecord
  PLAN_TYPES = %w[charge installments].freeze
  STATUSES = %w[active cancelled completed].freeze
  MAX_INSTALLMENTS = 48
  MAX_CHARGE_PAYMENTS = 600

  # How far apart payments are, keyed by the stored value; the UI labels live in RecurringTransactionsHelper
  FREQUENCIES = {
    "daily" => 1.day,
    "weekly" => 1.week,
    "monthly" => 1.month,
    "bimonthly" => 2.months,
    "quarterly" => 3.months,
    "semiannual" => 6.months,
    "annual" => 1.year
  }.freeze

  INELIGIBILITY_MESSAGES = {
    transfer: "Transfers can't repeat.",
    already_linked: "This is already part of a recurring payment.",
    not_standard: "Turn off One-time Expense to set this up.",
    income: "Only expenses can repeat.",
    account_not_manual: "Only manual accounts can have recurring payments.",
    foreign_currency: "Recurring payments only work in your main currency."
  }.freeze

  GENERIC_ERROR = "We couldn't set this up. Nothing changed. Try again.".freeze

  Occurrence = Data.define(:number, :date, :amount)

  belongs_to :family
  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :merchant, optional: true
  # Runs before the nullify below so installments are removed and the purchase reverted first
  before_destroy :release_transactions
  has_many :transactions, dependent: :nullify
  after_destroy :sync_account_later, unless: :destroyed_by_association

  # The entry a plan is being built from (capture, preview, convert); drives the eligibility check
  attr_accessor :source_entry

  validates :name, :currency, presence: true
  validates :start_date, presence: { message: "Choose a date for the first payment." }
  validates :plan_type, inclusion: { in: PLAN_TYPES }
  validates :frequency, inclusion: { in: FREQUENCIES.keys, message: "Choose how often it repeats." }
  validates :status, inclusion: { in: STATUSES }
  validates :amount, numericality: { greater_than: 0 }
  validate :total_payments_in_range
  validate :installment_amount_large_enough
  validate :account_manual_and_active, on: :create
  validate :source_entry_eligible, on: :create
  validate :schedule_unchanged, on: :update

  scope :active, -> { where(status: "active") }
  scope :generatable, -> { active.joins(:account).merge(Account.manual).where(accounts: { status: "active" }) }

  class << self
    # Why an entry can't become (part of) a plan, or nil when it can
    def ineligibility_reason(entry)
      transaction = entry.entryable
      return :not_standard unless transaction.is_a?(Transaction)
      return :transfer if transaction.transfer? || transaction.transfer.present?
      return :already_linked if transaction.recurring_transaction_id.present?
      return :not_standard unless transaction.standard?
      return :income if entry.amount.to_d.negative?
      return :account_not_manual unless entry.account.manual? && entry.account.active?
      return :foreign_currency unless entry.currency == entry.account.family.currency

      nil
    end

    # The plan type follows the end count: an end means a purchase in installments (the amount entered is the
    # total), no end means a recurring charge (the amount is per payment). Clients never choose it.
    def build_from_entry(entry, frequency:, total_payments: nil)
      source = entry.entryable
      total_payments = total_payments.presence

      plan = new(
        source_entry: entry,
        family: entry.account.family,
        account: entry.account,
        name: entry.name,
        category: source.try(:category),
        merchant: source.try(:merchant),
        frequency: frequency,
        plan_type: total_payments ? "installments" : "charge",
        amount: entry.amount,
        currency: entry.currency,
        total_payments: total_payments
      )
      plan.start_date = plan.first_payment_date_after(entry.date)
      plan
    end

    def create_from_entry!(entry, **attributes)
      source = entry.entryable
      originals = { entry => entry.slice(:amount), source => source.slice(:kind, :recurring_transaction_id, :installment_number) }

      transaction do
        plan = build_from_entry(entry, **attributes)
        plan.save!

        if plan.source_is_first_payment?
          # Installments off a card: the purchase becomes payment 1, so it keeps only its share of the total
          if plan.installments?
            entry.update!(amount: plan.occurrence_amount(1))
            entry.sync_account_later
          end
          source.update!(recurring_transaction: plan, installment_number: 1)
        else
          source.update!(kind: "msi_purchase", recurring_transaction: plan)
        end

        plan.generate_due!
        plan
      end
    rescue StandardError
      # The database rolled back, so the caller's records must not keep the plan's changes
      originals.each do |record, values|
        record.assign_attributes(values)
        record.clear_attribute_changes(values.keys)
      end
      raise
    end
  end

  def installments?
    plan_type == "installments"
  end

  def charge?
    plan_type == "charge"
  end

  def credit_card?
    account&.credit_card? || false
  end

  # Card installments keep the purchase apart (msi_purchase adds the debt); every other plan counts
  # its source transaction as payment 1
  def source_is_first_payment?
    charge? || !credit_card?
  end

  # Card installments start one interval after the purchase; otherwise the purchase is payment 1
  def first_payment_date_after(date)
    return date if date.nil? || source_is_first_payment? || !FREQUENCIES.key?(frequency)

    date + FREQUENCIES.fetch(frequency)
  end

  # Advances from the first payment, so month-based frequencies clamp without drifting
  # (monthly from Jan 31: Feb 28, then Mar 31)
  def occurrence_date(number)
    start_date + FREQUENCIES.fetch(frequency) * (number - 1)
  end

  # Installment plans store the total; each payment is floored to cents and the last absorbs the remainder
  def occurrence_amount(number)
    return amount unless installments?

    base = (amount / total_payments).floor(2)
    number == total_payments ? amount - base * (total_payments - 1) : base
  end

  def end_date
    total_payments && occurrence_date(total_payments)
  end

  # Callers must not preload :transactions on an instance before calling generate_due! (stale cache).
  def generated_numbers
    return transactions.filter_map(&:installment_number) if transactions.loaded?

    transactions.where.not(installment_number: nil).pluck(:installment_number)
  end

  # Every number up to this one is done (generated, or generated and later deleted).
  # Deleted occurrences are never regenerated, so the gap they leave is permanent.
  def last_handled_number
    [ generated_numbers.max || 0, numbers_generated_through(last_generated_on) ].max
  end

  def remaining_payments
    total_payments && [ total_payments - last_handled_number, 0 ].max
  end

  def remaining_balance
    return BigDecimal("0") unless installments?

    amount - (1..last_handled_number).sum(BigDecimal("0")) { |number| occurrence_amount(number) }
  end

  # What one budget month of this plan costs: every payment in the month of the next one
  # (a single payment for monthly and longer frequencies)
  def monthly_amount
    anchor = next_payment_number
    month_start, month_end = family.cycle_range_containing(occurrence_date(anchor))

    first = anchor
    first -= 1 while first > 1 && occurrence_date(first - 1) >= month_start
    last = anchor
    last += 1 while (total_payments.nil? || last < total_payments) && occurrence_date(last + 1) <= month_end

    (first..last).sum(BigDecimal("0")) { |number| occurrence_amount(number) }
  end

  # The next payment's amount (the last one's once every payment is handled)
  def next_payment_amount
    occurrence_amount(next_payment_number)
  end

  def next_payment_date
    next_number = last_handled_number + 1
    return nil if total_payments && next_number > total_payments

    occurrence_date(next_number)
  end

  # Occurrences that saving this plan adds with past dates (payment 1 is the source transaction unless it's a card purchase)
  def backfill_count(as_of: family.today)
    upcoming(through: as_of).count { |occurrence| !source_is_first_payment? || occurrence.number > 1 }
  end

  # The day a finished plan stopped: when it was stopped, or its last payment
  def ended_on
    case status
    when "cancelled" then updated_at.to_date
    when "completed" then end_date
    end
  end

  def budget_impact
    BudgetImpact.new(self)
  end

  def upcoming(through:)
    ((last_handled_number + 1)..).lazy
      .map { |number| Occurrence.new(number: number, date: occurrence_date(number), amount: occurrence_amount(number)) }
      .take_while { |occurrence| occurrence.date <= through && (total_payments.nil? || occurrence.number <= total_payments) }
      .to_a
  end

  def cancel!
    update!(status: "cancelled")
  end

  def generate_due!(as_of: family.today)
    return 0 unless status == "active"

    created = upcoming(through: as_of).count { |occurrence| create_occurrence(occurrence) }

    update!(last_generated_on: as_of, status: fully_generated? ? "completed" : status)
    account.sync_later if created.positive?

    created
  end

  private
    def next_payment_number
      [ last_handled_number + 1, total_payments ].compact.min
    end

    def total_payments_in_range
      raw = total_payments_before_type_cast.to_s.strip
      whole = raw.match?(/\A\d+\z/) ? raw.to_i : nil

      if installments?
        unless whole&.between?(2, MAX_INSTALLMENTS)
          errors.add(:total_payments, "Enter 2 to #{MAX_INSTALLMENTS} payments.")
        end
      elsif raw.present? && !whole&.between?(1, MAX_CHARGE_PAYMENTS)
        errors.add(:total_payments, "Enter a whole number, or leave it empty.")
      end
    end

    def installment_amount_large_enough
      return unless installments? && amount.present? && total_payments.present?
      return if errors.include?(:total_payments)
      return if (amount / total_payments).floor(2) >= BigDecimal("0.01")

      errors.add(:total_payments, "Too small to split into #{total_payments} payments. Use fewer.")
    end

    def account_manual_and_active
      return unless account
      return if account.manual? && account.active?

      errors.add(:account, INELIGIBILITY_MESSAGES[:account_not_manual])
    end

    def source_entry_eligible
      return unless source_entry

      reason = self.class.ineligibility_reason(source_entry)
      # A manual/active account is reported on :account by account_manual_and_active
      return if reason.nil? || reason == :account_not_manual

      errors.add(:base, INELIGIBILITY_MESSAGES.fetch(reason))
    end

    # D12: the schedule is fixed once created, so last_generated_on never needs a reset
    def schedule_unchanged
      changed_schedule = will_save_change_to_start_date? || will_save_change_to_total_payments? ||
                         will_save_change_to_frequency? || will_save_change_to_plan_type? || (installments? && will_save_change_to_amount?)
      errors.add(:base, "The schedule can't be changed. Stop this plan and add a new one.") if changed_schedule
    end

    def create_occurrence(occurrence)
      Entry.transaction(requires_new: true) do
        account.entries.create!(
          name: name,
          date: occurrence.date,
          amount: occurrence.amount,
          currency: currency,
          entryable: Transaction.new(
            kind: source_is_first_payment? ? "standard" : "installment",
            category: category,
            merchant: merchant,
            recurring_transaction: self,
            installment_number: occurrence.number
          )
        )
      end
      true
    rescue ActiveRecord::RecordNotUnique
      false
    end

    def fully_generated?
      total_payments.present? && last_handled_number >= total_payments
    end

    # generate_due! creates every occurrence dated on or before the day it ran, so those numbers are done
    def numbers_generated_through(date)
      return 0 if date.nil?

      number = 0
      number += 1 while occurrence_date(number + 1) <= date && (total_payments.nil? || number < total_payments)
      number
    end

    def release_transactions
      return if source_is_first_payment? # charges and installments off a card: payments stay, unlinked (dependent: :nullify)

      installment_ids = transactions.where(kind: "installment").where.not(installment_number: nil).select(:id)
      Entry.where(entryable_type: "Transaction", entryable_id: installment_ids).find_each(&:destroy!)
      transactions.where(kind: "msi_purchase").find_each(&:release_from_plan!)
    end

    def sync_account_later
      account.sync_later
    end
end
