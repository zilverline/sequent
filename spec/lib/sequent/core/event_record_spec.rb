# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::EventRecord do
  let(:aggregate_id) { Sequent.new_uuid }

  class EventRecordWithOrganizationId < Sequent::Core::EventRecord
    attr_accessor :organization_id
  end

  before do
    stub_const('ExampleEvent', Class.new(Sequent::Core::Event))

    ExampleEvent.class_eval do
      attrs name: String, age: Integer
    end
  end

  describe Sequent::Core::SerializesEvent do
    context 'event=' do
      it 'assigns attributes from an event' do
        sequence_number = 1
        created_at = DateTime.new(2019, 1, 1)

        event = ExampleEvent.new(
          aggregate_id: aggregate_id,
          sequence_number: sequence_number,
          created_at: created_at,
        )

        record = Sequent::Core::EventRecord.new
        record.event = event

        expect(record.aggregate_id).to eq(aggregate_id)
        expect(record.sequence_number).to eq(sequence_number)
        expect(record.event_type).to eq('ExampleEvent')
        expect(record.created_at).to eq(created_at)
        expect(record.event).to eq(event)
      end

      it "invokes 'after_serialization' hook" do
        event_record_hooks = spy(:event_record_hooks)
        Sequent.configuration.event_record_hooks_class = event_record_hooks

        event = ExampleEvent.new(
          aggregate_id: 'aggregate-id',
          sequence_number: 1,
        )

        record = Sequent::Core::EventRecord.new
        record.event = event
        expect(event_record_hooks).to have_received(:after_serialization).with(record, event)
      end
    end
  end

  it 'persists events to the database' do
    event = ExampleEvent.new(
      aggregate_id: aggregate_id,
      sequence_number: 1,
      created_at: Time.parse('2024-02-29T09:09.009Z'),
    )

    Sequent.configuration.event_store.commit_events(
      Sequent::Core::Command.new(aggregate_id: aggregate_id),
      [
        [
          Sequent::Core::EventStream.new(
            aggregate_type: 'ExampleStream',
            aggregate_id: aggregate_id,
          ),
          [event],
        ],
      ],
    )
    record = Sequent::Core::EventRecord.find_by(aggregate_id: aggregate_id, sequence_number: 1)
    expect(record.event).to eq(event)
  end
end
