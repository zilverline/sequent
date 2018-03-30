# the command
class CreateAccount < Sequent::Core::Command
  attrs name: String
  validates_presence_of :name
end

# events
class AccountCreated < Sequent::Core::Event
end

class AccountNameChanged < Sequent::Core::Event
  attrs name: String
end

# aggregate root
class Account < Sequent::Core::AggregateRoot
  def initialize(command)
    super(command.aggregate_id)
    # apply will set the mandatory event attributes aggregate_id and sequence_number
    apply AccountCreated
    apply AccountNameChanged, name: command.name
  end

  on AccountCreated do
  end

  on AccountNameChanged do |event|
    @name = event.name
  end
end

# command handler
class AccountCommandHandler < Sequent::Core::BaseCommandHandler
  on CreateAccount do |command|
    repository.add_aggregate Account.new(command)
  end
end
