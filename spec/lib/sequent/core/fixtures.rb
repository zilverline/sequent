class NameSet < Sequent::Event
  attrs first_name: String, last_name: String
end

class PersonAggregate < Sequent::Core::AggregateRoot
  attr_reader :first_name, :last_name

  self.autoset_attributes_for_events(NameSet)

  def initialize(id)
    super(id)
    apply TestEvent, field: "value"
  end

  def set_name(first_name, last_name)
    apply NameSet, first_name: first_name, last_name: last_name
  end

  def set_name_if_changed(first_name, last_name)
    apply_if_changed NameSet, first_name: first_name, last_name: last_name
  end

  private
  on TestEvent do
  end
end
