require 'spec_helper'

describe Sequent::Core::Helpers::ParamSupport do
  let(:ben) { Person.new(name: "Ben Vonk") }
  it "can translate an object from and into params" do
    expect(Person.from_params(ben.as_params)).to eq(ben)
  end

  it "can translate nested objects from and into params" do
    house = House.new(person: ben)
    expect(House.from_params(house.as_params)).to eq(house)
  end

  context DateTime do
    class ParamWithDateTime < Sequent::Core::ValueObject
      attrs value: DateTime
    end

    it "handles datetime" do
      obj = ParamWithDateTime.new(value: DateTime.now.iso8601)
      expect(ParamWithDateTime.from_params(obj.as_params)).to eq(obj)
    end
  end


end

class Person < Sequent::Core::ValueObject
  attrs name: String
end

class House < Sequent::Core::ValueObject
  attrs owner: Person
end
