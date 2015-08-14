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

    context "arrays" do
      class TestClassWithRequiredString < Sequent::Core::ValueObject
        attrs message: String
        validates_presence_of :message
      end

      class TestClassWithArray < Sequent::Core::ValueObject
        attrs messages: array(TestClassWithRequiredString)
        validates_presence_of :messages
      end

      it "does not create errors for items in an empty array" do
        subject = TestClassWithArray.new(messages: [])
        expect(subject.valid?).to be_falsey
        expect(subject.validation_errors.size).to eq 1
        expect(subject.validation_errors[:messages]).to_not be_nil
        expect(subject.validation_errors[:"messages_0_message"]).to be_nil
      end

      it "creates an error item in array" do
        subject = TestClassWithArray.new(messages: [NestedTestClass.new])
        expect(subject.valid?).to be_falsey
        expect(subject.validation_errors.size).to eq 2
        expect(subject.validation_errors[:messages]).to_not be_nil
        expect(subject.validation_errors[:"messages_0_message"]).to_not be_nil
      end

      it "creates an error for each item in array" do
        subject = TestClassWithArray.new(messages: [NestedTestClass.new, NestedTestClass.new])
        expect(subject.valid?).to be_falsey
        errors = subject.validation_errors
        expect(errors[:messages]).to_not be_nil
        expect(errors[:"messages_0_message"]).to_not be_nil
        expect(errors[:"messages_1_message"]).to_not be_nil
        expect(errors.size).to eq 3
      end
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

    context Sequent::Core::Event do
      class AnEvent < Sequent::Core::Event
        attrs values: array(Integer)
      end

      it "adds no validations for events" do
        obj = AnEvent.new(aggregate_id: "1", sequence_number: 2, values: [1])
        expect(obj.respond_to?(:valid?)).to be_falsey
      end

    end

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

      it "handles nil value" do
        expect(WithInteger.new).to be_valid
      end

      it "handles blank" do
        expect(WithInteger.new(value: "")).to be_valid
        expect(WithInteger.new(value: " ")).to be_valid
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

      it "handles valid date formats" do
        obj = WithDate.new(value: "1-1-2015")
        expect(obj.valid?).to be_falsey
      end

      it "reports errors for invalid date" do
        obj = WithDate.new(value: "aa-bb-cccc")
        expect(obj.valid?).to be_falsey
      end

      it "handles blank" do
        obj = WithDate.new(value: "")
        expect(obj.valid?).to be_truthy
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

    context Sequent::Core::ValueObject do
      class NestedValueObject < Sequent::Core::ValueObject
        attrs value: Integer
      end

      class BaseValueObject < Sequent::Core::ValueObject
        attrs nested: NestedValueObject
      end

      class BaseValueObjectWithMulitpleNested < Sequent::Core::ValueObject
        attrs nested: NestedValueObject, another: NestedValueObject
      end

      it "handles nil" do
        obj = BaseValueObject.new(nested: nil)
        expect(obj.valid?).to be_truthy
      end

      it "reports an error when nested invalid" do
        obj = BaseValueObject.new(nested: NestedValueObject.new(value: "A"))
        expect(obj.valid?).to be_falsey
        expect(obj.validation_errors[:nested_value]).to_not be_nil
      end

      it "reports an error for all invalid nested" do
        obj = BaseValueObjectWithMulitpleNested.new(
          nested: NestedValueObject.new(value: "A"),
          another: NestedValueObject.new(value: "B")
        )
        expect(obj.valid?).to be_falsey
        expect(obj.validation_errors[:nested_value]).to_not be_nil
        expect(obj.validation_errors[:another_value]).to_not be_nil
      end

      it "handles valid input" do
        obj = BaseValueObject.new(nested: NestedValueObject.new(value: "1"))
        expect(obj.valid?).to be_truthy
      end
    end

    context Array do

      context "nils" do
        class ArrayWithNil < Sequent::Core::ValueObject
          attrs values: array(Integer)
        end

        it "handles nil" do
          obj = ArrayInteger.new(values: [nil])
          expect(obj.valid?).to be_falsey
        end
      end

      context Integer do

        class ArrayInteger < Sequent::Core::ValueObject
          attrs values: array(Integer)
        end

        it "handles nil" do
          obj = ArrayInteger.new(values: nil)
          expect(obj.valid?).to be_truthy
        end

        it "reports an error for invalid Integers in the array" do
          obj = ArrayInteger.new(values: ["a"])
          expect(obj.valid?).to be_falsey
          expect(obj.validation_errors[:values]).to eq ["is invalid"]
        end

        it "handles valid input" do
          obj = ArrayInteger.new(values: ["1", 2])
          expect(obj.valid?).to be_truthy
        end
      end

      context Date do
        class ArrayWithDate < Sequent::Core::ValueObject
          attrs values: array(Date)
        end

        it "handles nil" do
          obj = ArrayWithDate.new(values: nil)
          expect(obj.valid?).to be_truthy
        end

        it "reports an error for invalid Dates in the array" do
          obj = ArrayWithDate.new(values: ["aa-aa-aaaa"])
          expect(obj.valid?).to be_falsey
          expect(obj.validation_errors[:values]).to eq ["is invalid"]
        end

        it "handles valid input" do
          obj = ArrayWithDate.new(values: ["01-01-2015", Date.today])
          expect(obj.valid?).to be_truthy
        end

      end
      context DateTime do
        class ArrayWithDateTime < Sequent::Core::ValueObject
          attrs values: array(DateTime)
        end

        it "handles nil" do
          obj = ArrayWithDateTime.new(values: nil)
          expect(obj.valid?).to be_truthy
        end

        it "reports an error for invalid DateTimes in the array" do
          obj = ArrayWithDateTime.new(values: ["aa-aa-aaaa"])
          expect(obj.valid?).to be_falsey
          expect(obj.validation_errors[:values]).to eq ["is invalid"]
        end

        it "handles valid input" do
          obj = ArrayWithDateTime.new(values: ["2015-04-06T19:43:07+02:00", DateTime.now])
          expect(obj.valid?).to be_truthy
        end

      end

      context String do
        class ArrayWithString < Sequent::Core::ValueObject
          attrs values: array(String)
        end

        it "handles nil" do
          obj = ArrayWithString.new(values: nil)
          expect(obj.valid?).to be_truthy
        end

        it "handles valid input" do
          obj = ArrayWithString.new(values: ["ben", "kim"])
          expect(obj.valid?).to be_truthy
        end

      end
      context Symbol do
        class ArrayWithSymbol < Sequent::Core::ValueObject
          attrs values: array(Symbol)
        end

        it "handles nil" do
          obj = ArrayWithSymbol.new(values: nil)
          expect(obj.valid?).to be_truthy
        end

        it "handles valid input" do
          obj = ArrayWithSymbol.new(values: ["ben", :kim])
          expect(obj.valid?).to be_truthy
        end

      end
      context Boolean do
        class ArrayWithBoolean < Sequent::Core::ValueObject
          attrs values: array(Boolean)
        end

        it "handles nil" do
          obj = ArrayWithBoolean.new(values: nil)
          expect(obj.valid?).to be_truthy
        end

        it "reports an error for invalid Boolean in the array" do
          obj = ArrayWithDateTime.new(values: ["yes"])
          expect(obj.valid?).to be_falsey
          expect(obj.validation_errors[:values]).to eq ["is invalid"]
        end

        it "handles valid input" do
          obj = ArrayWithBoolean.new(values: ["true", "false", true, false])
          expect(obj.valid?).to be_truthy
        end

      end

      context Sequent::Core::ValueObject do
        class FooBar < Sequent::Core::ValueObject
          attrs value: Integer
        end

        class ArrayWithValueObject < Sequent::Core::ValueObject
          attrs values: array(FooBar)
        end

        it "handles nil" do
          obj = ArrayWithValueObject.new(values: nil)
          expect(obj.valid?).to be_truthy
        end

        it "reports an error for nil as value of the array" do
          obj = ArrayWithValueObject.new(values: [nil])
          expect(obj.valid?).to be_falsey
        end

        it "reports an error for invalid ValueObject in the array" do
          obj = ArrayWithValueObject.new(values: [FooBar.new(value: "a")])
          expect(obj.valid?).to be_falsey
          expect(obj.validation_errors[:values]).to eq ["is invalid"]
        end

        it "handles valid input" do
          obj = ArrayWithValueObject.new(values: [FooBar.new(value: 1), FooBar.new(value: "2")])
          expect(obj.valid?).to be_truthy
        end

        context "multiple assicatiations" do
          class MultipleAssociations < Sequent::Core::ValueObject
            attrs value: FooBar, values: array(FooBar)
          end

          it "handles nil" do
            obj = MultipleAssociations.new(value: nil, values: nil)
            expect(obj.valid?).to be_truthy
          end

          it "handles valid input" do
            obj = MultipleAssociations.new(value: FooBar.new(value: 2), values: [FooBar.new(value: 1)])
            expect(obj.valid?).to be_truthy
          end

        end
      end
    end
  end

  describe '#update' do
    class TestValue < Sequent::Core::ValueObject
      attrs value: Integer
    end

    it 'updates the object with changes' do
      expect(TestValue.new(value: 1).update(value: 2).value).to eq(2)
    end
  end
end
