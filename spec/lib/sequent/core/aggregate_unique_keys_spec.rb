# frozen_string_literal: true

require 'spec_helper'

RSpec.configure do |config|
  config.include Sequent::Test::CommandHandlerHelpers
end

module Sequent
  module Core
    class UniqueKeysCommand < Sequent::Core::Command
      attrs keys: array(String)
    end

    class MoveUniqueKeysCommand < Sequent::Core::Command
      attrs to_aggregate_id: String, keys: array(String)
    end

    class UniqueKeysEvent < Sequent::Core::Event
      attrs keys: array(String)
    end

    class UniqueKeysAggregate < Sequent::Core::AggregateRoot
      def initialize(command)
        super(command.aggregate_id)
        apply UniqueKeysEvent, keys: command.keys
      end

      def unique_keys
        @keys.to_h { |key| [key, key] }.symbolize_keys
      end

      def unique_keys=(keys)
        apply UniqueKeysEvent, keys:
      end

      def add_keys(keys)
        apply UniqueKeysEvent, keys: @keys.union(keys)
      end

      def remove_keys(keys)
        apply UniqueKeysEvent, keys: @keys - keys
      end

      on UniqueKeysEvent do |event|
        @keys = event.keys
      end
    end

    class UniqueKeysCommandHandler < Sequent::Core::BaseCommandHandler
      on UniqueKeysCommand do |command|
        aggregate = repository.load_aggregate(command.aggregate_id)
        aggregate.unique_keys = command.keys
      rescue Sequent::Core::AggregateRepository::AggregateNotFound
        repository.add_aggregate UniqueKeysAggregate.new(command)
      end

      on MoveUniqueKeysCommand do |command|
        do_with_aggregate(command, UniqueKeysAggregate, command.aggregate_id) do |from|
          do_with_aggregate(command, UniqueKeysAggregate, command.to_aggregate_id) do |to|
            from.remove_keys(command.keys)
            to.add_keys(command.keys)
          end
        end
      end
    end

    shared_examples 'aggregates with unique keys' do
      let(:event_store) { Sequent.configuration.event_store }

      before :each do
        Sequent.configuration.command_handlers = [UniqueKeysCommandHandler.new]
      end

      let(:aggregate_id) { Sequent.new_uuid }
      let(:aggregate_id_1) { Sequent.new_uuid }
      let(:aggregate_id_2) { Sequent.new_uuid }

      it 'allows an aggregate with multiple unique keys' do
        when_command UniqueKeysCommand.new(aggregate_id:, keys: %w[a b])
        expect(event_store.find_event_stream(aggregate_id).unique_keys).to eq(
          {
            a: 'a',
            b: 'b',
          },
        )
      end

      it 'allows an aggregate with multiple unique keys to change a key' do
        given_events UniqueKeysEvent.new(aggregate_id:, sequence_number: 1, keys: %w[a b])
        when_command UniqueKeysCommand.new(aggregate_id:, keys: %w[a c])
        expect(event_store.find_event_stream(aggregate_id).unique_keys).to eq(
          {
            a: 'a',
            c: 'c',
          },
        )
      end

      it 'allows moving a unique key from one aggregate to another' do
        given_events UniqueKeysEvent.new(aggregate_id: aggregate_id_1, sequence_number: 1, keys: %w[a b]),
                     UniqueKeysEvent.new(aggregate_id: aggregate_id_2, sequence_number: 1, keys: %w[c])
        when_command MoveUniqueKeysCommand.new(
          aggregate_id: aggregate_id_1,
          to_aggregate_id: aggregate_id_2,
          keys: %w[b],
        )
        expect(event_store.find_event_stream(aggregate_id_1).unique_keys).to eq(
          {
            a: 'a',
          },
        )
        expect(event_store.find_event_stream(aggregate_id_2).unique_keys).to eq(
          {
            b: 'b',
            c: 'c',
          },
        )
      end

      it 'fails when adding two different aggregates with the same unique key' do
        when_command UniqueKeysCommand.new(aggregate_id: aggregate_id_1, keys: %w[a])
        expect do
          when_command UniqueKeysCommand.new(aggregate_id: aggregate_id_2, keys: %w[a])
        end.to raise_error(
          an_instance_of(Sequent::Core::AggregateKeyNotUniqueError)
            .and(having_attributes(aggregate_type: 'Sequent::Core::UniqueKeysAggregate'))
            .and(having_attributes(aggregate_id: aggregate_id_2)),
        )
      end

      context 'find by unique key' do
        before do
          given_events UniqueKeysEvent.new(aggregate_id: aggregate_id_1, sequence_number: 1, keys: %w[a b])
        end

        it 'can find an aggregate by its unique keys' do
          aggregate = Sequent.configuration.aggregate_repository.find_aggregate_by_unique_key(
            :a,
            'a',
          )
          expect(aggregate).to be_present

          aggregate = Sequent.configuration.aggregate_repository.find_aggregate_by_unique_key(
            :b,
            'b',
          )
          expect(aggregate).to be_present
        end

        it 'returns nil if not found' do
          aggregate = Sequent.configuration.aggregate_repository.find_aggregate_by_unique_key(
            :c,
            'c',
          )
          expect(aggregate).to be_nil
        end
      end

      # Test located here so it tests both the real event store and the fake event store in one go.
      it 'can enumerate event streams' do
        given_events UniqueKeysEvent.new(aggregate_id: aggregate_id_1, sequence_number: 1, keys: %w[a b]),
                     UniqueKeysEvent.new(aggregate_id: aggregate_id_2, sequence_number: 1, keys: %w[c])

        aggregate_ids = event_store.event_streams_enumerator.to_a.flatten
        expect(aggregate_ids).to contain_exactly(aggregate_id_1, aggregate_id_2)
      end
    end

    describe Sequent::Test::CommandHandlerHelpers::FakeEventStore do
      before :each do
        Sequent.configuration.event_store = Sequent::Test::CommandHandlerHelpers::FakeEventStore.new
      end

      include_examples 'aggregates with unique keys'
    end

    describe Sequent::Core::EventStore do
      before :each do
        Sequent.configuration.event_store = Sequent::Core::EventStore.new
      end

      include_examples 'aggregates with unique keys'
    end
  end
end
