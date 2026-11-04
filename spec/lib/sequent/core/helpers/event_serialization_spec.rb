# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::EventSerialization do
  class SerializationChanged < Sequent::Core::Event
    attrs name: String, count: Integer, at: Time, payload: Hash, tags: array(String)
  end

  class SerializationUnloadable < Sequent::Core::Event
    attrs anything: Object
  end

  class SerializationAggregate < Sequent::Core::AggregateRoot
    def change(**attributes) = apply(SerializationChanged, attributes)

    def change_unloadable = apply(SerializationUnloadable, anything: 1)

    on SerializationChanged do
    end

    on SerializationUnloadable do
    end
  end

  let(:aggregate_id) { Sequent.new_uuid }
  let(:aggregate) { SerializationAggregate.new(aggregate_id) }
  let(:time) { Time.utc(2026, 1, 2, 3, 4, 5, 123_456.789r) }

  it 'does not deserialize events without an error handler' do
    expect(described_class).not_to receive(:stored_event)

    aggregate.change(name: :symbol)

    expect(aggregate.uncommitted_events.sole.name).to eq :symbol
  end

  context 'with an error handler that reports the events that change when they are stored' do
    let(:errors) { [] }

    before { Sequent.configuration.event_serialization_error_handler = errors.method(:push) }

    it 'passes the error with the differences, and applies the event' do
      aggregate.change(name: :symbol, count: 4)

      applied = aggregate.uncommitted_events.sole
      expect(errors.sole).to have_attributes(
        event: applied,
        differences: [Sequent::Core::EventSerializationError::Difference.new(:name, :symbol, 'symbol')],
      )
    end

    it 'passes nothing for an event that does not change' do
      aggregate.change(name: 'name', count: 4, at: time, payload: {'key' => 'value'}, tags: ['tag'])

      expect(errors).to be_empty
    end
  end

  context 'when raising the errors' do
    before { Sequent.configuration.event_serialization_error_handler = Sequent::Core::EventSerializationError::RAISE }

    it 'fails applying an event that changes when it is stored, before the aggregate applies it' do
      expect { aggregate.change(name: :symbol, count: '4', payload: {key: 'value'}, tags: [:tag]) }
        .to raise_error(Sequent::Core::EventSerializationError) { |error|
          expect(error.message).to include(
            'name: :symbol is stored as "symbol"',
            'count: "4" is stored as 4',
            "payload: #{{key: 'value'}.inspect} is stored as #{{'key' => 'value'}.inspect}",
            'tags: [:tag] is stored as ["tag"]',
          )
          expect(error.message).not_to include('created_at')
        }
      expect(aggregate.uncommitted_events).to be_empty
    end

    it 'fails when the aggregate_id is loaded as another UUID text' do
      expect { SerializationAggregate.new(aggregate_id.upcase).change(name: 'name') }
        .to raise_error(Sequent::Core::EventSerializationError, /aggregate_id: "#{aggregate_id.upcase}"/)
    end

    it 'fails when an event can not be deserialized once it is stored' do
      expect { aggregate.change_unloadable }
        .to raise_error(Sequent::Core::EventSerializationError, /SerializationUnloadable can not be deserialized/)
    end

    it 'fails when a hash changes its class or a time in it becomes a string' do
      expect { aggregate.change(payload: {'key' => 'value'}.with_indifferent_access) }
        .to raise_error(Sequent::Core::EventSerializationError, /payload/)
      expect { aggregate.change(payload: {'at' => time}) }
        .to raise_error(Sequent::Core::EventSerializationError, /payload/)
    end

    it 'does not change the times of the event' do
      at = Time.new(2026, 1, 2, 3, 4, 5, '+01:00').freeze

      aggregate.change(name: 'name', at:)

      expect(aggregate.uncommitted_events.sole.at).to be(at)
      expect(at.utc_offset).to eq 3600
    end

    it 'accepts times, which are truncated to the time precision when the event is created' do
      expect { aggregate.change(name: 'name', count: 4, at: time, payload: {'key' => 'value'}, tags: ['tag']) }
        .not_to raise_error
    end
  end
end
