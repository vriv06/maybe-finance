module RecurringTransactionsHelper
  RecurringSummary = Data.define(:icon, :line1, :line2, :past_due, :announcement)

  # r.daily … r.annual (Repeat select), keyed by RecurringTransaction::FREQUENCIES
  FREQUENCY_LABELS = {
    "daily" => "Daily", "weekly" => "Weekly", "monthly" => "Monthly", "bimonthly" => "Every 2 months",
    "quarterly" => "Quarterly", "semiannual" => "Every 6 months", "annual" => "Annually"
  }.freeze

  # r2.units: "every {unit}"
  FREQUENCY_UNITS = {
    "daily" => "day", "weekly" => "week", "monthly" => "month", "bimonthly" => "2 months",
    "quarterly" => "3 months", "semiannual" => "6 months", "annual" => "year"
  }.freeze

  # r.charge_label
  CHARGE_LABELS = {
    "daily" => "Daily charge", "weekly" => "Weekly charge", "monthly" => "Monthly charge", "bimonthly" => "Charge every 2 months",
    "quarterly" => "Quarterly charge", "semiannual" => "Charge every 6 months", "annual" => "Annual charge"
  }.freeze

  # Repeat select options: None first, then each frequency
  def recurring_frequency_options
    [ [ "None", "" ], *FREQUENCY_LABELS.map { |value, label| [ label, value ] } ]
  end

  def recurring_every(plan)
    "every #{FREQUENCY_UNITS.fetch(plan.frequency)}"
  end

  def recurring_charge_label(plan)
    CHARGE_LABELS.fetch(plan.frequency)
  end

  # Installment plans: "installments" on a card (the purchase stays whole on it), "payments" elsewhere
  def recurring_payments_noun(plan, count = 2)
    noun = plan.credit_card? ? "installment" : "payment"
    count == 1 ? noun : noun.pluralize
  end

  # "Mar 27, 2027"; with short: true, "Oct 27" in the current year
  def recurring_date(date, short: false)
    return date.strftime("%b %-d") if short && date.year == Date.current.year

    date.strftime("%b %-d, %Y")
  end

  def recurring_money(amount, currency)
    Money.new(amount, currency).format
  end

  def recurring_icon(plan)
    plan.installments? && plan.credit_card? ? "credit-card" : "repeat"
  end

  # B2 summary: figures on line 1, dates on line 2 (copy b2.*); the announcement uses commas instead of "·"
  def recurring_summary(plan, as_of: plan.family.today)
    first_amount = recurring_money(plan.occurrence_amount(1), plan.currency)

    if plan.installments?
      line1 = "#{plan.total_payments} payments of #{first_amount}"
      last_amount = plan.occurrence_amount(plan.total_payments)
      last_date = recurring_date(plan.end_date)

      if last_amount == plan.occurrence_amount(1)
        line2 = "Last on #{last_date}"
        spoken = "#{line1}, last on #{last_date}"
      else
        last_money = recurring_money(last_amount, plan.currency)
        line2 = "Last one #{last_money} on #{last_date}"
        spoken = "#{line1}, last one #{last_money} on #{last_date}"
      end
    else
      line1 = "#{first_amount} #{recurring_every(plan)}"

      if plan.total_payments
        payments = pluralize(plan.total_payments, "payment")
        last_date = recurring_date(plan.end_date)
        line2 = safe_join([ payments, tag.span("·", aria: { hidden: true }), "last on #{last_date}" ], " ")
        spoken = "#{line1}, #{payments}, last on #{last_date}"
      else
        line2 = "No end date"
        spoken = "#{line1}, no end date"
      end
    end

    backfill = plan.backfill_count(as_of: as_of)
    past_due = backfill.positive? ? "#{backfill} already due. They'll be added with their original dates." : nil

    RecurringSummary.new(
      icon: recurring_icon(plan),
      line1: line1,
      line2: line2,
      past_due: past_due,
      announcement: [ spoken, past_due ].compact.join(". ")
    )
  end

  # c1.installment_line (card installments) / r.payment_line (other installments, charges with an end) / r.charge_label
  def recurring_occurrence_label(plan, number)
    if plan.installments? && plan.credit_card?
      "Installment #{number} of #{plan.total_payments}"
    elsif plan.total_payments
      "Payment #{number} of #{plan.total_payments}"
    else
      recurring_charge_label(plan)
    end
  end

  # C1 provenance line of a transaction linked to a plan
  def recurring_provenance_label(transaction)
    plan = transaction.recurring_transaction
    return "Paid in #{plan.total_payments} installments" if transaction.kind_in_database == "msi_purchase"

    recurring_occurrence_label(plan, transaction.installment_number)
  end

  # b3.status_* / r.status_payments under "Recurring payment" in the drawer
  def recurring_status_text(transaction)
    plan = transaction.recurring_transaction
    return "One time" unless plan
    return recurring_charge_label(plan) if plan.charge?

    number = transaction.installment_number || plan.last_handled_number
    label = plan.credit_card? ? "Installments" : "Payments"
    safe_join([ label, tag.span("·", aria: { hidden: true }), tag.span(",", class: "sr-only"), "#{number} of #{plan.total_payments}" ], " ")
  end

  # [icon, text] for a plan's state: Active / Stopped {date} / Paid off {date} / Ended {date}
  def recurring_plan_state(plan)
    case plan.status
    when "active" then [ nil, "Active" ]
    when "cancelled" then [ "circle-stop", "Stopped #{recurring_date(plan.ended_on)}" ]
    else [ "check", "#{plan.installments? ? "Paid off" : "Ended"} #{recurring_date(plan.ended_on)}" ]
    end
  end

  # c2.upcoming_group
  def recurring_group_label(date, today: Current.family.today)
    return "Today" if date == today
    return "Tomorrow" if date == today + 1.day

    recurring_date(date, short: true)
  end

  # bi.title_over / bi.title_over_multi (nil when no month goes over)
  def budget_impact_title(impact)
    over = impact.over_months
    return nil if over.empty?

    first = over.first
    if over.size > 1
      "This puts #{over.size} budgets over. The first is #{first.budget.name}."
    else
      "This puts #{first.budget.name} #{recurring_money(first.overage, first.budget.currency)} over budget"
    end
  end

  # Accounts whose new transactions can be split into installments (manual, active credit cards)
  def recurring_credit_account_ids
    Current.family.accounts.manual.active.where(accountable_type: "CreditCard").pluck(:id)
  end

  # Which "Recurring payment" block the drawer's Settings shows (interaction §3.1 + canvas D14)
  def recurrence_block_state(entry)
    transaction = entry.transaction
    return :linked if transaction.recurring_transaction
    return nil if entry.amount.negative? || transaction.transfer? || transaction.transfer.present?
    return nil unless entry.account.manual? && entry.account.active?
    return nil if entry.currency != entry.account.family.currency
    return :one_time if transaction.one_time?

    RecurringTransaction.ineligibility_reason(entry).nil? ? :editable : nil
  end

  # c3.subtitle_installments / c3.subtitle_charge, joined by an aria-hidden "·" in the view
  def recurring_plan_subtitle_parts(plan)
    state_icon, state_text = recurring_plan_state(plan)
    state = state_icon ? safe_join([ icon(state_icon, size: "xs", color: "current"), state_text ]) : state_text

    if plan.installments?
      [ "#{plan.total_payments} payments of #{recurring_money(plan.occurrence_amount(1), plan.currency)}", recurring_every(plan), state ]
    else
      [ "#{recurring_money(plan.amount, plan.currency)} #{recurring_every(plan)}", state ]
    end
  end
end
