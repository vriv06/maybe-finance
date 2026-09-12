module Family::CyclePeriod
  extend ActiveSupport::Concern

  # Returns [start_date, end_date] for the "month" containing `date`.
  # With no cycle_end_day set, this is the plain calendar month. Otherwise it's
  # the custom pay-cycle window (e.g. cycle_end_day 27 => Aug 28 - Sep 27),
  # named after the month its end_date falls in.
  def cycle_range_containing(date)
    return [ date.beginning_of_month, date.end_of_month ] unless cycle_end_day.present?

    this_month_end_day = clamped_cycle_end_day(date)

    if date.day <= this_month_end_day
      end_date = date.beginning_of_month + (this_month_end_day - 1).days
      prev_month_start = date.prev_month.beginning_of_month
      start_date = prev_month_start + clamped_cycle_end_day(prev_month_start).days
    else
      next_month_start = date.next_month.beginning_of_month
      end_date = next_month_start + (clamped_cycle_end_day(next_month_start) - 1).days
      start_date = date.beginning_of_month + this_month_end_day.days
    end

    [ start_date, end_date ]
  end

  # Same as cycle_range_containing(Date.current), but capped at today (mirrors
  # Period::PERIODS["current_month"]'s start..today semantics, not start..end_of_month).
  def current_cycle_range
    start_date, end_date = cycle_range_containing(Date.current)
    [ start_date, [ end_date, Date.current ].min ]
  end

  private
    def clamped_cycle_end_day(date)
      [ cycle_end_day, date.end_of_month.day ].min
    end
end
