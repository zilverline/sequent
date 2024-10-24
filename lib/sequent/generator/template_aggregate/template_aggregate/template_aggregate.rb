# frozen_string_literal: true

class TemplateAggregate < Sequent::AggregateRoot
  def initialize(command)
    super(command.aggregate_id)
    apply TemplateAggregateAdded
  end

  on TemplateAggregateAdded do
  end
end
