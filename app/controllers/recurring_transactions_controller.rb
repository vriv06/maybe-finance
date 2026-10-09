class RecurringTransactionsController < ApplicationController
  include RecurrenceParams

  before_action :set_recurring_transaction, only: %i[show update stop]

  def show
  end

  # Only name and category (and a charge's amount) can change; past payments never do
  def update
    return render :show, status: :unprocessable_entity unless @recurring_transaction.status == "active"

    if @recurring_transaction.update(recurring_transaction_params)
      flash.now[:notice] = "Changes saved."
      render_dialog
    else
      render :show, status: :unprocessable_entity
    end
  end

  def stop
    return render :show, status: :unprocessable_entity unless @recurring_transaction.status == "active"

    @recurring_transaction.cancel!
    flash.now[:notice] = "#{@recurring_transaction.name} stopped."
    render_dialog
  end

  # B2: server-side summary (and B1 budget impact) for the plan being typed; never saves anything
  def preview
    render partial: "recurring_transactions/preview", locals: {
      plan: build_preview_plan,
      show_impact: params[:impact] == "1",
      surface: params[:entry_id].present? ? :container : :inset
    }
  end

  private
    def set_recurring_transaction
      @recurring_transaction = Current.family.recurring_transactions.includes(:account, :category).find(params[:id])
    end

    def recurring_transaction_params
      permitted = params.require(:recurring_transaction).permit(:name, :category_id, :amount)
      permitted.delete(:amount) unless @recurring_transaction.charge?
      permitted[:category_id] = Current.family.categories.expenses.find(permitted[:category_id]).id if permitted[:category_id].present?
      permitted
    end

    def render_dialog
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("modal", template: "recurring_transactions/show"),
            *flash_notification_stream_items
          ]
        end
        format.html { redirect_to recurring_transaction_path(@recurring_transaction), notice: flash.now[:notice] }
      end
    end

    def build_preview_plan
      return nil unless recurrence_requested?

      entry = preview_entry
      entry && RecurringTransaction.build_from_entry(entry, **recurrence_attributes)
    end

    def preview_entry
      return Current.family.entries.find_by(id: params[:entry_id]) if params[:entry_id].present?

      account = Current.family.accounts.find_by(id: params.dig(:entry, :account_id))
      return nil unless account

      Entry.new(
        account: account,
        name: "Preview",
        date: parse_date(params.dig(:entry, :date)),
        amount: params.dig(:entry, :amount).presence,
        currency: params.dig(:entry, :currency).presence || account.currency,
        entryable: Transaction.new
      )
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
end
