# B3: turn an existing transaction into a recurring payment, inline in its drawer
class Transactions::RecurrencesController < ApplicationController
  include RecurrenceParams

  before_action :set_entry

  def show
    render_step :closed
  end

  def new
    unless recurrence_requested?
      @recurrence = RecurringTransaction.build_from_entry(@entry, plan_type: nil)
      return render_step(:fields)
    end

    @recurrence = RecurringTransaction.build_from_entry(@entry, **recurrence_attributes)

    if @recurrence.valid?
      render_step :confirm
    else
      render_step :fields, status: :unprocessable_entity
    end
  end

  def create
    @recurrence = RecurringTransaction.create_from_entry!(@entry, **recurrence_attributes)
    @entry.reload
    @focus_provenance = true
    flash.now[:notice] = recurrence_notice(@recurrence)

    render turbo_stream: [
      turbo_stream.replace("drawer", template: "transactions/show"),
      turbo_stream.replace(@entry, partial: "entries/entry", locals: { entry: @entry }),
      *flash_notification_stream_items
    ]
  rescue ActiveRecord::RecordInvalid => e
    @recurrence = RecurringTransaction.build_from_entry(@entry, **recurrence_attributes)
    render_step :confirm, status: :unprocessable_entity,
                error: e.record.errors.map(&:message).first || RecurringTransaction::GENERIC_ERROR
  rescue StandardError => e
    Rails.logger.error("Recurring conversion failed for entry #{@entry.id}: #{e.class}: #{e.message}")
    Sentry.capture_exception(e)
    @recurrence = RecurringTransaction.build_from_entry(@entry, **recurrence_attributes)
    render_step :confirm, status: :unprocessable_entity, error: RecurringTransaction::GENERIC_ERROR
  end

  private
    def set_entry
      @entry = Current.family.entries.find(params[:transaction_id])
    end

    def render_step(step, status: :ok, error: nil)
      render partial: "transactions/recurrences/recurrence",
             locals: { entry: @entry, step: step, recurrence: @recurrence, error: error, autofocus: step != :confirm },
             status: status
    end
end
