# The shape of data expected by `confirm_dialog_controller.js` to override the
# default browser confirm API via Turbo.
class CustomConfirm
  class << self
    def for_resource_deletion(resource_name, high_severity: false)
      new(
        destructive: true,
        high_severity: high_severity,
        title: "Delete #{resource_name.titleize}?",
        body: "Are you sure you want to delete #{resource_name.downcase}? This is not reversible.",
        btn_text: "Delete #{resource_name.titleize}"
      )
    end

    def for_plan_stop(plan)
      body = if plan.installments?
        left = plan.remaining_payments
        "The #{left} #{"installment".pluralize(left)} left (#{money(plan.remaining_balance, plan.currency)}) " \
          "won't count in future budgets. The full purchase stays on your card balance."
      else
        added = plan.last_handled_number
        "No new payments will be added. The #{added} already added #{added == 1 ? "stays" : "stay"}."
      end

      new(title: "Stop #{plan.name}?", body: body, btn_text: "Stop payments", destructive: true, cancel_text: "Keep it")
    end

    def for_plan_edit(plan)
      added = plan.last_handled_number

      new(
        title: "Save changes to future payments?",
        body: "The #{added} #{"payment".pluralize(added)} already added won't change.",
        btn_text: "Save changes",
        cancel_text: "Keep editing"
      )
    end

    def for_msi_purchase_deletion(entry)
      plan = entry.transaction.recurring_transaction
      added = plan.transactions.where(kind: "installment").count

      new(
        title: "Delete this purchase and its installments?",
        body: "All #{plan.total_payments} installments will be deleted, including the #{added} already added. " \
              "Your card balance and past budgets will change. This can't be undone.",
        btn_text: "Delete",
        destructive: true,
        high_severity: true,
        cancel_text: "Keep it"
      )
    end

    def for_occurrence_deletion(entry)
      noun = entry.transaction.installment? ? "installment" : "payment"
      month = Budget.for_cycle(entry.account.family, entry.date).name

      new(
        title: "Delete this #{noun}?",
        body: "It won't be added again. Your #{month} budget will change.",
        btn_text: "Delete #{noun}",
        destructive: true,
        cancel_text: "Keep it"
      )
    end

    private
      def money(amount, currency)
        Money.new(amount, currency).format
      end
  end

  def initialize(title: default_title, body: default_body, btn_text: default_btn_text, destructive: false, high_severity: false, cancel_text: nil)
    @title = title
    @body = body
    @btn_text = btn_text
    @btn_variant = derive_btn_variant(destructive, high_severity)
    @cancel_text = cancel_text
  end

  def to_data_attribute
    {
      title: title,
      body: body,
      confirmText: btn_text,
      variant: btn_variant,
      cancelText: cancel_text
    }.compact
  end

  private
    attr_reader :title, :body, :btn_text, :btn_variant, :cancel_text

    def derive_btn_variant(destructive, high_severity)
      return "primary" unless destructive
      high_severity ? "destructive" : "outline-destructive"
    end

    def default_title
      "Are you sure?"
    end

    def default_body
      "This is not reversible."
    end

    def default_btn_text
      "Confirm"
    end
end
