require 'spec_helper'
require 'sequent/support'
require 'postgresql_cursor'

describe Sequent::Core::EventStore do

  class MyEvent < Sequent::Core::Event
  end

  let(:event_store) { Sequent::configuration.event_store }
  let(:aggregate_id) { "aggregate-#{rand(10000000)}" }

  context ".configure" do
    it "can be configured using a ActiveRecord class" do
      Sequent.configure do |config|
        config.stream_record_class = :foo
      end
      expect(Sequent.configuration.stream_record_class).to eq :foo
    end

    it "can be configured with event_handlers" do
      event_handler_class = Class.new
      Sequent.configure do |config|
        config.event_handlers = [event_handler_class]
      end
      expect(Sequent.configuration.event_handlers).to eq [event_handler_class]
    end

    it 'can be configured multiple times' do
      foo = Class.new
      bar = Class.new
      Sequent.configure do |config|
        config.event_handlers = [foo]
      end
      expect(Sequent.configuration.event_handlers).to eq [foo]
      Sequent.configure do |config|
        config.event_handlers << bar
      end
      expect(Sequent.configuration.event_handlers).to eq [foo, bar]
    end
  end

  context "snapshotting" do
    it "can store events" do
      event_store.commit_events(
        Sequent::Core::CommandRecord.new,
        [
          [
            Sequent::Core::EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id, snapshot_threshold: 13),
            [MyEvent.new(aggregate_id: aggregate_id, sequence_number: 1)]
          ]
        ]
      )

      stream, events = event_store.load_events aggregate_id

      expect(stream.snapshot_threshold).to eq(13)
      expect(stream.aggregate_type).to eq('MyAggregate')
      expect(stream.aggregate_id).to eq(aggregate_id)
      expect(events.first.aggregate_id).to eq(aggregate_id)
      expect(events.first.sequence_number).to eq(1)
    end

    it "can find streams that need snapshotting" do
      event_store.commit_events(
        Sequent::Core::CommandRecord.new,
        [
          [
            Sequent::Core::EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id, snapshot_threshold: 1),
            [MyEvent.new(aggregate_id: aggregate_id, sequence_number: 1)]
          ]
        ]
      )

      expect(event_store.aggregates_that_need_snapshots(nil)).to include(aggregate_id)
    end
  end

  describe '#commit_events' do
    it 'fails with OptimisticLockingError when RecordNotUnique' do
      expect {
        event_store.commit_events(
          Sequent::Core::CommandRecord.new,
          [
            [
              Sequent::Core::EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id, snapshot_threshold: 13),
              [MyEvent.new(aggregate_id: aggregate_id, sequence_number: 1), MyEvent.new(aggregate_id: aggregate_id, sequence_number: 1)]
            ]
          ]
        )
      }.to raise_error(Sequent::Core::EventStore::OptimisticLockingError) { |error| expect(error.cause).to be_a(ActiveRecord::RecordNotUnique) }
    end
  end

  describe '#exists?' do
    it 'gets true for an existing aggregate' do
      event_store.commit_events(
        Sequent::Core::CommandRecord.new,
        [
          [
            Sequent::Core::EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id, snapshot_threshold: 13),
            [MyEvent.new(aggregate_id: aggregate_id, sequence_number: 1)]
          ]
        ]
      )
      expect(event_store.stream_exists?(aggregate_id)).to eq(true)
    end

    it 'gets false for an non-existing aggregate' do
      expect(event_store.stream_exists?(aggregate_id)).to eq(false)
    end
  end

  describe "#load_events" do
    it 'returns nil for non existing aggregates' do
      stream, events = event_store.load_events(aggregate_id)
      expect(stream).to be_nil
      expect(events).to be_nil
    end

    it 'returns the stream and events for existing aggregates' do
      event_store.commit_events(
        Sequent::Core::CommandRecord.new,
        [
          [
            Sequent::Core::EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id),
            [MyEvent.new(aggregate_id: aggregate_id, sequence_number: 1)]
          ]
        ]
      )
      stream, events = event_store.load_events(aggregate_id)
      expect(stream).to be
      expect(events).to be
    end
  end

  describe "#load_events_for_aggregates" do
    let(:aggregate_id_1) { Sequent.new_uuid }
    let(:aggregate_id_2) { Sequent.new_uuid }

    before :each do
      event_store.commit_events(
        Sequent::Core::CommandRecord.new,
        [
          [
            Sequent::Core::EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id_1),
            [MyEvent.new(aggregate_id: aggregate_id_1, sequence_number: 1)]
          ],
          [
            Sequent::Core::EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id_2),
            [MyEvent.new(aggregate_id: aggregate_id_2, sequence_number: 1)]
          ]
        ]
      )
    end
    it 'returns the stream and events for multiple aggregates' do
      streams_with_events = event_store.load_events_for_aggregates([aggregate_id_1, aggregate_id_2])

      expect(streams_with_events).to have(2).items
      expect(streams_with_events[0]).to have(2).items
      expect(streams_with_events[1]).to have(2).items
    end
  end

  describe 'error handling for publishing events' do
    class RecordingHandler < Sequent::Core::BaseEventHandler
      attr_reader :recorded_events

      def initialize
        super
        @recorded_events = []
      end

      on MyEvent do |e|
        @recorded_events << e
      end
    end

    class FailingHandler < Sequent::Core::BaseEventHandler
      Error = Class.new(RuntimeError)

      on MyEvent do |_|
        fail Error, 'Handler error'
      end
    end

    before do
      Sequent.configure do |c|
        c.event_handlers << handler
      end
    end

    context 'given a handler for MyEvent' do
      let(:handler) { RecordingHandler.new }

      it 'calls an event handler that handles the event' do
        my_event = MyEvent.new(aggregate_id: aggregate_id, sequence_number: 1)
        event_store.commit_events(
          Sequent::Core::CommandRecord.new,
          [
            [
              Sequent::Core::EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id, snapshot_threshold: 13),
              [my_event]
            ]
          ]
        )
        expect(handler.recorded_events).to eq([my_event])
      end

      context 'Sequent.configuration.disable_event_handlers = true' do
        it 'does not publish any events' do
          Sequent.configuration.disable_event_handlers = true
          my_event = MyEvent.new(aggregate_id: aggregate_id, sequence_number: 1)
          event_store.commit_events(
            Sequent::Core::CommandRecord.new,
            [
              [
                Sequent::Core::EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id, snapshot_threshold: 13),
                [my_event]
              ]
            ]
          )
          expect(handler.recorded_events).to eq([])
        end
      end
    end

    context 'given a failing event handler' do
      let(:handler) { FailingHandler.new }
      let(:my_event) { MyEvent.new(aggregate_id: aggregate_id, sequence_number: 1) }
      subject(:publish_error) do
        begin
          event_store.commit_events(
            Sequent::Core::CommandRecord.new,
            [
              [
                Sequent::Core::EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id, snapshot_threshold: 13),
                [my_event]
              ]
            ]
          )
        rescue => e
          e
        end
      end

      it { is_expected.to be_a(Sequent::Core::EventPublisher::PublishEventError) }

      it 'preserves its cause' do
        expect(publish_error.cause).to be_a(FailingHandler::Error)
        expect(publish_error.cause.message).to eq('Handler error')
      end

      it 'specifies the event handler that failed' do
        expect(publish_error.event_handler_class).to eq(FailingHandler)
      end

      it 'specifies the event that failed' do
        expect(publish_error.event).to eq(my_event)
      end
    end
  end

  describe "#replay_events_from_cursor" do
    let(:stream_record) do
      Sequent::Core::StreamRecord.create!(
        aggregate_type: "Sequent::Core::AggregateRoot",
        aggregate_id: aggregate_id,
        created_at: DateTime.now
      )
    end
    let(:command_record) do
      Sequent::Core::CommandRecord.create!(
        command_type: "Sequent::Core::Command",
        command_json: "{}",
        aggregate_id: stream_record.aggregate_id
      )
    end
    let(:get_events_cursor) do
      ->() { Sequent::Support::Events::ORDERED_BY_STREAM[event_store] }
    end

    before do
      Sequent::Core::EventRecord.delete_all
      5.times do |n|
        Sequent::Core::EventRecord.create!(
          aggregate_id: stream_record.aggregate_id,
          sequence_number: n + 1,
          event_type: "Sequent::Core::Event",
          event_json: "{}",
          created_at: DateTime.now,
          command_record_id: command_record.id,
          stream_record_id: stream_record.id
        )
      end
    end

    it "publishes all events" do
      replay_counter = ReplayCounter.new
      Sequent.configuration.event_handlers << replay_counter
      event_store.replay_events_from_cursor(
        block_size: 2,
        get_events: get_events_cursor,
        on_progress: proc {}
      )
      expect(replay_counter.replay_count).to eq(Sequent::Core::EventRecord.count)
    end

    it "reports progress for each block" do
      progress = 0
      progress_reported_count = 0
      on_progress = lambda do |n, _, _|
        progress = n
        progress_reported_count += 1
      end
      event_store.replay_events_from_cursor(
        block_size: 2,
        get_events: get_events_cursor,
        on_progress: on_progress
      )
      total_events = Sequent::Core::EventRecord.count
      expect(progress).to eq(total_events)
      expect(progress_reported_count).to eq((total_events / 2.0).ceil)
    end
  end

  class ReplayCounter < Sequent::Core::BaseEventHandler
    attr_reader :replay_count

    def initialize
      @replay_count = 0
    end

    on Sequent::Core::Event do |_|
      @replay_count += 1
    end
  end
end
