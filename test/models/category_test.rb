require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  def setup
    @family = families(:dylan_family)
  end

  test "replacing and destroying" do
    transactions = categories(:food_and_drink).transactions.to_a

    categories(:food_and_drink).replace_and_destroy!(categories(:income))

    assert_equal categories(:income), transactions.map { |t| t.reload.category }.uniq.first
  end

  test "replacing with nil should nullify the category" do
    transactions = categories(:food_and_drink).transactions.to_a

    categories(:food_and_drink).replace_and_destroy!(nil)

    assert_nil transactions.map { |t| t.reload.category }.uniq.first
  end

  test "subcategory can only be one level deep" do
    category = categories(:subcategory)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      category.subcategories.create!(name: "Invalid category", family: @family)
    end

    assert_equal "Validation failed: Parent can't have more than 2 levels of subcategories", error.message
  end

  test "replace_and_destroy! moves recurring plans to the replacement" do
    category = categories(:food_and_drink)
    replacement = families(:dylan_family).categories.create!(name: "Dining", color: "#e99537", lucide_icon: "utensils")
    plan = families(:dylan_family).recurring_transactions.create!(
      account: accounts(:credit_card), name: "Club", plan_type: "charge", amount: 10, currency: "USD",
      start_date: Date.current + 1.day, category: category
    )

    category.replace_and_destroy!(replacement)

    assert_equal replacement, plan.reload.category
  end
end
