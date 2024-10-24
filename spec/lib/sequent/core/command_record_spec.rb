# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::CommandRecord do
  class TestCommand < Sequent::Core::Command
    attrs field: String
  end

  let(:command) { TestCommand.new(aggregate_id: Sequent.new_uuid, field: 'value') }

  before do
    # ActiveRecord is doing some timestamp trunctation (microseconds
    # to milliseconds) so set the timestamp without microseconds
    # here. The JSON timestamp format will not persist these
    # microseconds anyway.
    command.created_at = Time.parse('2024-02-09T09:09:09.009Z')
  end

  subject { described_class.new }

  describe '#command' do
    before do
      subject.command = command
    end

    it 'returns the original command' do
      expect(subject.command).to eq command
    end
  end

  it 'should store json in the database' do
    Sequent.configuration.event_store.commit_events(command, [])
    record = Sequent::Core::CommandRecord.find_by(aggregate_id: command.aggregate_id)
    expect(record.command).to eq(command)
  end
end
