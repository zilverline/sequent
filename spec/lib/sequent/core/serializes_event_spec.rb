require 'spec_helper'

describe Sequent::Core::SerializesEvent do

  class RecordMock
    include Sequent::Core::SerializesEvent
    attr_accessor :aggregate_id,
                  :sequence_number,
                  :event_type,
                  :created_at,
                  :event_json

  end

  class RecordValueObject < Sequent::Core::ValueObject
    attrs value: String
  end

  class RecordEvent < Sequent::Core::Event
    attrs value: RecordValueObject
  end

  let(:value_object) { RecordValueObject.new }
  let(:event) { RecordEvent.new(aggregate_id: "1",
                                sequence_number: 2,
                                value: value_object) }

  describe ".event" do
    it 'only serializes declared attrs' do
      # call valid to let AM generate @errors and @validation_context
      value_object.valid?
      record = RecordMock.new
      record.event = event
      payload = Oj.strict_load(record.event_json, {})
      expect(payload).to have_key("aggregate_id")
      expect(payload).to have_key("sequence_number")
      expect(payload).to have_key("value")
      expect(payload["value"]).to_not have_key("errors")
      expect(payload["value"]).to have_key("value")
    end
  end
end
