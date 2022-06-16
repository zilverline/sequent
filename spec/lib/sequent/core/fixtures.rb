# frozen_string_literal: true

module Statusable
  def self.included(base)
    base.attrs status: String
  end
end

class NameSet < Sequent::Event
  attrs first_name: String, last_name: String
end

class AgeSet < Sequent::Event
  include Statusable

  attrs age: Integer
end

class PersonAggregate < Sequent::Core::AggregateRoot
  attr_reader :first_name,
              :last_name,
              :age,
              :status

  autoset_attributes_for_events NameSet,
                                is_a(Statusable)

  def initialize(id)
    super(id)
    apply TestEvent, field: 'value'
  end

  def set_name(first_name, last_name)
    apply NameSet, first_name: first_name, last_name: last_name
  end

  def set_age(age)
    apply AgeSet, age: age, status: age >= 18 ? :mature : :immature
  end

  def set_name_with_unknown_event_attribute
    apply NameSet, does_not_exist: 'test'
  end

  def set_name_if_changed(first_name, last_name)
    apply_if_changed NameSet, first_name: first_name, last_name: last_name
  end

  on TestEvent do
  end
end
