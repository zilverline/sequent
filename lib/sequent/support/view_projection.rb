# frozen_string_literal: true

require 'postgresql_cursor'

module Sequent
  module Support
    class ViewProjection
      attr_reader :name, :version, :schema_definition

      def initialize(options)
        @name = options.fetch(:name)
        @version = options.fetch(:version)
        @schema_definition = options.fetch(:definition)
        @replay_event_handlers = options.fetch(:event_handlers)
      end

      def build!
        with_default_configuration do
          Sequent.configuration.event_handlers = @replay_event_handlers

          load schema_definition
          event_store = Sequent.configuration.event_store
          ordering = Events::ORDERED_BY_STREAM
          event_store.replay_events_from_cursor(
            block_size: 10_000,
            get_events: -> { ordering[event_store] },
          )
        end
      end

      def schema_name
        "#{name}_#{version}"
      end

      private

      def with_default_configuration
        original_configuration = Sequent.configuration
        Sequent::Configuration.reset
        yield
        Sequent::Configuration.restore(original_configuration)
      end
    end

    module Events
      extend ActiveRecord::ConnectionAdapters::Quoting

      ORDERED_BY_STREAM = ->(_event_store) do
        snapshot_event_type = quote(Sequent.configuration.snapshot_event_class)

        Sequent.configuration.event_record_class
          .select('event_type, event_json')
          .where("event_type <> #{snapshot_event_type}")
          .order!('stream_record_id, sequence_number')
      end
    end
  end
end
