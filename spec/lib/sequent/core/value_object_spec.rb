# frozen_string_literal: true

require 'spec_helper'

class Country < Sequent::Core::ValueObject
  attrs name: String, code: String
end

class Address < Sequent::Core::ValueObject
  attrs street: String, country: Country, city: String, postal_code: String
end

class CountryList < Sequent::Core::ValueObject
  attrs countries: array(Country)
end

describe Sequent::Core::ValueObject do
  it 'includes TypeConversion' do
    expect(Sequent::Core::ValueObject.included_modules).to include(Sequent::Core::Helpers::TypeConversionSupport)
  end

  let(:country) { Country.new({code: 'NL', name: 'Nederland'}) }

  it 'is equal to another one when all attributes are equal' do
    other = Country.new({code: 'NL', name: 'Nederland'})
    expect(country).to eq(other)
    expect(country.hash).to eq other.hash
  end

  it 'is equal to another one when all attributes are equal and both are missing one' do
    nl_1 = Country.new({code: 'NL'})
    nl_2 = Country.new({code: 'NL'})
    expect(nl_1).to eq(nl_2)
    expect(nl_1.hash).to eq(nl_2.hash)
  end

  it 'is not equal to another when attributes differ' do
    other = Country.new({code: 'NL', name: 'Nederland2'})
    expect(country).to_not eq(other)
    expect(country.hash).to_not eq(other.hash)
  end

  it 'is not equal to another when a single attribute is missing' do
    other = Country.new({code: 'NL'})
    expect(country).to_not eq(other)
    expect(country.hash).to_not eq(other.hash)
  end

  it 'should equal when same type but one attribute is nil and the other is not set' do
    expect(Country.new(code: nil)).to eq(Country.new)
  end

  it 'can make a deep clone' do
    address = Address.new({street: 'Foo 12', country: country})
    other = address.copy
    expect(address).to_not equal(other)
    expect(address.country).to_not equal(other.country)
    expect(address).to eq(other)
    expect(address.hash).to eq(other.hash)
  end

  it 'can make a deep clone and change attributes' do
    address = Address.new({street: 'Foo 12', city: 'Amsterdam', postal_code: '1098TW', country: country})
    other = address.copy(street: 'Bar 12')
    expect(other.street).to eq 'Bar 12'
  end

  it 'is be possible to make params of a value object' do
    address = Address.new({street: 'Foo 12', country: country})
    expect(address.as_params).to eq HashWithIndifferentAccess.new(
      street: 'Foo 12',
      country: country.as_params,
      city: nil,
      postal_code: nil,
    )
  end

  it 'should be able to create value objects from params' do
    expect(Country.from_params({'code' => 'NL', 'name' => 'Nederland'})).to eq country

    expect(
      Address.from_params({'street' => 'Foo 12', 'country' => {'code' => 'NL', 'name' => 'Nederland'}}),
    ).to eq Address.new({street: 'Foo 12', country: country})
  end

  it 'handles arrays when creating value objects from params' do
    expect(
      CountryList.from_params('countries' => [{'code' => 'NL', 'name' => 'Nederland'}]),
    ).to eq CountryList.new({countries: [country]})
  end

  context '.attributes' do
    it 'ignores non attrs like @valid' do
      address = Address.new
      address.valid?
      expect(address.attributes).to_not have_key(:errors)
      expect(address.attributes).to_not have_key(:validation_context)
    end
  end
end
