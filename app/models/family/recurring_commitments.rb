# What recurring payments commit in a date range: rows the plans already generated plus the
# occurrences active plans will still add. The single source for C4, the capture preview,
# future budget months and the credit card's Upcoming list.
class Family::RecurringCommitments
  Item = Data.define(:plan, :number, :date, :amount, :category, :entry) do
    def generated?
      entry.present?
    end
  end

  attr_reader :family, :start_date, :end_date

  def initialize(family, start_date:, end_date:, accounts: nil, include_generated: true)
    @family = family
    @start_date = start_date
    @end_date = end_date
    @account_ids = accounts&.map(&:id)
    @include_generated = include_generated
  end

  def items
    @items ||= (generated_items + upcoming_items).sort_by { |item| [ item.date, item.plan.name, item.number ] }
  end

  def total
    items.sum(BigDecimal("0"), &:amount)
  end

  # Same roll-up as budget spending: a parent includes its subcategories; a category without id is "Uncategorized"
  def items_for(category)
    items.select do |item|
      if category.id.nil?
        item.category.nil?
      else
        item.category&.id == category.id || item.category&.parent_id == category.id
      end
    end
  end

  def total_for(category)
    items_for(category).sum(BigDecimal("0"), &:amount)
  end

  def by_date
    items.group_by(&:date)
  end

  private
    attr_reader :account_ids

    def plan_scope
      scope = family.recurring_transactions
      account_ids ? scope.where(account_id: account_ids) : scope
    end

    def generated_items
      return [] unless @include_generated

      Transaction.joins(:entry)
        .includes(:category, :entry, recurring_transaction: :account)
        .where(recurring_transaction_id: plan_scope.select(:id))
        .where.not(installment_number: nil)
        .where.not(kind: Transaction::BUDGET_EXCLUDED_KINDS)
        .where(entries: { date: start_date..end_date, excluded: false })
        .map do |transaction|
          Item.new(
            plan: transaction.recurring_transaction,
            number: transaction.installment_number,
            date: transaction.entry.date,
            amount: transaction.entry.amount,
            category: transaction.category,
            entry: transaction.entry
          )
        end
    end

    def upcoming_items
      plan_scope.generatable.includes(:category, :account).flat_map do |plan|
        plan.upcoming(through: end_date).filter_map do |occurrence|
          next if occurrence.date < start_date

          Item.new(plan: plan, number: occurrence.number, date: occurrence.date,
                   amount: occurrence.amount, category: plan.category, entry: nil)
        end
      end
    end
end
