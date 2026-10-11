# The virtual `recurrence[...]` params of the capture and convert forms (kept out of entry params)
module RecurrenceParams
  extend ActiveSupport::Concern

  private
    # A tampered `recurrence=foo` (not a hash) reads as "no recurrence" instead of raising.
    # plan_type and start_date are derived by the model, never taken from the client.
    def recurrence_params
      raw = params[:recurrence]
      raw.is_a?(ActionController::Parameters) ? raw.permit(:frequency, :total_payments) : ActionController::Parameters.new.permit
    end

    # Repeat isn't None. An unknown frequency still counts, so the plan reports it (422, never a 500)
    def recurrence_requested?
      recurrence_params[:frequency].present?
    end

    def recurrence_attributes
      { frequency: recurrence_params[:frequency].to_s, total_payments: recurrence_params[:total_payments].presence }
    end

    # b3.success_installments / r3.success_payments / r3.success_charge
    def recurrence_notice(plan)
      if plan.installments?
        "Split into #{plan.total_payments} #{helpers.recurring_payments_noun(plan)}."
      else
        "#{helpers.recurring_charge_label(plan)} started."
      end
    end
end
