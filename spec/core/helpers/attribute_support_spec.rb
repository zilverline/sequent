require 'spec_helper'

describe Sequent::Core::Helpers::AttributeSupport do

  class NestedTestClass
    include Sequent::Core::Helpers::AttributeSupport, ActiveModel::Validations
    attrs message: String
    validates_presence_of :message
  end

  class AttributeSupportTestClass
    include Sequent::Core::Helpers::AttributeSupport, ActiveModel::Validations
    attrs message: String, nested_test_class: NestedTestClass
    validates_presence_of :message
    validates_with Sequent::Core::Helpers::AssociationValidator, associations: :nested_test_class
  end

  class SubTestClass < NestedTestClass
    attrs sub_message: String
    validates_presence_of :sub_message
  end

  module TestModule
    include Sequent::Core::Helpers::AttributeSupport

    attrs some_included_attribute: String
  end

  class TestClassWithIncludedModule
    include Sequent::Core::Helpers::AttributeSupport, TestModule

    attrs some_attribute: String
  end

  class WithBoolean < Sequent::Core::ValueObject
    include ActiveModel::Validations::Callbacks
    include Sequent::Core::Helpers::BooleanSupport

    attrs foo: Boolean

    validates :foo, inclusion: {in: [true, false]}, allow_nil: true
  end

  it "returns validation errors as hash" do
    subject = NestedTestClass.new
    expect(subject.valid?).to be_falsey
    expect(subject.validation_errors).to have(1).items
    expect(subject.validation_errors[:message]).to_not be_nil
  end
  
  it "returns all validations of nested classes in same hash" do
    subject = AttributeSupportTestClass.new
    subject.nested_test_class = NestedTestClass.new
    expect(subject.valid?).to be_falsey
    expect(subject.validation_errors).to have(3).items
    expect(subject.validation_errors[:message]).to_not be_nil
    expect(subject.validation_errors[:nested_test_class]).to_not be_nil
    expect(subject.validation_errors[:nested_test_class_message]).to_not be_nil
  end

  it "returns all validation errors including from superclass" do
    subject = SubTestClass.new
    expect(subject.valid?).to be_falsey
    expect(subject.validation_errors).to have(2).items
    expect(subject.validation_errors[:message]).to_not be_nil
    expect(subject.validation_errors[:sub_message]).to_not be_nil
  end

  it "does not fail when it does not have errors" do
    subject = NestedTestClass.new
    subject.message = "foo"
    expect(subject.valid?).to be_truthy
    expect(subject.validation_errors).to be_empty
  end

  it "supports including modules" do
    expect(TestClassWithIncludedModule.types).to eq({some_attribute: String, some_included_attribute: String})
  end

  it "should support subclasses" do
    expect(SubTestClass.types).to eq({sub_message: String, message: String})
  end

  it "transforms string to booleans if possible" do
    expect(WithBoolean.new.valid?).to be_truthy
    expect(WithBoolean.new(foo: true).valid?).to be_truthy
    expect(WithBoolean.new(foo: false).valid?).to be_truthy
    expect(WithBoolean.new(foo: "").valid?).to be_falsey
    expect(WithBoolean.new(foo: "foobar").valid?).to be_falsey
    expect(WithBoolean.new(foo: nil).valid?).to be_truthy
    expect(WithBoolean.new(foo: "true").valid?).to be_truthy
  end

end
