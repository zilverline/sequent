# frozen_string_literal: true

class TemplateAggregateCommandHandler < Sequent::CommandHandler
  on AddTemplateAggregate do |command|
    repository.add_aggregate TemplateAggregate.new(command)
  end
end
