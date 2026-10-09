class RecurringTransactionsController < ApplicationController
  include RecurrenceParams

  # B2: server-side summary (and B1 budget impact) for the plan being typed; never saves anything
  def preview
    render partial: "recurring_transactions/preview", locals: {
      plan: build_preview_plan,
      show_impact: params[:impact] == "1",
      surface: params[:entry_id].present? ? :container : :inset
    }
  end

  private
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
