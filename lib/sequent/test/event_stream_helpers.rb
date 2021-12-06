# frozen_string_literal: true

module Sequent
  module Test
    ##
    # Use in tests
    #
    # This provides a nice DSL for generating streams of events. FactoryBot is required when using this helper.
    #
    # Example for Rspec config
    #
    # RSpec.configure do |config|
    #   config.include Sequent::Test::EventStreamHelpers
    # end
    #
    # Then in a spec
    #
    # given_stream_for(aggregate_id: 'X') do |s|
    #   s.group_created owner_aggregate_id: 'Y'
    #   s.group_opened
    #   s.owner_joined_group owner_aggregate_id: 'Y'
    # end
    #
    # Methods on `s` will be FactoryBot factories. All arguments will be passed on to FactoryBot's build method.
    # Aggregate ids and sequence numbers will be set automatically.
    #
    # The example above can also be written as follows:
    #
    # events = event_stream(aggregate_id: 'X') do |s|
    #   s.group_created owner_aggregate_id: 'Y'
    #   s.group_opened
    #   s.owner_joined_group owner_aggregate_id: 'Y'
    # end
    #
    # given_events(events)
    #
    module EventStreamHelpers
      class Builder
        attr_reader :events

        def initialize(aggregate_id)
          @aggregate_id = aggregate_id
          @events = []
        end

        # rubocop:disable Style/MissingRespondToMissing
        def method_missing(name, *args, &block)
          args = prepare_arguments(args)
          @events << FactoryBot.build(name, *args, &block)
        end
        # rubocop:enable Style/MissingRespondToMissing

        private

        def prepare_arguments(args)
          options = args.last.is_a?(Hash) ? args.pop : {}
          args << options.merge(aggregate_id: @aggregate_id, sequence_number: next_sequence_number)
        end

        def next_sequence_number
          @events.count + 1
        end
      end

      def event_stream(aggregate_id:, &block)
        builder = Builder.new(aggregate_id)
        block.call(builder)
        builder.events
      end

      def given_stream_for(aggregate_id:, &block)
        given_events(*event_stream(aggregate_id: aggregate_id, &block))
      end

      def self.included(_spec)
        require 'factory_bot'
      rescue LoadError
        raise ArgumentError, 'Factory bot is required to use the event stream helpers'
      end
    end
  end
end
