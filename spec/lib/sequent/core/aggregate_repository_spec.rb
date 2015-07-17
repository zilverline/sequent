require 'spec_helper'

describe Sequent::Core::AggregateRepository do

  class DummyAggregate < Sequent::Core::TenantAggregateRoot

    attr_reader :loaded_events
    attr_writer :uncommitted_events

    def load_from_history(stream, events)
      @event_stream = stream
      @loaded_events = events
    end
  end

  let(:event_store) { double }
  let(:repository) { Sequent::Core::AggregateRepository.new(event_store) }
  let(:aggregate) { DummyAggregate.new(:id, :org_id) }

  it "should track added aggregates by id" do
    repository.add_aggregate aggregate
    expect(repository.load_aggregate(aggregate.id, DummyAggregate)).to be(aggregate)
  end

  it "should load an aggregate from the event store" do
    allow(event_store).to receive(:load_events).with(:id).and_return([aggregate.event_stream, [:events]])

    loaded = repository.load_aggregate(:id, DummyAggregate)

    expect(loaded.event_stream).to eq(aggregate.event_stream)
    expect(loaded.loaded_events).to eq([:events])
  end

  it "should not require expected aggregate class" do
    allow(event_store).to receive(:load_events).with(:id).and_return([aggregate.event_stream, [:events]])
    loaded = repository.load_aggregate(:id)
    expect(loaded.class).to eq(DummyAggregate)
  end

  it "should load a subclass aggregate" do
    allow(event_store).to receive(:load_events).with(:id).and_return([aggregate.event_stream, [:events]])
    loaded = repository.load_aggregate(:id, Sequent::Core::TenantAggregateRoot)
    expect(loaded.class).to be < Sequent::Core::TenantAggregateRoot
  end

  it "should fail when the expected type does not match the stored type" do
    allow(event_store).to receive(:load_events).with(:id).and_return([aggregate.event_stream, [:events]])
    expect { repository.load_aggregate(:id, Integer) }.to raise_error TypeError
  end

  it "should commit and clear events from aggregates in the identity map" do
    repository.add_aggregate aggregate
    aggregate.uncommitted_events = [:event]
    allow(event_store).to receive(:commit_events).with(:command, [[aggregate.event_stream, [:event]]]).once

    repository.commit(:command)

    expect(aggregate.uncommitted_events).to be_empty
  end

  it "should return aggregates from the identity map after loading from the event store" do
    allow(event_store).to receive(:load_events).with(:id).and_return([aggregate.event_stream, [:events]]).once

    a = repository.load_aggregate(:id, DummyAggregate)
    b = repository.load_aggregate(:id, DummyAggregate)
    expect(a).to equal(b)
  end

  it "should check type when returning aggregate from identity map" do
    repository.add_aggregate aggregate
    expect { repository.load_aggregate(aggregate.id, String) }.to raise_error { |error|
                                                                      expect(error).to be_a TypeError
                                                                    }
  end

  it "should prevent different aggregates with the same id from being added" do
    another = DummyAggregate.new(:id, :org_id)

    repository.add_aggregate aggregate
    expect { repository.add_aggregate another }.to raise_error { |error|
                                                      expect(error).to be_a Sequent::Core::AggregateRepository::NonUniqueAggregateId
                                                    }
  end

  it "should indicate if a aggregate exists" do
    repository.add_aggregate aggregate
    expect(repository.ensure_exists(aggregate.id, DummyAggregate)).to be_truthy
  end

  it "should raise exception if a aggregate does not exists" do
    expect { repository.ensure_exists(:foo, InvoiceCreatedEvent) }.to raise_exception NameError
  end

  it 'contains an aggregate' do
    allow(event_store).to receive(:stream_exists?).with(aggregate.id).and_return(true)
    expect(repository.contains_aggregate?(aggregate.id)).to eq(true)
  end

  it 'does not contain an aggregate' do
    allow(event_store).to receive(:stream_exists?).with(aggregate.id).and_return(false)
    expect(repository.contains_aggregate?(aggregate.id)).to eq(false)
  end
end
