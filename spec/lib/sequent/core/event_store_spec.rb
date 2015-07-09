require 'spec_helper'

describe Sequent::Core::EventStore do

  class MyEvent < Sequent::Core::Event
  end

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
    let(:event_store) { Sequent::configuration.event_store }
    let(:aggregate_id) { "aggregate-#{rand(10000000)}" }

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

  describe '#exists?' do
    let(:event_store) { Sequent::configuration.event_store }
    let(:aggregate_id) { "aggregate-#{rand(10000000)}" }

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

    it 'gets false for an existing aggregate' do
      expect(event_store.stream_exists?(aggregate_id)).to eq(false)
    end
  end
end
