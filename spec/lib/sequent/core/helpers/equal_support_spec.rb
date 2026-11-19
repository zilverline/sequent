# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::EqualSupport do
  class EqualSupportAddress < Sequent::Core::ValueObject
    attrs street: String
  end

  class EqualSupportValue < Sequent::Core::ValueObject
    attrs name: String, amount: Integer, at: Time, data: Hash, list: Array, address: EqualSupportAddress
  end

  class OtherEqualSupportValue < Sequent::Core::ValueObject
    attrs name: String
  end

  class ReaderEqualSupportValue < Sequent::Core::ValueObject
    attrs name: String

    def name
      @name&.upcase
    end
  end

  class DateTimeEqualSupportValue < Sequent::Core::ValueObject
    attrs at: DateTime
  end

  class UntypedEqualSupportValue < Sequent::Core::ValueObject
    attrs value: String

    def initialize(value)
      super()
      @value = value
    end
  end

  let(:now) { Time.new(2026, 1, 2, 3, 4, 5.123456789r, '+00:00') }

  def value(**attrs) = EqualSupportValue.new(name: 'a', amount: 1, **attrs)

  it 'does not call the readers' do
    expect(ReaderEqualSupportValue.new(name: 'a')).to eq ReaderEqualSupportValue.new(name: 'a')
    one = ReaderEqualSupportValue.new(name: 'a')
    two = ReaderEqualSupportValue.new(name: 'A')
    expect(one.name).to eq two.name
    expect(one).not_to eq two
  end

  it 'is equal to a value of the same class with the same values' do
    expect(value(data: {a: [1]})).to eq value(data: {a: [1]})
  end

  it 'is not equal to nil or another class' do
    expect(value).not_to eq nil
    expect(OtherEqualSupportValue.new(name: 'a')).not_to eq EqualSupportAddress.new(street: 'a')
    expect(Class.new(OtherEqualSupportValue).new(name: 'a')).not_to eq OtherEqualSupportValue.new(name: 'a')
  end

  it 'treats an integer and a float as different' do
    one = value
    two = value
    two.instance_variable_set(:@amount, 1.0)
    expect(one).not_to eq two
  end

  it 'treats nil as equal to nil only' do
    expect(value(name: nil)).to eq value(name: nil)
    expect(value(name: nil)).not_to eq value(name: '')
    expect(value(name: '')).not_to eq value(name: nil)
  end

  describe 'hashes' do
    it 'is not equal to a hash with indifferent access' do
      expect(value(data: {'a' => 1})).not_to eq value(data: {'a' => 1}.with_indifferent_access)
      expect(value(data: {'a' => 1}.with_indifferent_access)).not_to eq value(data: {'a' => 1})
    end

    it 'distinguishes symbol and string keys' do
      expect(value(data: {a: 1})).not_to eq value(data: {'a' => 1})
    end

    it 'ignores the order of the keys' do
      expect(value(data: {a: 1, b: 2})).to eq value(data: {b: 2, a: 1})
      expect(value(data: {a: 1, b: 2}).hash).to eq value(data: {b: 2, a: 1}).hash
    end

    it 'compares the values strictly' do
      expect(value(data: {a: {b: 1}})).not_to eq value(data: {a: {b: 1.0}})
      expect(value(data: {a: 1})).not_to eq value(data: {a: 1, b: 2})
      expect(value(data: {a: 1})).not_to eq value(data: {b: 1})
    end
  end

  describe 'arrays' do
    it 'compares the elements strictly' do
      expect(value(list: [1, [2]])).to eq value(list: [1, [2]])
      expect(value(list: [1, [2]])).not_to eq value(list: [1, [2.0]])
      expect(value(list: [1])).not_to eq value(list: [1, 2])
      expect(value(list: [1, 2])).not_to eq value(list: [2, 1])
    end
  end

  describe 'times' do
    it 'treats a Time and an ActiveSupport::TimeWithZone of the same instant as equal' do
      zoned = now.in_time_zone('Amsterdam')
      expect(value(at: now)).to eq value(at: zoned)
      expect(value(at: zoned)).to eq value(at: now)
      expect(value(at: now).hash).to eq value(at: zoned).hash
    end

    it 'has the same hash for a Time and a TimeWithZone nested in a hash or array' do
      zoned = now.in_time_zone('Amsterdam')
      expect(value(data: {a: [now]})).to eq value(data: {a: [zoned]})
      expect(value(data: {a: [now]}).hash).to eq value(data: {a: [zoned]}).hash
      expect(value(list: [now]).hash).to eq value(list: [zoned]).hash
    end

    it 'is not equal for a difference of a nanosecond' do
      expect(value(at: now)).not_to eq value(at: now + (1r / 1_000_000_000))
    end

    it 'does not equate a DateTime and a Time' do
      expect(DateTimeEqualSupportValue.new(at: now.to_datetime)).not_to eq value(at: now)
      one = value
      one.instance_variable_set(:@at, now.to_datetime)
      expect(one).not_to eq value(at: now)
      expect(value(at: now)).not_to eq one
    end

    it 'compares DateTimes at full precision' do
      one = DateTimeEqualSupportValue.new(at: DateTime.new(2026, 1, 2, 3, 4, Rational(5_123, 1000)))
      two = DateTimeEqualSupportValue.new(at: DateTime.new(2026, 1, 2, 3, 4, Rational(5_456, 1000)))
      expect(one).to eq DateTimeEqualSupportValue.new(at: DateTime.new(2026, 1, 2, 3, 4, Rational(5_123, 1000)))
      expect(one).not_to eq two
    end
  end

  it 'compares nested value objects with their own equality' do
    address = EqualSupportAddress.new(street: 'a')
    expect(value(address: address)).to eq value(address: EqualSupportAddress.new(street: 'a'))
    expect(value(address: address)).not_to eq value(address: EqualSupportAddress.new(street: 'b'))
    expect(value(address: address)).not_to eq value
  end

  it 'keeps the equality of a class that defines its own' do
    klass = Class.new do
      attr_reader :number

      def initialize(number) = @number = number

      def ==(other) = other.instance_of?(self.class) && number.abs == other.number.abs
    end
    one = UntypedEqualSupportValue.new(klass.new(1))
    expect(one).to eq UntypedEqualSupportValue.new(klass.new(-1))
    expect(one).not_to eq UntypedEqualSupportValue.new(klass.new(2))
  end

  it 'has a hash and eql? consistent with ==' do
    one = value(data: {a: 1}, list: [now])
    two = value(data: {a: 1}, list: [now.in_time_zone('Amsterdam')])
    expect(one.eql?(two)).to be true
    expect(one.hash).to eq two.hash
    expect([one, two, value(name: 'b')].uniq.size).to eq 2
    expect(Set.new([one, two]).size).to eq 1
  end
end
