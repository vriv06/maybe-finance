require "test_helper"

class FamilyTest < ActiveSupport::TestCase
  include SyncableInterfaceTest

  def setup
    @syncable = families(:dylan_family)
    @family = families(:dylan_family)
  end

  test "cycle_range_containing defaults to calendar month when cycle_end_day is nil" do
    date = Date.new(2026, 9, 15)

    assert_equal [ Date.new(2026, 9, 1), Date.new(2026, 9, 30) ], @family.cycle_range_containing(date)
  end

  test "cycle_range_containing resolves the window ending in the same month when day is on or before the cycle end day" do
    @family.update!(cycle_end_day: 27)

    assert_equal [ Date.new(2026, 8, 28), Date.new(2026, 9, 27) ], @family.cycle_range_containing(Date.new(2026, 9, 15))
    assert_equal [ Date.new(2026, 8, 28), Date.new(2026, 9, 27) ], @family.cycle_range_containing(Date.new(2026, 9, 1))
    assert_equal [ Date.new(2026, 8, 28), Date.new(2026, 9, 27) ], @family.cycle_range_containing(Date.new(2026, 9, 27))
  end

  test "cycle_range_containing rolls into next month's window when day is after the cycle end day" do
    @family.update!(cycle_end_day: 27)

    assert_equal [ Date.new(2026, 9, 28), Date.new(2026, 10, 27) ], @family.cycle_range_containing(Date.new(2026, 9, 28))
  end

  test "cycle_range_containing clamps cycle_end_day to short months" do
    @family.update!(cycle_end_day: 30)

    # February 2026 has 28 days, so its window ends the 28th (clamped from 30) and starts
    # Jan 31 (the day after January's own clamped end day, 30 -- Jan has 31 days so no clamp there)
    assert_equal [ Date.new(2026, 1, 31), Date.new(2026, 2, 28) ], @family.cycle_range_containing(Date.new(2026, 2, 15))
  end

  test "current_cycle_range caps the end date at today" do
    @family.update!(cycle_end_day: 27)

    _, end_date = @family.current_cycle_range
    assert_equal Date.current, end_date
  end
end
