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
        if Gem.loaded_specs['activerecord'].version < Gem::Version.create('7.2')
          skip("AR 7.1.3 doesn't allow correct configuration of composite foreign key constraint")
          # AR 7.1.3 fails with `Association Sequent::Internal::PartitionedEvent#partitioned_aggregate primary key
          # ["partition_key", "aggregate_id"] doesn't match with foreign key ["events_partition_key",
          # "aggregate_id"]. Please specify query_constraints, or primary_key and foreign_key values.`, however
          # specifying the `foreign_key` with multiple columns results in the error: `Passing ["events_partition_key",
          # "aggregate_id"] array to :foreign_key option on the
          # Sequent::Internal::PartitionedEvent#partitioned_aggregate association is not supported. Use the
          # query_constraints: ["events_partition_key", "aggregate_id"] option instead to represent a composite foreign
          # key.`
        end

        aggregate = PartitionedAggregate.first
        expect(aggregate).to be_present
        expect(aggregate.aggregate_id).to eq(aggregate_id)
        expect(aggregate.events_partition_key).to eq(events_partition_key)
        expect(aggregate.aggregate_type.type).to eq('Aggregate')

        events = aggregate.partitioned_events.to_a
        expect(events.size).to eq(1)

        event = events[0]
        expect(event.partitioned_aggregate).to be(aggregate)
        expect(event.aggregate_id).to eq(aggregate_id)
        expect(event.partition_key).to eq(events_partition_key)
        expect(event.event_type.type).to eq('Sequent::Core::Event')

        command = event.partitioned_command
        expect(command).to be_present
        expect(command.command_type.type).to eq('Sequent::Core::Command')
        expect(command.partitioned_events).to eq(events)
      end
    end
  end
end
