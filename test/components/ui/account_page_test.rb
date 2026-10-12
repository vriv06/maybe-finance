require "test_helper"

class UI::AccountPageTest < ActiveSupport::TestCase
  test "credit cards get a Recurring payments tab after Activity" do
    page = UI::AccountPage.new(account: accounts(:credit_card))

    assert_equal [ :activity, :recurring ], page.tabs
    assert_equal :activity, page.active_tab
    assert_equal "Recurring payments", page.tab_label(:recurring)
    assert_equal "Activity", page.tab_label(:activity)
  end

  test "other accounts keep their tabs" do
    assert_equal [ :activity ], UI::AccountPage.new(account: accounts(:depository)).tabs
    assert_equal [ :activity, :holdings ], UI::AccountPage.new(account: accounts(:investment)).tabs
  end
end
