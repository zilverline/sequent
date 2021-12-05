# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::AssociationValidator do
  let(:options) { {} }
  let(:subject) { Sequent::Core::Helpers::AssociationValidator.new(options) }

  it 'fails when providing no associations' do
    expect { subject }.to raise_error /Must provide ':associations' to validate/
  end

  it 'fails when provind an empty list of associations' do
    options[:associations] = []
    expect { subject }.to raise_error /Must provide ':associations' to validate/
  end

  context 'validating an array with simple types' do
    class ValueObjectWithSimpleTypeAssociations < Sequent::Core::ValueObject
      attrs numbers: array(Integer)
    end

    let(:options) { {associations: [:numbers]} }
    let(:values) { {} }
    let(:object) { ValueObjectWithSimpleTypeAssociations.new(values) }

    it 'can handle nil as arrays' do
      subject.validate(object)
      expect(object.errors).to be_empty
    end

    it 'can handle empty arrays' do
      values[:numbers] = []
      subject.validate(object)
      expect(object.errors).to be_empty
    end

    it 'reports an error for nil values in an array' do
      values[:numbers] = [nil]
      subject.validate(object)
      expect(object.errors).to_not be_empty
    end

    it 'reports an error for invalid value in the array' do
      values[:numbers] = [10, 'A', 9]
      subject.validate(object)
      expect(object.errors).to_not be_empty
    end

    it 'reports a non-array value' do
      values[:numbers] = 'string'
      subject.validate(object)
      expect(object.errors).to_not be_empty
    end
  end

  context 'validating an array with value objects' do
    class ValueObjectWithInteger < Sequent::Core::ValueObject
      attrs number: Integer
    end

    class ValueObjectWithValueObjectAssociations < Sequent::Core::ValueObject
      attrs numbers: array(ValueObjectWithInteger)
    end

    let(:options) { {associations: [:numbers]} }
    let(:values) { {} }
    let(:object) { ValueObjectWithValueObjectAssociations.new(values) }

    it 'can handle nil as arrays' do
      subject.validate(object)
      expect(object.errors).to be_empty
    end

    it 'can handle empty arrays' do
      values[:numbers] = []
      subject.validate(object)
      expect(object.errors).to be_empty
    end

    it 'reports an error for nil values in an array' do
      values[:numbers] = [nil]
      subject.validate(object)
      expect(object.errors).to_not be_empty
    end

    it 'reports an error for invalid value in the array' do
      values[:numbers] =
        [
          ValueObjectWithInteger.new(number: 'A'),
          ValueObjectWithInteger.new(number: 1),
          ValueObjectWithInteger.new(number: 'B'),
        ]
      subject.validate(object)
      expect(object.errors).to_not be_empty
      expect(object.validation_errors.size).to eq 3
      expect(object.validation_errors[:numbers]).to_not be_empty
      expect(object.validation_errors[:numbers_0_number]).to_not be_empty
      expect(object.validation_errors[:numbers_2_number]).to_not be_empty
    end
  end

  context 'inheritance' do
    let(:options) { {associations: [:numbers]} }

    class ValueObjectWithArray < Sequent::Core::ValueObject
      attrs numbers: array(Integer)

      validates :numbers, presence: true
    end

    SubclassWithArray = Class.new(ValueObjectWithArray)

    it 'can handle inherited array properties' do
      object = SubclassWithArray.new(numbers: (1..5).to_a)
      subject.validate(object)
      expect(object.errors).to be_empty
    end
  end
end
