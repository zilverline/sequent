# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::StagedEventPublisher do
  class StagedTrigger < Sequent::Core::Event; end
  class StagedFollowUp < Sequent::Core::Event; end

  # Publishes a new event when it handles a `StagedTrigger`, like a workflow generating new events.
  class StagedPublishingHandler < Sequent::Core::Workflow
    self.skip_autoregister = true
    self.phase = :publishing

    on StagedTrigger do |event|
      Sequent.configuration.event_publisher.publish_events(
        [StagedFollowUp.new(aggregate_id: event.aggregate_id, sequence_number: event.sequence_number + 1)],
      )
    end
  end

  class StagedRecordingHandler < Sequent::Core::Workflow
    self.skip_autoregister = true
    self.phase = :recording

    on StagedTrigger, StagedFollowUp do |_event|
      # Nothing to do, the stage records the events it handles
    end
  end

  # Stage that records the batches of events it handles in the shared +log+.
  class RecordingStage < Sequent::Core::InlineEventPublisher
    def initialize(name, log)
      super()
      @name = name
      @log = log
    end

    def handle_events(events, event_handlers)
      @log << [@name, events.map(&:class)]
      super
    end
  end

  let(:log) { [] }
  let(:publishing_stage) { RecordingStage.new(:publishing, log) }
  let(:recording_stage) { RecordingStage.new(:recording, log) }

  before do
    Sequent.configuration.event_handlers = [StagedPublishingHandler.new, StagedRecordingHandler.new]
  end

  # Configures a publisher with the given immediate stages, by phase.
  def configure_publisher(**immediate)
    Sequent.configuration.event_publisher = described_class.new(immediate:)
  end

  let(:aggregate_id) { Sequent.new_uuid }
  let(:trigger) { StagedTrigger.new(aggregate_id:, sequence_number: 1) }
  let(:follow_up) { StagedFollowUp.new(aggregate_id:, sequence_number: 2) }

  it 'requires at least one stage' do
    expect { described_class.new(immediate: {}) }.to raise_error ArgumentError
    expect { described_class.new(immediate: nil) }.to raise_error ArgumentError
    expect do
      described_class.new(immediate: {recording: recording_stage}, deferred: {recording: publishing_stage})
    end.to raise_error ArgumentError, /duplicate phases/
  end

  it 'passes all published events to each stage in a single batch' do
    publisher = configure_publisher(recording: recording_stage, publishing: publishing_stage)

    publisher.publish_events([trigger, trigger])

    expect(log.first).to eq [:recording, [StagedTrigger, StagedTrigger]]
  end

  it 'only starts the next stage after the previous stage handled all published events' do
    publisher = configure_publisher(publishing: publishing_stage, recording: recording_stage)

    publisher.publish_events([trigger])

    # The first stage also handles the event it published itself before the next stage is started,
    # so the next stage handles both events in a single batch.
    expect(log).to eq [
      [:publishing, [StagedTrigger]],
      [:publishing, [StagedFollowUp]],
      [:recording, [StagedTrigger, StagedFollowUp]],
    ]
  end

  it 'handles events published by a later stage in the earlier stages first' do
    publisher = configure_publisher(recording: recording_stage, publishing: publishing_stage)

    publisher.publish_events([trigger])

    expect(log).to eq [
      [:recording, [StagedTrigger]],
      [:publishing, [StagedTrigger]],
      [:recording, [StagedFollowUp]],
      [:publishing, [StagedFollowUp]],
    ]
  end

  it 'does not publish any events when the event handlers are disabled' do
    Sequent.configuration.disable_event_handlers = true
    publisher = configure_publisher(publishing: publishing_stage, recording: recording_stage)

    publisher.publish_events([trigger])

    expect(log).to be_empty
  end

  it 'clears the events queue when a stage fails' do
    failing_stage = Class.new(Sequent::Core::InlineEventPublisher) do
      def handle_events(_events, _event_handlers)
        fail 'stage failed'
      end
    end.new
    publisher = Sequent.configuration.event_publisher =
      described_class.new(immediate: {publishing: publishing_stage, recording: failing_stage})

    expect { publisher.publish_events([trigger]) }.to raise_error 'stage failed'

    expect(publisher.send(:events_queue)).to be_empty
  end

  context 'with a command service' do
    class StagedOtherAggregateTriggered < Sequent::Core::Event
      attrs other_aggregate_id: String
    end
    class StagedEventAdded < Sequent::Core::Event; end

    class StartStagedTestCase < Sequent::Core::Command; end
    class AddStagedEvent < Sequent::Core::Command; end

    class StagedTestAggregate < Sequent::Core::AggregateRoot
      def trigger_other_aggregate(aggregate_id)
        apply StagedOtherAggregateTriggered, other_aggregate_id: aggregate_id
      end

      def add_event
        apply StagedEventAdded
      end
    end

    class StagedTestCommandHandler < Sequent::Core::BaseCommandHandler
      on StartStagedTestCase do |_command|
        agg1 = StagedTestAggregate.new(Sequent.new_uuid)
        agg2 = StagedTestAggregate.new(Sequent.new_uuid)

        agg1.trigger_other_aggregate(agg2.id)
        agg2.add_event

        repository.add_aggregate(agg1)
        repository.add_aggregate(agg2)
      end

      on AddStagedEvent do |command|
        repository.load_aggregate(command.aggregate_id).add_event
      end
    end

    class StagedTestWorkflow < Sequent::Core::Workflow
      self.skip_autoregister = true
      self.phase = :workflows

      on StagedOtherAggregateTriggered do |event|
        execute_commands AddStagedEvent.new(aggregate_id: event.other_aggregate_id)
      end
    end

    # A workflow in the given phase that handles all events, which its stage records.
    def self.recording_workflow(phase)
      Class.new(Sequent::Core::Workflow) do
        self.skip_autoregister = true
        self.phase = phase

        on(StagedOtherAggregateTriggered, StagedEventAdded) { |_event| nil }
      end
    end

    StagedRecordingWorkflow = recording_workflow(:projectors)
    StagedLastRecordingWorkflow = recording_workflow(:last)

    class DoNothingStagedTestCase < Sequent::Core::Command; end
    class FailStagedTestCase < Sequent::Core::Command; end

    class OtherStagedTestCommandHandler < Sequent::Core::BaseCommandHandler
      on DoNothingStagedTestCase do |_command|
        # No events
      end

      on FailStagedTestCase do |_command|
        fail 'command failed'
      end
    end

    # Configures a publisher with recording stages for the given phases, and an event handler per phase.
    def use_stages(immediate:, deferred:)
      handlers = {
        workflows: StagedTestWorkflow,
        projectors: StagedRecordingWorkflow,
        last: StagedLastRecordingWorkflow,
      }
      stages = ->(phases) { phases.to_h { |phase| [phase, RecordingStage.new(phase, log)] } }
      Sequent.configuration.event_publisher =
        described_class.new(immediate: stages[immediate], deferred: stages[deferred])
      Sequent.configuration.event_handlers = (immediate + deferred).map { |phase| handlers.fetch(phase).new }
    end

    before do
      Sequent.configuration.command_handlers << StagedTestCommandHandler.new
      Sequent.configuration.command_handlers << OtherStagedTestCommandHandler.new
    end

    it 'defers the later stages until no more commands are queued' do
      use_stages(immediate: %i[workflows], deferred: %i[projectors])

      Sequent.command_service.execute_commands StartStagedTestCase.new(aggregate_id: Sequent.new_uuid)

      # The first stage handles the events of every command, the later stage handles the events of
      # all commands at once.
      expect(log).to eq [
        [:workflows, [StagedOtherAggregateTriggered, StagedEventAdded]],
        [:workflows, [StagedEventAdded]],
        [:projectors, [StagedOtherAggregateTriggered, StagedEventAdded, StagedEventAdded]],
      ]
    end

    it 'processes the commands executed by a deferred stage before starting the next stage' do
      use_stages(immediate: %i[projectors], deferred: %i[workflows last])

      Sequent.command_service.execute_commands StartStagedTestCase.new(aggregate_id: Sequent.new_uuid)

      expect(log).to eq [
        [:projectors, [StagedOtherAggregateTriggered, StagedEventAdded]],
        [:workflows, [StagedOtherAggregateTriggered, StagedEventAdded]],
        [:projectors, [StagedEventAdded]],
        [:workflows, [StagedEventAdded]],
        [:last, [StagedOtherAggregateTriggered, StagedEventAdded, StagedEventAdded]],
      ]
    end

    it 'handles the deferred events when the last command has no events' do
      use_stages(immediate: %i[projectors], deferred: %i[last])

      Sequent.command_service.execute_commands(
        StartStagedTestCase.new(aggregate_id: Sequent.new_uuid),
        DoNothingStagedTestCase.new(aggregate_id: Sequent.new_uuid),
      )

      expect(log).to eq [
        [:projectors, [StagedOtherAggregateTriggered, StagedEventAdded]],
        [:last, [StagedOtherAggregateTriggered, StagedEventAdded]],
      ]
    end

    it 'discards the deferred events when a command fails' do
      use_stages(immediate: %i[projectors], deferred: %i[last])

      expect do
        Sequent.command_service.execute_commands(
          StartStagedTestCase.new(aggregate_id: Sequent.new_uuid),
          FailStagedTestCase.new(aggregate_id: Sequent.new_uuid),
        )
      end.to raise_error 'command failed'
      log.clear

      Sequent.command_service.execute_commands StartStagedTestCase.new(aggregate_id: Sequent.new_uuid)

      expect(log).to eq [
        [:projectors, [StagedOtherAggregateTriggered, StagedEventAdded]],
        [:last, [StagedOtherAggregateTriggered, StagedEventAdded]],
      ]
    end
  end

  context 'with phases' do
    class PhasedTestEvent < Sequent::Core::Event; end
    class StartPhasedTestCase < Sequent::Core::Command; end

    class PhasedTestAggregate < Sequent::Core::AggregateRoot
      def add_event
        apply PhasedTestEvent
      end
    end

    class PhasedTestCommandHandler < Sequent::Core::BaseCommandHandler
      on StartPhasedTestCase do |command|
        aggregate = PhasedTestAggregate.new(command.aggregate_id)
        aggregate.add_event
        repository.add_aggregate(aggregate)
      end
    end

    class InlinePhasedTestWorkflow < Sequent::Core::Workflow
      attr_accessor :log

      on PhasedTestEvent do |event|
        log << [:inline, event.aggregate_id]
      end
    end

    class BeforeCommitPhasedTestWorkflow < Sequent::Core::Workflow
      self.phase = :before_commit

      attr_accessor :log

      on_batch PhasedTestEvent do |events|
        log << [:before_commit, events.map(&:aggregate_id)]
      end
    end

    class UnknownPhaseTestWorkflow < Sequent::Core::Workflow
      self.skip_autoregister = true
      self.phase = :later
    end

    class StartTwoPhasedTestCases < Sequent::Core::Command; end

    class TwoPhasedTestCasesCommandHandler < Sequent::Core::BaseCommandHandler
      on StartTwoPhasedTestCases do |_command|
        2.times do
          aggregate = PhasedTestAggregate.new(Sequent.new_uuid)
          aggregate.add_event
          repository.add_aggregate(aggregate)
        end
      end
    end

    class BulkTestRecord < Sequent::ApplicationRecord; end

    class BulkTestProjector < Sequent::Core::Projector
      self.skip_autoregister = true
      self.phase = :bulk
      manages_tables BulkTestRecord

      on_batch PhasedTestEvent do |events|
        create_records(BulkTestRecord, events.map { |event| {aggregate_id: event.aggregate_id} })
      end
    end

    class BatchInlineTestProjector < Sequent::Core::Projector
      self.skip_autoregister = true
      manages_tables BulkTestRecord

      class << self
        attr_accessor :batch_sizes
      end

      on_batch PhasedTestEvent do |events|
        self.class.batch_sizes << events.size
      end
    end

    class RecordCountingTestWorkflow < Sequent::Core::Workflow
      self.skip_autoregister = true

      class << self
        attr_accessor :counts
      end

      on PhasedTestEvent do |_event|
        self.class.counts << BulkTestRecord.count
      end
    end

    let(:inline_workflow) { InlinePhasedTestWorkflow.new.tap { |w| w.log = log } }
    let(:before_commit_workflow) { BeforeCommitPhasedTestWorkflow.new.tap { |w| w.log = log } }

    before do
      Sequent.configuration.command_handlers << PhasedTestCommandHandler.new
      Sequent.configuration.event_handlers = [inline_workflow, before_commit_workflow]
    end

    it 'is the default event publisher' do
      Sequent::Configuration.reset

      expect(Sequent.configuration.event_publisher).to be_a described_class
      expect(Sequent.configuration.event_publisher.phases).to eq %i[bulk inline before_commit]
      expect(Sequent.configuration.event_publisher.stages.values.map(&:class)).to eq [
        Sequent::Core::BulkEventPublisher,
        Sequent::Core::InlineEventPublisher,
        Sequent::Core::BulkEventPublisher,
      ]
    end

    it 'handles the inline phase for each command and the before commit phase for all commands at once' do
      Sequent.configuration.event_publisher = described_class.with_phases
      aggregate_ids = [Sequent.new_uuid, Sequent.new_uuid]

      Sequent.command_service.execute_commands(*aggregate_ids.map { |id| StartPhasedTestCase.new(aggregate_id: id) })

      expect(log).to eq [
        [:inline, aggregate_ids[0]],
        [:inline, aggregate_ids[1]],
        [:before_commit, aggregate_ids],
      ]
    end

    context 'with a bulk projector' do
      before do
        Sequent::ApplicationRecord.connection.execute(<<~SQL)
          CREATE TABLE bulk_test_records (id bigserial PRIMARY KEY, aggregate_id character varying NOT NULL)
        SQL
        BulkTestRecord.reset_column_information
        Sequent.configuration.command_handlers << TwoPhasedTestCasesCommandHandler.new
        Sequent.configuration.event_publisher = described_class.with_phases
      end

      after do
        Sequent::ApplicationRecord.connection.execute('DROP TABLE bulk_test_records')
      end

      it 'inserts the records of all events of a command using a single statement before the inline phase' do
        Sequent.configuration.event_handlers << BulkTestProjector << RecordCountingTestWorkflow
        RecordCountingTestWorkflow.counts = []
        inserts = []
        subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
          inserts << payload[:sql] if payload[:sql].include?('INSERT INTO "bulk_test_records"')
        end

        Sequent.command_service.execute_commands(
          StartTwoPhasedTestCases.new(aggregate_id: Sequent.new_uuid),
          StartTwoPhasedTestCases.new(aggregate_id: Sequent.new_uuid),
        )

        expect(inserts.size).to eq 2
        expect(BulkTestRecord.count).to eq 4
        # The inline workflow sees the records of all events of the command.
        expect(RecordCountingTestWorkflow.counts).to eq [2, 2, 4, 4]
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      it 'calls the batch handlers of an inline projector with one event at a time' do
        Sequent.configuration.event_handlers << BatchInlineTestProjector
        BatchInlineTestProjector.batch_sizes = []

        Sequent.command_service.execute_commands StartTwoPhasedTestCases.new(aggregate_id: Sequent.new_uuid)

        expect(BatchInlineTestProjector.batch_sizes).to eq [1, 1]
      end
    end

    it 'fails on an event handler with a phase without a stage' do
      Sequent.configuration.event_publisher = described_class.with_phases
      Sequent.configuration.event_handlers << UnknownPhaseTestWorkflow

      expect do
        Sequent.command_service.execute_commands StartPhasedTestCase.new(aggregate_id: Sequent.new_uuid)
      end.to raise_error ArgumentError, /phase :later of UnknownPhaseTestWorkflow is not one of the phases/
    end
  end
end
