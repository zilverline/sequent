require 'spec_helper'

describe Sequent::Core::SerializesCommand do

  class RecordMock
    include Sequent::Core::SerializesCommand
    attr_accessor :aggregate_id,
                  :created_at,
                  :user_id,
                  :command_type,
                  :command_json,
                  :event_aggregate_id,
                  :event_sequence_number

  end

  class RecordValueObject < Sequent::Core::ValueObject
    attrs value: String
  end

  class RecordCommand < Sequent::Core::Command
    attrs value: RecordValueObject
  end

  let(:value_object) { RecordValueObject.new }
  let(:command) { RecordCommand.new(aggregate_id: "1",
                                    user_id: "ben en kim",
                                    value: value_object) }

  describe ".command" do
    it 'only serializes declared attrs' do
      # call valid to let AM generate @errors and @validation_context
      command.valid?
      record = RecordMock.new
      record.command = command
      payload = Sequent::Core::Oj.strict_load(record.command_json)
      expect(payload).to have_key("aggregate_id")
      expect(payload).to have_key("value")
      expect(payload["value"]).to_not have_key("errors")
      expect(payload["value"]).to have_key("value")
    end
  end
end
