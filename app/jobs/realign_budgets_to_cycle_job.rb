class RealignBudgetsToCycleJob < ApplicationJob
  def perform(family)
    Budget.realign_to_cycle!(family)
  end
end
