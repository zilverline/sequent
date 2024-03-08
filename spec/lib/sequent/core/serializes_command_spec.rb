# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../fixtures/for_attribute_support'

describe Sequent::Core::SerializesCommand do
  class RecordMock
    include Sequent::Core::SerializesCommand
    attr_accessor :aggregate_id,
                  :created_at,
                  :user_id,
                  :command_type,
                  :command_json,
                  :event_aggregate_id,
                  :event_sequence_number,
                  :organization_id

    def serialize_json?
      true
    end
  end

  class RecordCommand < Sequent::Core::Command
    attrs value: RecordValueObject, organization_id: String
  end

  let(:value_object) { RecordValueObject.new }
  let(:command) do
    RecordCommand.new(
      aggregate_id: '1',
      user_id: 'ben en kim',
      value: value_object,
    )
  end

  describe '.command' do
    it 'only serializes declared attrs' do
      # call valid to let AM generate @errors and @validation_context
      command.valid?
      record = RecordMock.new
      record.command = command
      payload = Sequent::Core::Oj.strict_load(record.command_json)
      expect(payload).to have_key('aggregate_id')
      expect(payload).to have_key('value')
      expect(payload['value']).to_not have_key('errors')
      expect(payload['value']).to have_key('value')
    end

    describe 'optional fields' do
      class MyRecord
        include Sequent::Core::SerializesCommand
        attr_accessor :aggregate_id,
                      :created_at,
                      :user_id,
                      :command_type,
                      :command_json

        def initialize(aggregate_id, created_at, user_id, command_type, command_json)
          @aggregate_id = aggregate_id
          @created_at = created_at
          @user_id = user_id
          @command_type = command_type
          @command_json = command_json
        end

        def serialize_json?
          true
        end
      end

      let(:record) do
        MyRecord.new(
          Sequent.new_uuid,
          DateTime.now,
          Sequent.new_uuid,
          RecordCommand.name,
          {},
        )
      end

      it 'should not fail' do
        record.command = command
      end
    end
  end
end
