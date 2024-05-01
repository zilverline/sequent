# frozen_string_literal: true

require 'spec_helper'

module Sequent
  module Internal
    describe 'partitioned storage' do
      let(:aggregate_id) { Sequent.new_uuid }
      let(:events_partition_key) { 'abc' }

      let(:event_store) { Sequent.configuration.event_store }

      before do
        event_store.commit_events(
          Sequent::Core::Command.new(aggregate_id:),
          [
            [
              Sequent::Core::EventStream.new(aggregate_type: 'Aggregate', aggregate_id:, events_partition_key:),
              [
                Sequent::Core::Event.new(aggregate_id:, sequence_number: 1),
              ],
            ],
          ],
        )
      end

      it 'persists to the partitioned tables' do
        aggregate = PartitionedAggregate.first
        expect(aggregate).to be_present
        expect(aggregate.aggregate_id).to eq(aggregate_id)
        expect(aggregate.events_partition_key).to eq(events_partition_key)
        expect(aggregate.aggregate_type.type).to eq('Aggregate')

        events = aggregate.events.to_a
        expect(events.size).to eq(1)

        event = events[0]
        expect(event.aggregate).to be(aggregate)
        expect(event.aggregate_id).to eq(aggregate_id)
        expect(event.partition_key).to eq(events_partition_key)
        expect(event.event_type.type).to eq('Sequent::Core::Event')

        command = event.command
        expect(command).to be_present
        expect(command.command_type.type).to eq('Sequent::Core::Command')
        expect(command.events).to eq(events)
      end
    end
  end
end
