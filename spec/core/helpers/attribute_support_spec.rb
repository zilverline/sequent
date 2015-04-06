require 'spec_helper'

describe Sequent::Core::Helpers::AttributeSupport do
  context ".validation_errors" do
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

  end

  context "including and inheritance" do
    module TestModule
      include Sequent::Core::Helpers::AttributeSupport

      attrs some_included_attribute: String
    end

    class TestClassWithIncludedModule
      include Sequent::Core::Helpers::AttributeSupport, TestModule

      attrs some_attribute: String
    end

    it "supports including modules" do
      expect(TestClassWithIncludedModule.types).to eq({some_attribute: String, some_included_attribute: String})
    end

    it "should support subclasses" do
      expect(SubTestClass.types).to eq({sub_message: String, message: String})
    end
  end

  context "add default validations" do

    context Integer do
      class WithInteger < Sequent::Core::ValueObject
        attrs value: Integer
      end

      it "reports errors for not number" do
        obj = WithInteger.new(value: "A")
        expect(obj.valid?).to be_falsey
        expect(obj.validation_errors[:value]).to eq ["is not a number"]
      end

      it "reports errors for invalid integers" do
        obj = WithInteger.new(value: "1.0")
        expect(obj.valid?).to be_falsey
        expect(obj.validation_errors[:value]).to eq ["must be an integer"]
      end

      it "handles valid integers" do
        expect(WithInteger.new(value: 1)).to be_valid
      end

    end

    context String do
      class WithString < Sequent::Core::ValueObject
        attrs value: String
      end

      it "handles strings" do
        expect(WithString.new(value: "1")).to be_valid
      end
    end

    context Date do
      class WithDate < Sequent::Core::ValueObject
        attrs value: Date
      end

      it "handles nils" do
        obj = WithDate.new(value: nil)
        expect(obj.valid?).to be_truthy
      end

      it "handles Dates" do
        obj = WithDate.new(value: Date.today)
        expect(obj.valid?).to be_truthy
      end

      it "handles valid date strings" do
        obj = WithDate.new(value: "01-01-2015")
        expect(obj.valid?).to be_truthy
      end

      it "reports errors for invalid date" do
        obj = WithDate.new(value: "aa-bb-cccc")
        expect(obj.valid?).to be_falsey
      end
    end

    context DateTime do
      class WithDateTime < Sequent::Core::ValueObject
        attrs value: DateTime
      end

      it "handles nils" do
        obj = WithDateTime.new(value: nil)
        expect(obj.valid?).to be_truthy
      end

      it "handles DateTimes" do
        obj = WithDateTime.new(value: DateTime.current)
        expect(obj.valid?).to be_truthy
      end

      it "handles valid date strings" do
        obj = WithDateTime.new(value: "2015-04-06T19:43:07+02:00")
        expect(obj.valid?).to be_truthy
      end

      it "reports errors for invalid date" do
        obj = WithDateTime.new(value: "2015-04-dfgdsfg07+02:00")
        expect(obj.valid?).to be_falsey
      end

    end


  end
end
