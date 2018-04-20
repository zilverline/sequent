class Account < Sequent::Core::AggregateRoot; end

require_relative './account/commands'
require_relative './account/command_handler'
require_relative './account/events'
require_relative './account/projector'

class Account
  def initialize(command)
    super(command.aggregate_id)
    apply AccountAdded
    apply AccountNameChanged, name: command.name
  end

  on AccountAdded do
  end

  on AccountNameChanged do |event|
    @name = event.name
  end
end
