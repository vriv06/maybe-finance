require "test_helper"

class RecurringTransaction::BudgetImpactTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    travel_to Date.new(2026, 10, 8)
    @family = families(:dylan_family)
    @family.budgets.destroy_all
    @card = accounts(:credit_card)
    @card.entries.delete_all
    @family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                            currency: "USD", budgeted_spending: 1500, expected_income: 4000)
    @family.recurring_transactions.create!(account: @card, name: "Rent", plan_type: "charge",
                                           amount: 1000, currency: "USD", start_date: Date.new(2026, 10, 20))
    # Category spend has its own tests below; the others look at commitments and the purchase only
    Budget.any_instance.stubs(:category_spend_for_projection).returns([])
  end

  test "projects the next three installments over the reference budget" do
    purchase = create_transaction(account: @card, amount: 3000, name: "iPad", date: Date.new(2026, 10, 8))
    impact = RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: 6).budget_impact

    assert_equal [ "October 2026", "November 2026", "December 2026" ], impact.months.map { |m| m.budget.name }
    assert_equal [ false, true, true ], impact.months.map(&:reference?) # October has its own budget
    assert_equal [ BigDecimal("1500") ] * 3, impact.months.map(&:total)
    assert_equal [ 100 ] * 3, impact.months.map(&:percent)
    assert_empty impact.over_months
    assert_equal 1800, impact.scale
  end

  test "flags the months a purchase puts over budget" do
    purchase = create_transaction(account: @card, amount: 1200, name: "TV", date: Date.new(2026, 10, 8))
    impact = RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: 2).budget_impact

    assert_equal 2, impact.payments_count
    assert_equal [ BigDecimal("100") ] * 2, impact.over_months.map(&:overage)
    assert_equal [ 107 ] * 2, impact.months.map(&:percent)
  end

  test "skips installments in months that already ended" do
    purchase = create_transaction(account: @card, amount: 600, name: "Chair", date: Date.new(2026, 7, 2))
    impact = RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: 6).budget_impact

    assert_equal "October 2026", impact.months.first.budget.name # Aug and Sep are over
  end

  test "nothing to show without any configured budget" do
    @family.budgets.destroy_all
    purchase = create_transaction(account: @card, amount: 600, name: "Chair", date: Date.new(2026, 10, 8))

    assert_not RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: 3).budget_impact.available?
  end

  test "the preview total equals the committed amount once the plan is saved" do
    purchase = create_transaction(account: @card, amount: 3000, name: "iPad", date: Date.new(2026, 10, 8))
    preview = RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: 3).budget_impact
    expected = preview.months.to_h { |month| [ month.budget.start_date, month.committed + month.purchase ] }

    RecurringTransaction.create_from_entry!(purchase, frequency: "monthly", total_payments: 3)

    expected.each do |start_date, total|
      assert_equal total, Budget.for_cycle(@family, start_date).committed_spending
    end
  end

  test "a monthly charge projects the month of the purchase and the next two" do
    purchase = create_transaction(account: @card, amount: 200, name: "Gym", date: Date.new(2026, 10, 8))
    impact = RecurringTransaction.build_from_entry(purchase, frequency: "monthly").budget_impact

    assert_equal [ "October 2026", "November 2026", "December 2026" ], impact.months.map { |m| m.budget.name }
    assert_equal [ BigDecimal("200") ] * 3, impact.months.map(&:purchase)
    assert_equal [ false, true, true ], impact.months.map(&:reference?)
    assert_not impact.counts_months?
  end

  test "a weekly plan shows the next three budget months with every payment in them" do
    purchase = create_transaction(account: @card, amount: 50, name: "Cleaner", date: Date.new(2026, 10, 8))
    impact = RecurringTransaction.build_from_entry(purchase, frequency: "weekly").budget_impact

    assert_equal [ BigDecimal("200"), BigDecimal("200"), BigDecimal("250") ], impact.months.map(&:purchase)
    assert_equal 13, impact.payments_count
    assert impact.counts_months?
  end

  test "category spend fills each month: actuals now, averages later, plan rows left out" do
    Budget.any_instance.unstub(:category_spend_for_projection)
    family = families(:empty)
    checking = Account.create!(family: family, accountable: Depository.new, name: "Checking", status: "active", currency: "USD", balance: 0)
    food = family.categories.create!(name: "Food", color: "#e99537", lucide_icon: "utensils", classification: "expense")
    family.budgets.create!(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 31),
                           currency: "USD", budgeted_spending: 600, expected_income: 0)
    create_transaction(account: checking, date: Date.new(2026, 9, 10), amount: 300, category: food)
    create_transaction(account: checking, date: Date.new(2026, 10, 2), amount: 100, category: food)
    gym = create_transaction(account: checking, date: Date.new(2026, 10, 3), amount: 50, category: food)
    RecurringTransaction.create_from_entry!(gym, frequency: "monthly")
    purchase = Entry.new(account: checking, name: "TV", date: Date.new(2026, 10, 8), amount: 1200, currency: "USD",
                         entryable: Transaction.new) # unsaved, as at capture

    impact = RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: 3).budget_impact

    assert_equal [ BigDecimal("50") ] * 3, impact.months.map(&:committed)
    assert_equal [ [ "Food", BigDecimal("100") ], [ "Food", BigDecimal("200") ], [ "Food", BigDecimal("200") ] ],
                 impact.months.map { |month| [ month.category_segments.first.label, month.category_segments.first.amount ] }
    assert_equal [ false, true, true ], impact.months.map(&:estimated?)
    assert_equal [ BigDecimal("550"), BigDecimal("650"), BigDecimal("650") ], impact.months.map(&:total)
    assert_equal [ "November 2026", "December 2026" ], impact.over_months.map { |month| month.budget.name }
  end

  test "the legend names the top four categories and folds the rest, Uncategorized included, into Other" do
    rows = [ [ "Rent", 500 ], [ "Food", 400 ], [ "Fun", 300 ], [ "Travel", 200 ], [ "Pets", 100 ] ].map do |name, amount|
      Budget::ProjectionCategory.new(category: Category.new(id: SecureRandom.uuid, name: name, color: "#e99537"),
                                     amount: BigDecimal(amount.to_s), estimated: true)
    end
    rows << Budget::ProjectionCategory.new(category: Category.new(name: "Uncategorized", color: Category::UNCATEGORIZED_COLOR),
                                           amount: BigDecimal("50"), estimated: true)
    Budget.any_instance.stubs(:category_spend_for_projection).returns(rows)
    purchase = create_transaction(account: @card, amount: 300, name: "Lamp", date: Date.new(2026, 10, 8))

    impact = RecurringTransaction.build_from_entry(purchase, frequency: "monthly", total_payments: 3).budget_impact
    other = impact.months.first.category_segments.last

    assert_equal [ "Rent", "Food", "Fun", "Travel", "Other" ], impact.category_legend.map(&:first)
    assert other.other
    assert_equal BigDecimal("150"), other.amount
    assert_equal BigDecimal("1550"), impact.months.first.category_spend
  end
end
