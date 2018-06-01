class TemplateAggregate < Sequent::AggregateRoot
  def initialize(command)
    super(command.aggregate_id)
    apply TemplateAggregateAdded
    apply TemplateAggregateNameChanged, name: command.name
  end

  on TemplateAggregateAdded do
  end

  on TemplateAggregateNameChanged do |event|
    @name = event.name
  end
end
