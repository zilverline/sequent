class Account < AggregateRoot
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
