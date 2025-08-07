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
      super
    end

    attr_reader :sequence_numbers

    on EventAdded do |event|
      @sequence_numbers << event.sequence_number
    end
  end

  it 'handles events in the proper order' do
    test_event_handler = TestEventHandler.new
    Sequent.configuration.event_handlers << TestWorkflow.new
    Sequent.configuration.event_handlers << test_event_handler
    Sequent.configuration.command_handlers << TestCommandHandler.new

    Sequent.command_service.execute_commands TriggerTestCase.new(aggregate_id: Sequent.new_uuid)

    expect(test_event_handler.sequence_numbers).to eq [1, 2]
  end

  context Sequent::Core::ActiveProjectorsEventPublisher do
    before do
      Sequent::Configuration.reset
      Sequent.configuration.enable_projector_states = true
      Sequent.configuration.event_publisher = Sequent::Core::ActiveProjectorsEventPublisher.new
    end
    after { Sequent::Configuration.reset }

    context 'event store database deploy' do
      class UnknownProjector < Sequent::Core::Projector
        manages_no_tables
      end

      before do
        Sequent::Core::ProjectorState.delete_all
        Sequent.configuration.event_handlers << TestEventHandler.new
        Sequent.configuration.command_handlers << TestCommandHandler.new
        Sequent.configuration.migrations_class = SpecMigrations
        Sequent.configuration.migrations_class.version = 1
        Sequent.activate_current_configuration!
      end

      it 'fails when unknown projectors are active' do
        Sequent::Core::Projectors.register_active_projectors!([TestEventHandler, UnknownProjector], 1)

        expect do
          Sequent.command_service.execute_commands TriggerTestCase.new(aggregate_id: Sequent.new_uuid)
        end.to raise_error Sequent::Core::UnknownActiveProjectorError
      end

      it 'fails when the projector is activating to finalize event replay' do
        Sequent::Core::Projectors.register_activating_projectors!([TestEventHandler], Sequent.new_version + 1)

        expect do
          Sequent.command_service.execute_commands TriggerTestCase.new(aggregate_id: Sequent.new_uuid)
        end.to raise_error Sequent::Core::DifferentProjectorVersionIsActiveError
      end
    end

    context 'projector activation' do
      def set_lock_timeout = ActiveRecord::Base.connection.execute("SET lock_timeout TO '10ms'")
      def update_projector_states = Sequent::Core::Projectors.register_active_projectors!([Sequent::Core::Projector], 1)
      def read_projector_states = Sequent::Core::Projectors.projector_states

      it 'waits for project state updates before reading' do
        reader_lock_attempted = Queue.new
        writer_locked = Queue.new
        writer = Thread.new do
          ActiveRecord::Base.transaction do
            update_projector_states
            writer_locked << 'locked states for reading'

            reader_lock_attempted.deq
          end
        end

        reader = Thread.new do
          ActiveRecord::Base.transaction do
            writer_locked.deq
            set_lock_timeout
            read_projector_states
            false
          rescue ActiveRecord::LockWaitTimeout
            true
          end
        end

        expect(reader.join(0.5).value).to be(true)
      ensure
        reader_lock_attempted << 'reader finished'
        writer.join(0.5).value
      end

      it 'waits for readers to when updating the projector states table' do
        writer_lock_attempted = Queue.new
        reader_locked = Queue.new
        reader = Thread.new do
          ActiveRecord::Base.transaction do
            read_projector_states
            reader_locked << 'locked states for reading'

            writer_lock_attempted.deq
          end
        end

        writer = Thread.new do
          ActiveRecord::Base.transaction do
            reader_locked.deq
            set_lock_timeout
            update_projector_states
          rescue ActiveRecord::LockWaitTimeout
            true
          end
        end

        expect(writer.join(0.5).value).to be(true)
      ensure
        writer_lock_attempted << 'writer finished'
        reader.join(0.5).value
      end
    end
  end
end
