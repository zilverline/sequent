class TemplateAggregateCommandHandler < Sequent::BaseCommandHandler
  on AddTemplateAggregate do |command|
    repository.add_aggregate TemplateAggregate.new(command)
  end
end
