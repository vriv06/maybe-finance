# Capture-time "Monthly projection": the budget months of the next payments of a (usually unsaved)
# plan, with what recurring payments already commit, the category spending they don't cover and
# this purchase, compared with the same basis budget as the budget screen.
class RecurringTransaction::BudgetImpact
  MAX_MONTHS = 3
  LEGEND_CATEGORIES = 4
  OTHER_LABEL = "Other"
  SHORT_FREQUENCIES = %w[daily weekly].freeze

  Segment = Data.define(:label, :color, :amount, :other)

  Month = Data.define(:budget, :committed, :category_segments, :purchase, :basis_budget) do
    def basis
      basis_budget.budgeted_spending
    end

    def category_spend
      category_segments.sum(BigDecimal("0"), &:amount)
    end

    def total
      committed + category_spend + purchase
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

    # Future months show category averages instead of real spending
    def estimated?
      budget.future?
    end
  end

  attr_reader :plan

  def initialize(plan)
    @plan = plan
  end

  # Every payment in the first MAX_MONTHS budget months that haven't ended
  def occurrences
    @occurrences ||= next_occurrences
  end

  def payments_count
    occurrences.size
  end

  # Daily and weekly plans put many payments in a month, so the subtitle counts months
  def counts_months?
    plan.frequency.in?(SHORT_FREQUENCIES)
  end

  def months
    @months ||= begin
      rows = occurrences.group_by { |occurrence| family.cycle_range_containing(occurrence.date).first }.filter_map do |start_date, group|
        budget = Budget.for_cycle(family, start_date)
        basis_budget = budget.basis_budget
        next unless basis_budget&.budgeted_spending&.positive?

        [ budget, basis_budget, group.sum(BigDecimal("0"), &:amount) ]
      end

      @legend_categories = rank_categories(rows.flat_map { |budget, _, _| budget.category_spend_for_projection })

      rows.map do |budget, basis_budget, purchase|
        Month.new(budget: budget, committed: budget.committed_spending,
                  category_segments: segments_for(budget.category_spend_for_projection),
                  purchase: purchase, basis_budget: basis_budget)
      end
    end
  end

  def legend_categories
    months
    @legend_categories
  end

  # [label, color] for each category segment colour, in bar order, "Other" last when used
  def category_legend
    entries = legend_categories.map { |category| [ category.name, category.color ] }
    entries << [ OTHER_LABEL, Category::UNCATEGORIZED_COLOR ] if months.any? { |month| month.category_segments.any?(&:other) }
    entries
  end

  def available?
    months.any?
  end

  def over_months
    months.select(&:over?)
  end

  # Shared bar scale for every month: the budget mark sits at 83.3% and nothing overflows
  def scale
    return BigDecimal("0") if months.empty?

    [ *months.map { |month| month.basis * BigDecimal("1.2") }, *months.map(&:total) ].max
  end

  def width(amount)
    return 0.0 if scale.zero?

    (amount / scale * 100).round(1).to_f
  end

  def reference_budget
    months.find(&:reference?)&.basis_budget
  end

  private
    def family
      plan.family
    end

    def next_occurrences
      return [] unless plan.start_date && RecurringTransaction::FREQUENCIES.key?(plan.frequency)

      today = family.today
      month_starts = []
      result = []

      (1..).each do |number|
        break if plan.total_payments && number > plan.total_payments

        date = plan.occurrence_date(number)
        month_start, month_end = family.cycle_range_containing(date)
        next if month_end < today

        unless month_starts.include?(month_start)
          break if month_starts.size == MAX_MONTHS

          month_starts << month_start
        end

        result << RecurringTransaction::Occurrence.new(number: number, date: date, amount: plan.occurrence_amount(number))
      end

      result
    end

    # Top categories by spend across the months shown. With more than LEGEND_CATEGORIES, Uncategorized joins "Other"
    def rank_categories(rows)
      ranked = rows.group_by { |row| row.category.id }
        .map { |_, group| [ group.first.category, group.sum(BigDecimal("0"), &:amount) ] }
        .sort_by { |_, amount| -amount }
        .map(&:first)

      ranked.size > LEGEND_CATEGORIES ? ranked.reject { |category| category.id.nil? }.first(LEGEND_CATEGORIES) : ranked
    end

    def segments_for(rows)
      legend_ids = @legend_categories.map(&:id)

      shown = @legend_categories.filter_map do |category|
        row = rows.find { |candidate| candidate.category.id == category.id }
        Segment.new(label: category.name, color: category.color, amount: row.amount, other: false) if row
      end

      rest = rows.reject { |row| legend_ids.include?(row.category.id) }.sum(BigDecimal("0"), &:amount)
      return shown unless rest.positive?

      shown + [ Segment.new(label: OTHER_LABEL, color: Category::UNCATEGORIZED_COLOR, amount: rest, other: true) ]
    end
end
