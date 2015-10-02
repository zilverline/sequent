require 'spec_helper'

describe Sequent::Core::Event do

  class Person < Sequent::Core::ValueObject
    attrs name: String
  end

  class TestTenantEvent < Sequent::Core::TenantEvent
    attrs name: String, date_time: DateTime, owner: Person
  end

  class EventWithDate < Sequent::Core::TenantEvent
    attrs date_of_birth: Date
  end

  class FooType;
  end
  class EventWithUnknownAttributeType < Sequent::Core::TenantEvent
    attrs name: FooType
  end

  class EventWithSymbol < Sequent::Core::TenantEvent
    attrs status: Symbol
  end

  class EventWithFloat < Sequent::Core::Event
    attrs latitude: Float, longitude: Float
  end

  it "does not include aggregate_id, sequence_number and organization_id in payload" do
    expect(
      TestTenantEvent.new(
        {aggregate_id: 123, sequence_number: 7, organization_id: "bar", name: "foo"}
      ).payload).to eq({ name: "foo", date_time: nil, owner: nil })
  end

  it "deserializes DateTime using iso8601" do
    now = DateTime.now
    val = now.iso8601
    event = TestTenantEvent.deserialize_from_json(
      "aggregate_id" => "bla", "sequence_number" => 1, "created_at" => val
    )
    expect(event.created_at.iso8601).to eq val
  end

  it "events are equal when deserialized from same attributes" do
    event1 = TestTenantEvent.new(aggregate_id: "foo", organization_id: "bar", sequence_number: 1)
    created_at = event1.created_at.iso8601
    event2 = TestTenantEvent.deserialize_from_json("aggregate_id" => "foo", "organization_id" => "bar", "sequence_number" => 1, "created_at" => created_at)
    expect(event1).to eq event2
  end

  it "is converted from and to json and ignore validation stuff from activemodel" do
    person = Person.new({name: "foo"})
    person.valid?
    event = TestTenantEvent.new(
      aggregate_id: 123, organization_id: "bar", sequence_number: 7, owner: person
    )
    json = Sequent::Core::Oj.dump(event)
    other = TestTenantEvent.deserialize_from_json(Sequent::Core::Oj.strict_load(json))
    expect(other).to eq event
  end

  it "is be able to converted from and to json with a date" do
    today = Date.today
    event = EventWithDate.new(
      aggregate_id: 123, organization_id: "bar", sequence_number: 7, date_of_birth: today
    )
    other = EventWithDate.deserialize_from_json(Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(event)))
    expect(other).to eq event
  end

  it "fails when converting to and from Json when type is not supported" do
    event = EventWithUnknownAttributeType.new(
      aggregate_id: 123, organization_id: "bar", sequence_number: 7, name: FooType.new
    )
    expect { EventWithUnknownAttributeType.deserialize_from_json(Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(event))) }.to raise_exception(NoMethodError)
  end

  it "converts symbols" do
    event = EventWithSymbol.new(aggregate_id: 123, sequence_number: 7, organization_id: "bar", status: :foo)
    other = EventWithSymbol.deserialize_from_json(Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(event)))
    expect(event).to eq other
  end

  it "converts floats" do
    event = EventWithFloat.new(aggregate_id: 'X', sequence_number: 1, latitude: 52.370146, longitude: 4.953977)
    deserialized = EventWithFloat.deserialize_from_json(Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(event)))
    expect(event).to eq(deserialized)
  end

  it "deserializes nil symbols" do
    event = EventWithSymbol.new(aggregate_id: 123, organization_id: "bar", sequence_number: 7)
    other = EventWithSymbol.deserialize_from_json(Sequent::Core::Oj.strict_load(Sequent::Core::Oj.dump(event)))
    expect(event).to eq other
  end

  context ".attributes" do

    it "ignores non attrs like @valid" do
      person = Person.new(name: "foo")
      person.valid?
      event = TestTenantEvent.new(aggregate_id: "1", sequence_number: 2, organization_id: "3", owner: person)
      expect(event.attributes[:owner]).to_not have_key(:errors)
      expect(event.attributes[:owner]).to_not have_key(:validation_context)
    end

  end

end
