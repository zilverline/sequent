# frozen_string_literal: true

require 'spec_helper'

RSpec.configure do |config|
  config.include Sequent::Test::CommandHandlerHelpers
end

module Sequent
  module Test
    describe Sequent::Test::CommandHandlerHelpers do
      before :each do
        Sequent.configuration.event_store = Sequent::Test::CommandHandlerHelpers::FakeEventStore.new
        Sequent.configuration.command_handlers = [UniqueKeysCommandHandler.new]
      end

      let(:aggregate_id) { Sequent.new_uuid }
      let(:aggregate_id_1) { Sequent.new_uuid }
      let(:aggregate_id_2) { Sequent.new_uuid }

      class UniqueKeysCommand < Sequent::Core::Command
        attrs keys: array(String)
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
          @keys.to_h { |key| [key, key] }
        end

        on UniqueKeysEvent do |event|
          @keys = event.keys
        end
      end

      class UniqueKeysCommandHandler < Sequent::Core::BaseCommandHandler
        on UniqueKeysCommand do |command|
          repository.add_aggregate UniqueKeysAggregate.new(command)
        end
      end

      it 'allows an aggregate with multiple unique keys' do
        when_command UniqueKeysCommand.new(aggregate_id:, keys: %w[a b])
        expect(Sequent.configuration.event_store.unique_keys).to eq(
          {
            %w[a a] => aggregate_id,
            %w[b b] => aggregate_id,
          },
        )
      end

      it 'allows an aggregate with multiple unique keys to change a key' do
        given_events UniqueKeysEvent.new(aggregate_id:, sequence_number: 1, keys: %w[a b])
        when_command UniqueKeysCommand.new(aggregate_id:, keys: %w[a c])
        expect(Sequent.configuration.event_store.unique_keys).to eq(
          {
            %w[a a] => aggregate_id,
            %w[c c] => aggregate_id,
          },
        )
      end

      it 'fails when adding two different aggregates with the same unique key' do
        when_command UniqueKeysCommand.new(aggregate_id: aggregate_id_1, keys: %w[a])
        expect do
          when_command UniqueKeysCommand.new(aggregate_id: aggregate_id_2, keys: %w[a])
        end.to raise_error Sequent::Core::AggregateKeyNotUniqueError
      end
    end
  end
end
