# Recurring payments on one account (the credit card's "Recurring payments" tab)
class Account::RecurringCommitments
  UPCOMING_MONTHS = 3

  attr_reader :account

  def initialize(account)
    @account = account
  end

  def plans
    @plans ||= account.recurring_transactions.includes(:category, :transactions).order(:name).to_a
  end

  def any?
    plans.any?
  end

  def active_installment_plans
    plans.select { |plan| plan.status == "active" && plan.installments? }.sort_by(&:end_date)
  end

  def active_charge_plans
    plans.select { |plan| plan.status == "active" && plan.charge? }
  end

  def past_plans
    plans.reject { |plan| plan.status == "active" }.sort_by { |plan| plan.ended_on || Date.new(1970) }.reverse
  end

  # Headline figures count the plans that still generate (manual, active account), the same
  # ones Upcoming lists, so the numbers and the list never disagree.
  def committed_per_month
    counted_plans.sum(BigDecimal("0"), &:monthly_amount)
  end

  def left_on_installments
    counted_plans.select(&:installments?).sum(BigDecimal("0"), &:remaining_balance)
  end

  def last_installment_date
    counted_plans.select(&:installments?).filter_map(&:end_date).max
  end

  # Not-yet-generated payments from the start of this month through the end of the second next one
  def upcoming
    @upcoming ||= family.recurring_commitments(
      start_date: family.cycle_range_containing(family.today).first,
      end_date: upcoming_end_date,
      accounts: [ account ],
      include_generated: false
    )
  end

  # Budget param of the first month after Upcoming ("See later months")
  def later_months_budget_param
    Budget.date_to_param(family.cycle_range_containing(upcoming_end_date + 1.day).last)
  end

  private
    def counted_plans
      return [] unless account.manual? && account.active?

      active_installment_plans + active_charge_plans
    end

    def family
      account.family
    end

    def upcoming_end_date
      cycle_end = family.cycle_range_containing(family.today).last
      (UPCOMING_MONTHS - 1).times { cycle_end = family.cycle_range_containing(cycle_end + 1.day).last }
      cycle_end
    end
end
