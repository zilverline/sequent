# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::InlineEventPublisher do
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

  let(:test_event_handler) { TestEventHandler.new }

  it 'handles events in the proper order' do
    Sequent.configuration.event_handlers << TestWorkflow.new
    Sequent.configuration.event_handlers << test_event_handler
    Sequent.configuration.command_handlers << TestCommandHandler.new

    Sequent.command_service.execute_commands TriggerTestCase.new(aggregate_id: Sequent.new_uuid)

    expect(test_event_handler.sequence_numbers).to eq [1, 2]
  end

  context 'dispatching events' do
    class DispatchTestRecord; end

    class DispatchTestProjector < Sequent::Core::Projector
      manages_tables DispatchTestRecord

      attr_accessor :log

      on_batch EventAdded do |events|
        log << [:projector_batch, events.map(&:sequence_number)]
      end

      on EventAdded do |event|
        log << [:projector, event.sequence_number]
      end
    end

    class DispatchTestWorkflow < Sequent::Core::Workflow
      attr_accessor :log

      on EventAdded do |event|
        log << [:workflow, event.sequence_number]
      end
    end

    let(:log) { [] }
    let(:projector) { DispatchTestProjector.new.tap { |p| p.log = log } }
    let(:workflow) { DispatchTestWorkflow.new.tap { |w| w.log = log } }
    let(:events) { [1, 2].map { |n| EventAdded.new(aggregate_id: Sequent.new_uuid, sequence_number: n) } }

    class InstantiatedTestWorkflow < Sequent::Core::Workflow
      self.skip_autoregister = true

      class << self
        attr_accessor :instances
      end

      attr_reader :handled

      def initialize
        super
        @handled = []
        self.class.instances << self
      end

      on EventAdded do |event|
        @handled << event.sequence_number
      end
    end

    it 'handles one event at a time with the projectors before the workflows for each event' do
      # The workflow is registered first, but the projectors still handle each event first.
      described_class.new.publish_events(events, event_handlers: [workflow, projector])

      expect(log).to eq [
        [:projector_batch, [1]],
        [:projector, 1],
        [:workflow, 1],
        [:projector_batch, [2]],
        [:projector, 2],
        [:workflow, 2],
      ]
    end

    it 'handles all events at once per event handler in bulk' do
      other_workflow = DispatchTestWorkflow.new.tap { |w| w.log = [] }

      Sequent::Core::BulkEventPublisher.new.publish_events(events, event_handlers: [workflow, other_workflow])

      expect(log).to eq [[:workflow, 1], [:workflow, 2]]
      expect(other_workflow.log).to eq [[:workflow, 1], [:workflow, 2]]
    end

    it 'instantiates a registered event handler class for every batch of events it handles' do
      InstantiatedTestWorkflow.instances = []
      publisher = described_class.new
      event_handlers = [InstantiatedTestWorkflow]

      publisher.publish_events(events, event_handlers:)
      publisher.publish_events(
        [OtherAggregateTriggered.new(aggregate_id: Sequent.new_uuid, sequence_number: 1, other_aggregate_id: 'x')],
        event_handlers:,
      )
      publisher.publish_events(events, event_handlers:)

      expect(InstantiatedTestWorkflow.instances.map(&:handled)).to eq [[1, 2], [1, 2]]
    end

    it 'only publishes to the given event handlers' do
      described_class.new.publish_events(events, event_handlers: [workflow])

      expect(log).to eq [[:workflow, 1], [:workflow, 2]]
    end

    it 'fails when events are published while publishing events' do
      publisher = described_class.new
      nested_publishing_workflow = Class.new(Sequent::Core::Workflow) do
        self.skip_autoregister = true

        define_method(:publisher) { publisher }

        on EventAdded do |event|
          publisher.publish_events([event], event_handlers: [])
        end
      end

      expect do
        publisher.publish_events(events, event_handlers: [nested_publishing_workflow.new])
      end.to raise_error(Sequent::Core::PublishEventError) { |error|
        expect(error.cause).to be_a Sequent::Core::NestedEventPublishingError
      }
    end

    it 'reports the event that failed when handling events in bulk' do
      failing_workflow = Class.new(Sequent::Core::Workflow) do
        self.skip_autoregister = true

        on EventAdded do |event|
          fail 'event failed' if event.sequence_number == 2
        end
      end

      expect do
        Sequent::Core::BulkEventPublisher.new.publish_events(events, event_handlers: [failing_workflow.new])
      end.to raise_error(Sequent::Core::PublishEventError) { |error|
        expect(error.event.sequence_number).to eq 2
        expect(error.cause.message).to eq 'event failed'
      }
    end

    it 'handles events in bulk using a projector instance with its own persistor' do
      Sequent::Core::BulkEventPublisher.new.publish_events(events, event_handlers: [projector])

      # The projector also handles each event individually, so the events are handled in order.
      expect(log).to eq [[:projector_batch, [1]], [:projector, 1], [:projector_batch, [2]], [:projector, 2]]
    end
  end

  context Sequent::Core::EventPublisher do
    it 'queues the events published while publishing events' do
      Sequent.configuration.event_publisher = Sequent::Core::EventPublisher.new
      Sequent.configuration.event_handlers << TestWorkflow.new << test_event_handler
      Sequent.configuration.command_handlers << TestCommandHandler.new

      Sequent.command_service.execute_commands TriggerTestCase.new(aggregate_id: Sequent.new_uuid)

      expect(test_event_handler.sequence_numbers).to eq [1, 2]
      expect(Sequent::Core::EventPublisher::PublishEventError).to be Sequent::Core::PublishEventError
    end
  end

  context Sequent::Core::ActiveProjectorsEventPublisher do
    before do
      Sequent::Configuration.reset
      Sequent.configuration.event_publisher = Sequent::Core::ActiveProjectorsEventPublisher.new
      Sequent.configuration.projectors_replayer_total_lock_timeout = 0.01.seconds
    end
    after { Sequent::Configuration.reset }

    context 'event store database deploy' do
      class UnknownProjector < Sequent::Core::Projector
        manages_no_tables
      end

      before do
        Sequent::Core::ProjectorState.delete_all
        Sequent.configuration.event_handlers << test_event_handler
        Sequent.configuration.command_handlers << TestCommandHandler.new
      end

      it 'ignores projectors that are replaying, but not active and not activating' do
        Sequent::Core::Projectors.register_replaying_projectors!([TestEventHandler])

        Sequent.command_service.execute_commands TriggerTestCase.new(aggregate_id: Sequent.new_uuid)

        expect(test_event_handler.sequence_numbers).to be_empty
      end

      it 'fails when unknown projectors are active' do
        Sequent::Core::Projectors.register_active_projectors!([TestEventHandler, UnknownProjector])

        expect do
          Sequent.command_service.execute_commands TriggerTestCase.new(aggregate_id: Sequent.new_uuid)
        end.to raise_error Sequent::Core::UnknownActiveProjectorError
      end

      it 'filters the inactive projectors of all stages' do
        inactive_bulk_projector = Class.new(Sequent::Core::Projector) do
          self.skip_autoregister = true
          self.phase = :bulk
          manages_no_tables

          def self.name = 'InactiveBulkProjector'

          on EventAdded do |_event|
            fail 'an inactive projector must not handle events'
          end
        end
        Sequent.configuration.event_handlers << inactive_bulk_projector
        Sequent.configuration.event_publisher = Sequent::Core::ActiveProjectorsEventPublisher.new(
          Sequent::Core::StagedEventPublisher.with_phases,
        )
        Sequent::Core::Projectors.register_active_projectors!([TestEventHandler])

        Sequent.command_service.execute_commands TriggerTestCase.new(aggregate_id: Sequent.new_uuid)

        expect(test_event_handler.sequence_numbers).to eq [1]
      end

      it 'fails when the projector is activating to finalize event replay' do
        Sequent::Core::Projectors.register_activating_projectors!([TestEventHandler])

        expect do
          Sequent.command_service.execute_commands TriggerTestCase.new(aggregate_id: Sequent.new_uuid)
        end.to raise_error Sequent::Core::ProjectorIsActivatingError
      end

      it "fails when the active projector's version is different from our version" do
        Sequent::Core::Projectors.register_active_projectors!([TestEventHandler])
        TestEventHandler.version += 1

        expect do
          Sequent.command_service.execute_commands TriggerTestCase.new(aggregate_id: Sequent.new_uuid)
        end.to raise_error Sequent::Core::DifferentProjectorVersionIsActiveError
      end
    end

    context 'projector activation' do
      def set_reader_lock_timeout = ActiveRecord::Base.connection.execute("SET LOCAL lock_timeout TO '10ms'")
      def update_projector_states = Sequent::Core::Projectors.register_active_projectors!([Sequent::Core::Projector])
      def read_projector_states = Sequent::Core::Projectors.projector_states

      it 'waits for projector state updates before reading' do
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
            set_reader_lock_timeout
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

      it 'allows readers to bypass projector state update when lock cannot be acquired quickly' do
        Sequent.configuration.projectors_replayer_total_lock_timeout = 1.seconds

        lock_order = Queue.new

        start_writer = Queue.new
        start_reader2 = Queue.new
        stop_reader1 = Queue.new

        reader1 = Thread.new do
          ActiveRecord::Base.transaction do
            read_projector_states
            lock_order << 'reader1'

            start_writer << 'locked states for reading 1'

            stop_reader1.deq

            true
          end
        end

        writer = Thread.new do
          ActiveRecord::Base.transaction do
            start_writer.deq

            start_reader2 << 'starting to lock for writing'

            update_projector_states
            lock_order << 'writer'

            true
          end
        end

        reader2 = Thread.new do
          ActiveRecord::Base.transaction do
            start_reader2.deq

            # Give the writer some time to execute the exclusive lock table statement, which will
            # block since reader1 has a share lock already.
            sleep 0.1

            read_projector_states
            lock_order << 'reader2'

            stop_reader1 << 'locked states for reading 2'

            true
          end
        end

        expect(reader1.join(1)&.value).to be_present
        expect(reader2.join(1)&.value).to be_present
        expect(writer.join(1)&.value).to be_present

        # Reader2 should bypass the writer, even though the writer attempted to lock the table
        # before reader2
        expect(lock_order.deq(true)).to eq('reader1')
        expect(lock_order.deq(true)).to eq('reader2')
        expect(lock_order.deq(true)).to eq('writer')
      end
    end
  end
end
