class BudgetsController < ApplicationController
  before_action :set_budget, only: %i[show edit update]

  def index
    redirect_to_current_month_budget
  end

  def show
  end

  def edit
    @previous_budget = @budget.previous_budget
    render layout: "wizard"
  end

  def update
    @budget.update!(budget_params.except(:autofill_previous_month))
    @budget.copy_categories_from!(@budget.previous_budget) if budget_params[:autofill_previous_month] == "1"
    redirect_to budget_budget_categories_path(@budget)
  end

  def picker
    render partial: "budgets/picker", locals: {
      family: Current.family,
      year: params[:year].to_i || Date.current.year
    }
  end

  private

    def budget_create_params
      params.require(:budget).permit(:start_date)
    end

    def budget_params
      params.require(:budget).permit(:budgeted_spending, :expected_income, :autofill_previous_month)
    end

    def set_budget
      start_date = Budget.param_to_date(params[:month_year])
      @budget = Budget.find_or_bootstrap(Current.family, start_date: start_date)
      raise ActiveRecord::RecordNotFound unless @budget
    end

    def redirect_to_current_month_budget
      current_budget = Budget.find_or_bootstrap(Current.family, start_date: Date.current)
      redirect_to budget_path(current_budget)
    end
end
