class RecurringTransaction < ApplicationRecord
  PLAN_TYPES = %w[charge installments].freeze
  STATUSES = %w[active cancelled completed].freeze
  MAX_INSTALLMENTS = 48

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

  # The entry a plan is being built from (capture, preview, convert); drives eligibility and first-payment checks
  attr_accessor :source_entry

  validates :name, :currency, presence: true
  validates :start_date, presence: { message: "Choose a date for the first payment." }
  validates :plan_type, inclusion: { in: PLAN_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :amount, numericality: { greater_than: 0 }
  validate :total_payments_in_range
  validate :installment_amount_large_enough
  validate :installments_require_credit_card
  validate :account_manual_and_active, on: :create
  validate :first_payment_not_before_purchase, on: :create
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

    def build_from_entry(entry, plan_type:, total_payments: nil, start_date: nil)
      source = entry.entryable

      new(
        source_entry: entry,
        family: entry.account.family,
        account: entry.account,
        name: entry.name,
        category: source.try(:category),
        merchant: source.try(:merchant),
        plan_type: plan_type,
        amount: entry.amount,
        currency: entry.currency,
        total_payments: total_payments,
        start_date: plan_type == "installments" ? first_payment_date(entry, start_date) : entry.date
      )
    end

    def create_from_entry!(entry, **attributes)
      transaction do
        plan = build_from_entry(entry, **attributes)
        plan.save!

        source = entry.entryable
        if plan.installments?
          source.update!(kind: "msi_purchase", recurring_transaction: plan)
        else
          source.update!(recurring_transaction: plan, installment_number: 1)
        end

        plan.generate_due!
        plan
      end
    end

    private
      # nil means "not provided" (default: one month after the purchase); a blank or invalid string stays nil
      def first_payment_date(entry, start_date)
        return entry.date&.next_month if start_date.nil?
        return start_date unless start_date.is_a?(String)

        Date.iso8601(start_date)
      rescue Date::Error
        nil
      end
  end

  def installments?
    plan_type == "installments"
  end

  def charge?
    plan_type == "charge"
  end

  def occurrence_date(number)
    start_date.advance(months: number - 1)
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

  def generated_numbers
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

  # What one month of this plan costs: the next installment, or the charge amount
  def monthly_amount
    next_number = last_handled_number + 1
    next_number = total_payments if total_payments && next_number > total_payments
    occurrence_amount(next_number)
  end

  # Occurrences that saving this plan adds with past dates (a charge's first payment is the source transaction)
  def backfill_count(as_of: family.today)
    upcoming(through: as_of).count { |occurrence| installments? || occurrence.number > 1 }
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
    def total_payments_in_range
      raw = total_payments_before_type_cast.to_s.strip
      whole = raw.match?(/\A\d+\z/) ? raw.to_i : nil

      if installments?
        unless whole&.between?(2, MAX_INSTALLMENTS)
          errors.add(:total_payments, "Enter 2 to #{MAX_INSTALLMENTS} installments.")
        end
      elsif raw.present? && !(whole && whole >= 1)
        errors.add(:total_payments, "Enter a whole number, or leave it empty.")
      end
    end

    def installment_amount_large_enough
      return unless installments? && amount.present? && total_payments.present?
      return if errors.include?(:total_payments)
      return if (amount / total_payments).floor(2) >= BigDecimal("0.01")

      errors.add(:total_payments, "Too small to split into #{total_payments} installments. Use fewer.")
    end

    def installments_require_credit_card
      return unless installments? && account

      errors.add(:account, "Installments only work on credit cards.") unless account.accountable_type == "CreditCard"
    end

    def account_manual_and_active
      return unless account
      return if account.manual? && account.active?

      errors.add(:account, INELIGIBILITY_MESSAGES[:account_not_manual])
    end

    def first_payment_not_before_purchase
      return unless installments? && start_date && source_entry&.date
      return if start_date >= source_entry.date

      errors.add(:start_date, "The first payment can't be before #{source_entry.date.strftime("%b %-d, %Y")}.")
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
                         will_save_change_to_plan_type? || (installments? && will_save_change_to_amount?)
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
            kind: installments? ? "installment" : "standard",
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
      return unless installments?

      installment_ids = transactions.where(kind: "installment").where.not(installment_number: nil).select(:id)
      Entry.where(entryable_type: "Transaction", entryable_id: installment_ids).find_each(&:destroy!)
      transactions.where(kind: "msi_purchase").find_each(&:release_from_plan!)
    end

    def sync_account_later
      account.sync_later
    end
end
