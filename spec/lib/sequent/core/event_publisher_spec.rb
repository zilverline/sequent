# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::EventPublisher do
  class OtherAggregateTriggered < Sequent::Core::Event
    attrs other_aggregate_id: String
  end
  class EventAdded < Sequent::Core::Event; end
  class TriggerTestCase < Sequent::Core::Command; end
  class TriggerOtherAggregate < Sequent::Core::Command; end
  class TestRecord; end

  class TestAggregate < Sequent::Core::AggregateRoot
    def trigger_other_aggregate(aggregate_id)
      apply OtherAggregateTriggered, other_aggregate_id: aggregate_id
    end

    def add_event
      apply EventAdded
    end
  end

  class TestCommandHandler < Sequent::Core::BaseCommandHandler
    on TriggerTestCase do |_command|
      agg1 = TestAggregate.new(Sequent.new_uuid)
      agg2 = TestAggregate.new(Sequent.new_uuid)

      agg1.trigger_other_aggregate(agg2.id)
      agg2.add_event

      repository.add_aggregate(agg1)
      repository.add_aggregate(agg2)
    end

    on TriggerOtherAggregate do |command|
      agg = repository.load_aggregate(command.aggregate_id)
      agg.add_event
    end
  end

  class TestWorkflow < Sequent::Core::Workflow
    on OtherAggregateTriggered do |event|
      execute_commands TriggerOtherAggregate.new(aggregate_id: event.other_aggregate_id)
    end
  end

  class TestEventHandler < Sequent::Core::Projector
    manages_tables TestRecord

    def initialize(*args)
      @sequence_numbers = []
      super(*args)
    end

    attr_reader :sequence_numbers

    on EventAdded do |event|
      @sequence_numbers << event.sequence_number
    end
  end

  before do
    Sequent::Configuration.reset
    Sequent.configuration.event_handlers << TestWorkflow.new
    Sequent.configuration.event_handlers << test_event_handler
    Sequent.configuration.command_handlers << TestCommandHandler.new
  end

  let(:test_event_handler) { TestEventHandler.new }

  it 'handles events in the proper order' do
    Sequent.command_service.execute_commands TriggerTestCase.new(aggregate_id: Sequent.new_uuid)
    expect(test_event_handler.sequence_numbers).to eq [1, 2]
  end

  context 'given an error' do
    before do
      expect_any_instance_of(TestEventHandler).to receive(:handle_message).and_raise(RuntimeError.new('oops!'))
    end

    it 'fails with a PublishEventError' do
      expect do
        Sequent.command_service.execute_commands TriggerTestCase.new(aggregate_id: Sequent.new_uuid)
      end.to raise_error(Sequent::Core::EventPublisher::PublishEventError)
    end
  end
end
