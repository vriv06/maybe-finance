# Capture-time projection: how the next installments of a (usually unsaved) plan land on
# the budget months they fall in, using the same committed/basis numbers as the budget screen.
class RecurringTransaction::BudgetImpact
  MAX_INSTALLMENTS = 3

  Month = Data.define(:budget, :committed, :purchase, :basis_budget) do
    def basis
      basis_budget.budgeted_spending
    end

    def total
      committed + purchase
    end

    def over?
      total > basis
    end

    def overage
      total - basis
    end

    # Whole percent; rounded up once over so it never reads "100%" while over budget
    def percent
      ratio = total / basis * 100
      over? ? ratio.ceil : ratio.floor
    end

    def reference?
      basis_budget != budget
    end
  end

  attr_reader :plan

  def initialize(plan)
    @plan = plan
  end

  # The next installments still to come (their month hasn't ended), at most three
  def occurrences
    @occurrences ||= begin
      return [] unless plan.installments? && plan.total_payments && plan.start_date

      (1..plan.total_payments).lazy
        .map { |n| RecurringTransaction::Occurrence.new(number: n, date: plan.occurrence_date(n), amount: plan.occurrence_amount(n)) }
        .reject { |occurrence| family.cycle_range_containing(occurrence.date).last < family.today }
        .first(MAX_INSTALLMENTS)
    end
  end

  def installments_count
    occurrences.size
  end

  def months
    @months ||= occurrences.group_by { |occurrence| family.cycle_range_containing(occurrence.date).first }.filter_map do |start_date, group|
      budget = Budget.for_cycle(family, start_date)
      basis_budget = budget.basis_budget
      next unless basis_budget&.budgeted_spending&.positive?

      Month.new(budget: budget, committed: budget.committed_spending,
                purchase: group.sum(BigDecimal("0"), &:amount), basis_budget: basis_budget)
    end
  end

  def available?
    months.any?
  end

  def over_months
    months.select(&:over?)
  end

  # Shared bar scale for every month: the budget mark sits at 83.3% and nothing overflows
  def scale
    [ *months.map { |month| month.basis * BigDecimal("1.2") }, *months.map(&:total) ].max
  end

  def width(amount)
    (amount / scale * 100).round(1).to_f
  end

  def reference_budget
    months.find(&:reference?)&.basis_budget
  end

  private
    def family
      plan.family
    end
end
