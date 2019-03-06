require 'spec_helper'

describe Sequent::Core::EventRecord do
  describe Sequent::Core::SerializesEvent do
    before do
      stub_const("ExampleEvent", Class.new(Sequent::Core::Event))
      stub_const("ExampleRecord", Class.new(Sequent::Core::EventRecord))

      ExampleEvent.class_eval do
        attrs name: String, age: Integer
      end
    end

    context "event" do
      it "initializes an event type from json" do
        record = ExampleRecord.new({
          event_type: ExampleEvent.name,
          event_json: {
            aggregate_id: 'example-id',
            sequence_number: 1,
            name: "example-name",
            age: 58,
            created_at: DateTime.new(2019, 1, 1)
          }.to_json
        })

        expect(record.event).to eq(ExampleEvent.new(
          aggregate_id: 'example-id',
          sequence_number: 1,
          name: 'example-name',
          age: 58,
          created_at: DateTime.new(2019, 1, 1)
        ))
      end
    end

    context "event=" do
      it "assigns attributes from an event" do
        aggregate_id = 'aggregate-id'
        sequence_number = 1
        created_at = DateTime.new(2019, 1, 1)

        event = ExampleEvent.new(
          aggregate_id: aggregate_id,
          sequence_number: sequence_number,
          created_at: created_at
        )

        record = ExampleRecord.new
        record.event = event

        expect(record.aggregate_id).to eq(aggregate_id)
        expect(record.sequence_number).to eq(sequence_number)
        expect(record.event_type).to eq('ExampleEvent')
        expect(record.created_at).to eq(created_at)
        expect(record.event_json).to eq(ExampleRecord.serialize_to_json(event))
      end

      it "conditionally assigns organization_id" do
        stub_const("EventWithOrganizationId", Class.new(Sequent::Core::Event))

        ExampleRecord.class_eval do
          attr_accessor :organization_id
        end

        record = ExampleRecord.new

        event = ExampleEvent.new(
          aggregate_id: 'aggregate-id',
          sequence_number: 1
        )

        record.event = event
        expect(record.organization_id).to be_nil

        EventWithOrganizationId.class_eval do
          attrs organization_id: String
        end

        event = EventWithOrganizationId.new(
          aggregate_id: 'aggregate-id',
          sequence_number: 1,
          organization_id: 'organization-id'
        )

        record.event = event
        expect(record.organization_id).to eq('organization-id')
      end

      it "invokes 'after_serialization' hook" do
        event_record_hooks = spy(:event_record_hooks)
        Sequent.configuration.event_record_hooks_class = event_record_hooks

        event = ExampleEvent.new(
          aggregate_id: 'aggregate-id',
          sequence_number: 1
        )

        record = ExampleRecord.new
        record.event = event
        expect(event_record_hooks).to have_received(:after_serialization).with(record, event)
      end
    end
  end
end
