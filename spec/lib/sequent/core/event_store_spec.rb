require 'spec_helper'

module Sequent
  module Core

    class MyEvent < Event
    end

    describe EventStore do
      context ".configure" do

        it "can be configured using a ActiveRecord class" do
          Sequent::Core::EventStore.configure do |config|
            config.event_record_class = :foo
          end
          expect(Sequent::Core::EventStore.configuration.event_record_class).to eq :foo
        end

        it "can be configured with event_handlers" do
          Sequent::Core::EventStore.configure do |config|
            config.event_handlers = [:event_handler]
          end
          expect(Sequent::Core::EventStore.configuration.event_handlers).to eq [:event_handler]
        end
      end

      let(:event_store) { Sequent::Core::EventStore.configure }
      let(:aggregate_id) { "aggregate-#{rand(10000000)}" }

      it "can store events" do
        event_store.commit_events(
          CommandRecord.new,
          [
            [
              EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id, snapshot_threshold: 13),
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
          CommandRecord.new,
          [
            [
              EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id, snapshot_threshold: 1),
              [MyEvent.new(aggregate_id: aggregate_id, sequence_number: 1)]
            ]
          ]
        )

        expect(event_store.aggregates_that_need_snapshots(nil)).to include(aggregate_id)
      end
    end

  end
end
