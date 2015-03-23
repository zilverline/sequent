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

end

class Person < Sequent::Core::ValueObject
  attrs name: String
end

class House < Sequent::Core::ValueObject
  attrs owner: Person
end
