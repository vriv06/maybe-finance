# The virtual `recurrence[...]` params of the capture and convert forms (kept out of entry params)
module RecurrenceParams
  extend ActiveSupport::Concern

  private
    def recurrence_params
      params.fetch(:recurrence, {}).permit(:plan_type, :total_payments, :start_date)
    end

    def recurrence_requested?
      recurrence_params[:plan_type].in?(RecurringTransaction::PLAN_TYPES)
    end

    # start_date is only passed when the form sent it, so a cleared field is an error rather than the default
    def recurrence_attributes
      attributes = { plan_type: recurrence_params[:plan_type], total_payments: recurrence_params[:total_payments].presence }
      attributes[:start_date] = recurrence_params[:start_date].to_s if recurrence_params.key?(:start_date)
      attributes
    end

    def recurrence_notice(plan)
      plan.installments? ? "Split into #{plan.total_payments} installments." : "Monthly charge started."
    end
end
