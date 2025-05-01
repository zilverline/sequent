# frozen_string_literal: true

require 'spec_helper'

module Sequent
  module Internal
    describe 'partitioned storage' do
      let(:aggregate_id) { Sequent.new_uuid }
      let(:events_partition_key) { 'partition-key' }

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

      context 'changed partition key' do
        let(:updated_events_partition_key) { 'new-key' }

        before do
          PartitionKeyChange.delete_all

          event_store.commit_events(
            Sequent::Core::Command.new(aggregate_id:),
            [
              [
                Sequent::Core::EventStream.new(
                  aggregate_type: 'Aggregate',
                  aggregate_id:,
                  events_partition_key: updated_events_partition_key,
                ),
                [
                  Sequent::Core::Event.new(aggregate_id:, sequence_number: 2),
                ],
              ],
            ],
          )
        end

        it 'logs the changed partition key' do
          aggregate = PartitionedAggregate.first
          expect(aggregate.events_partition_key).to eq(events_partition_key)

          logged_change = PartitionKeyChange.find_by!(aggregate_id:)
          expect(logged_change.partitioned_aggregate).to be_present
          expect(logged_change.old_partition_key).to eq(aggregate.events_partition_key)
          expect(logged_change.new_partition_key).to eq(updated_events_partition_key)
        end

        it 'updates the aggregate and events using a maintenance task' do
          PartitionKeyChange.update_aggregate_partition_keys(limit: 10)

          logged_change = PartitionKeyChange.find_by(aggregate_id:)
          expect(logged_change).to be_nil

          aggregate = PartitionedAggregate.find_by!(aggregate_id:)
          expect(aggregate.events_partition_key).to eq(updated_events_partition_key)

          events = aggregate.partitioned_events.to_a
          expect(events.size).to eq(2)
          expect(events).to all(have_attributes(partition_key: updated_events_partition_key))
        end
      end
    end
  end
end
