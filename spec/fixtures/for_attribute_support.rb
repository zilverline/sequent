# frozen_string_literal: true

class NestedTestClass
  include ActiveModel::Validations
  include Sequent::Core::Helpers::AttributeSupport
  attrs message: String
  validates_presence_of :message
end

class AttributeSupportTestClass
  include ActiveModel::Validations
  include Sequent::Core::Helpers::AttributeSupport
  attrs message: String, nested_test_class: NestedTestClass
  validates_presence_of :message
  validates_with Sequent::Core::Helpers::AssociationValidator, associations: :nested_test_class
end

class SubTestClass < NestedTestClass
  attrs sub_message: String
  validates_presence_of :sub_message
end

class SomeEvent < Sequent::Core::Event
  attrs message: String
end
