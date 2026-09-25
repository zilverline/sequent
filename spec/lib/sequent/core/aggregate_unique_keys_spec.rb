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

    class EmployeePeriodEvent < Sequent::Core::Event
      attrs employee_id: String, period: String
    end

    class EmployeePeriodAggregate < Sequent::Core::AggregateRoot
      attr_reader :employee_id, :period

      unique_key :employee_period, :employee_id, :period

      def initialize(aggregate_id, employee_id, period)
        super(aggregate_id)
        move(employee_id, period)
      end

      def move(employee_id, period)
        apply EmployeePeriodEvent, employee_id:, period:
      end

      on EmployeePeriodEvent do |event|
        @employee_id = event.employee_id
        @period = event.period
      end
    end

    class DatedKeyEvent < Sequent::Core::Event
      attrs date: Date
    end

    class DatedKeyAggregate < Sequent::Core::AggregateRoot
      attr_reader :date

      unique_key :dated_key, :date

      on DatedKeyEvent do |event|
        @date = event.date
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
        # The lookups also search the aggregates in the repository, which would otherwise be left over from earlier
        # examples on this thread.
        Sequent.configuration.aggregate_repository.clear
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

        context 'with aggregates in the repository' do
          let(:repository) { Sequent.configuration.aggregate_repository }

          after { repository.clear }

          it 'finds one that is added but not yet committed' do
            aggregate = UniqueKeysAggregate.new(UniqueKeysCommand.new(aggregate_id: aggregate_id_2, keys: %w[x]))
            repository.add_aggregate(aggregate)

            expect(repository.find_aggregate_by_unique_key(:x, 'x')).to be(aggregate)
          end

          it 'finds one whose key changed since it was loaded by its new key only' do
            aggregate = repository.load_aggregate(aggregate_id_1)
            aggregate.unique_keys = %w[c]

            expect(repository.find_aggregate_by_unique_key(:a, 'a')).to be_nil
            expect(repository.find_aggregate_by_unique_key(:c, 'c')).to be(aggregate)
          end
        end

        it 'finds an aggregate by a key holding a date' do
          given_events DatedKeyEvent.new(aggregate_id: aggregate_id_2, sequence_number: 1, date: Date.new(2024, 1, 1))

          aggregate = Sequent.configuration.aggregate_repository.find_aggregate_by_unique_key(
            :dated_key,
            {date: Date.new(2024, 1, 1)},
          )
          expect(aggregate&.id).to eq(aggregate_id_2)
        end

        it 'returns nil if not found' do
          aggregate = Sequent.configuration.aggregate_repository.find_aggregate_by_unique_key(
            :c,
            'c',
          )
          expect(aggregate).to be_nil
        end
      end

      context 'find by unique key containing' do
        let(:aggregate_id_3) { Sequent.new_uuid }
        let(:repository) { Sequent.configuration.aggregate_repository }

        def employee_period(aggregate_id, employee_id, period)
          EmployeePeriodEvent.new(aggregate_id:, sequence_number: 1, employee_id:, period:)
        end

        before do
          given_events(
            employee_period(aggregate_id_1, 'e1', '2024-01'),
            employee_period(aggregate_id_2, 'e1', '2024-02'),
            employee_period(aggregate_id_3, 'e2', '2024-01'),
          )
        end

        it 'finds every aggregate whose key contains the given part' do
          aggregates = repository.find_aggregates_by_unique_key_containing(:employee_period, {employee_id: 'e1'})

          expect(aggregates.map(&:id)).to contain_exactly(aggregate_id_1, aggregate_id_2)
        end

        it 'matches on every attribute of the given part' do
          aggregates = repository.find_aggregates_by_unique_key_containing(
            :employee_period,
            {employee_id: 'e1', period: '2024-02'},
          )

          expect(aggregates.map(&:id)).to eq([aggregate_id_2])
        end

        it 'loads only the aggregates whose key the block accepts' do
          before_february = ->(key) { key[:period] <= '2024-01' }
          aggregates = repository.find_aggregates_by_unique_key_containing(
            :employee_period,
            {employee_id: 'e1'},
            &before_february
          )

          expect(aggregates.map(&:id)).to eq([aggregate_id_1])
        end

        it 'returns the matching keys by aggregate id' do
          expect(event_store.find_unique_keys_containing(:employee_period, {employee_id: 'e1'})).to eq(
            aggregate_id_1 => {employee_id: 'e1', period: '2024-01'},
            aggregate_id_2 => {employee_id: 'e1', period: '2024-02'},
          )
        end

        context 'with aggregates in the repository' do
          after { repository.clear }

          it 'finds one that is added but not yet committed' do
            added = EmployeePeriodAggregate.new(Sequent.new_uuid, 'e1', '2024-03')
            repository.add_aggregate(added)

            aggregates = repository.find_aggregates_by_unique_key_containing(:employee_period, {employee_id: 'e1'})

            expect(aggregates.map(&:id)).to contain_exactly(aggregate_id_1, aggregate_id_2, added.id)
          end

          it 'passes the keys of those to the block as well' do
            added = EmployeePeriodAggregate.new(Sequent.new_uuid, 'e1', '2024-03')
            repository.add_aggregate(added)
            from_march = ->(key) { key[:period] >= '2024-03' }

            aggregates = repository.find_aggregates_by_unique_key_containing(
              :employee_period,
              {employee_id: 'e1'},
              &from_march
            )

            expect(aggregates).to eq([added])
          end

          it 'leaves out one whose key no longer matches since it was loaded' do
            repository.load_aggregate(aggregate_id_2).move('e3', '2024-02')

            aggregates = repository.find_aggregates_by_unique_key_containing(:employee_period, {employee_id: 'e1'})

            expect(aggregates.map(&:id)).to eq([aggregate_id_1])
          end
        end

        it 'returns no aggregates when none match' do
          expect(repository.find_aggregates_by_unique_key_containing(:employee_period, {employee_id: 'e3'})).to eq([])
        end

        it 'only searches the given scope' do
          expect(repository.find_aggregates_by_unique_key_containing(:other_scope, {employee_id: 'e1'})).to eq([])
        end

        it 'checks the type of the aggregates it finds' do
          expect do
            repository.find_aggregates_by_unique_key_containing(
              :employee_period,
              {employee_id: 'e1'},
              UniqueKeysAggregate,
            )
          end.to raise_error(TypeError)
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
