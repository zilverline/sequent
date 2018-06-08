require 'spec_helper'

describe Sequent::Core::EventPublisher do
  class OtherAggregateTriggered < Sequent::Core::Event
    attrs other_aggregate_id: String
  end
  class EventAdded < Sequent::Core::Event; end
  class TriggerTestCase < Sequent::Core::Command; end
  class TriggerOtherAggregate < Sequent::Core::Command; end

  class TestAggregate < Sequent::Core::AggregateRoot
    def trigger_other_aggregate(aggregate_id)
      apply OtherAggregateTriggered, other_aggregate_id: aggregate_id
    end

    def add_event
      apply EventAdded
    end
  end

  class TestCommandHandler < Sequent::Core::BaseCommandHandler
    on TriggerTestCase do |command|
      agg1 = TestAggregate.new(aggregate_id: Sequent.new_uuid)
      agg2 = TestAggregate.new(aggregate_id: Sequent.new_uuid)

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
    def initialize(*args)
      @sequence_numbers = []
      super(*args)
    end

    attr_reader :sequence_numbers

    on EventAdded do |event|
      @sequence_numbers << event.sequence_number
    end
  end

  it 'handles events in the proper order' do
    Sequent::Configuration.reset
    test_event_handler = TestEventHandler.new
    Sequent.configuration.event_handlers << TestWorkflow.new
    Sequent.configuration.event_handlers << test_event_handler
    Sequent.configuration.command_handlers << TestCommandHandler.new

    Sequent.command_service.execute_commands TriggerTestCase.new(aggregate_id: Sequent.new_uuid)

    expect(test_event_handler.sequence_numbers).to eq [1,2]
  end
end
