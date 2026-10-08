class Transaction < ApplicationRecord
  include Entryable, Transferable, Ruleable

  belongs_to :category, optional: true
  belongs_to :merchant, optional: true
  belongs_to :recurring_transaction, optional: true

  has_many :taggings, as: :taggable, dependent: :destroy
  has_many :tags, through: :taggings

  accepts_nested_attributes_for :taggings, allow_destroy: true

  enum :kind, {
    standard: "standard", # A regular transaction, included in budget analytics
    funds_movement: "funds_movement", # Movement of funds between accounts, excluded from budget analytics
    cc_payment: "cc_payment", # A CC payment, excluded from budget analytics (CC payments offset the sum of expense transactions)
    loan_payment: "loan_payment", # A payment to a Loan account, treated as an expense in budgets
    one_time: "one_time", # A one-time expense/income, excluded from budget analytics
    msi_purchase: "msi_purchase", # Full installment purchase: adds debt, spending comes from its installments
    installment: "installment" # Generated installment: counts as spending, does not change the balance
  }

  BUDGET_EXCLUDED_KINDS = %w[funds_movement one_time cc_payment msi_purchase].freeze
  BALANCE_EXCLUDED_KINDS = %w[installment].freeze

  def self.budget_excluded_kinds_sql
    BUDGET_EXCLUDED_KINDS.map { |kind| connection.quote(kind) }.join(", ")
  end

  # Overarching grouping method for all transfer-type transactions
  def transfer?
    funds_movement? || cc_payment? || loan_payment?
  end

  def set_category!(category)
    if category.is_a?(String)
      category = entry.account.family.categories.find_or_create_by!(
        name: category
      )
    end

    update!(category: category)
  end
end
