class RecurringTransaction < ApplicationRecord
  PLAN_TYPES = %w[charge installments].freeze
  STATUSES = %w[active cancelled completed].freeze

  Occurrence = Data.define(:number, :date, :amount)

  belongs_to :family
  belongs_to :account
  belongs_to :category, optional: true
  belongs_to :merchant, optional: true
  has_many :transactions, dependent: :nullify

  validates :name, :currency, :start_date, presence: true
  validates :plan_type, inclusion: { in: PLAN_TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :amount, numericality: { greater_than: 0 }
  validates :total_payments, numericality: { only_integer: true, greater_than_or_equal_to: 2 }, if: :installments?
  validates :total_payments, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true, unless: :installments?
  validate :installments_require_credit_card

  scope :active, -> { where(status: "active") }

  def self.create_from_entry!(entry, plan_type:, total_payments: nil, start_date: nil)
    transaction do
      source = entry.entryable

      plan = create!(
        family: entry.account.family,
        account: entry.account,
        name: entry.name,
        category: source.category,
        merchant: source.merchant,
        plan_type: plan_type,
        amount: entry.amount,
        currency: entry.currency,
        total_payments: total_payments,
        start_date: start_date || (plan_type == "installments" ? entry.date.next_month : entry.date)
      )

      if plan.installments?
        source.update!(kind: "msi_purchase", recurring_transaction: plan)
      else
        source.update!(recurring_transaction: plan, installment_number: 1)
      end

      plan.generate_due!
      plan
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

  def remaining_payments
    total_payments && total_payments - generated_numbers.size
  end

  def remaining_balance
    return BigDecimal("0") unless installments?

    amount - generated_numbers.sum { |number| occurrence_amount(number) }
  end

  def upcoming(through:)
    taken = generated_numbers.to_set

    (1..).lazy
      .map { |number| Occurrence.new(number: number, date: occurrence_date(number), amount: occurrence_amount(number)) }
      .take_while { |occurrence| occurrence.date <= through && (total_payments.nil? || occurrence.number <= total_payments) }
      .reject { |occurrence| taken.include?(occurrence.number) }
      .to_a
  end

  def cancel!
    update!(status: "cancelled")
  end

  def generate_due!(as_of: Date.current)
    return 0 unless status == "active"

    created = upcoming(through: as_of).count { |occurrence| create_occurrence(occurrence) }

    update!(last_generated_on: as_of, status: fully_generated? ? "completed" : status)
    account.sync_later if created.positive?

    created
  end

  private
    def installments_require_credit_card
      return unless installments? && account

      errors.add(:account, "must be a credit card for installments") unless account.accountable_type == "CreditCard"
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
      total_payments.present? && generated_numbers.size >= total_payments
    end
end
