require "test_helper"

class SegmentedBarTest < ActionView::TestCase
  test "renders rounded segments followed by the inset remainder" do
    render partial: "shared/segmented_bar", locals: { segments: [ [ "bg-pink-500", 20 ], [ "bg-inverse", 30 ] ] }

    assert_select "div.flex.h-1\\.5.gap-1[aria-hidden=true]" do
      assert_select "> div.rounded-md.h-1\\.5", 3
      assert_select "> div.bg-pink-500[style='width: 20.0%']"
      assert_select "> div.bg-inverse[style='width: 30.0%']"
      assert_select "> div.bg-surface-inset[style='width: 50.0%']"
    end
  end

  test "omits empty segments and the remainder when the bar is full" do
    render partial: "shared/segmented_bar", locals: { segments: [ [ "bg-pink-500", 0 ], [ "bg-destructive", 100 ] ] }

    assert_select "div.rounded-md", 1
    assert_select "div.bg-destructive"
  end
end
