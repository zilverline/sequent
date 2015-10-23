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
          event_store.replay_events { Events::ORDERED_BY_ID[event_store] }
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

      ORDERED_BY_ID = lambda do |event_store|
        event_record_class = event_store.event_record_class
        snapshot_event_class = event_store.snapshot_event_class
        event_store.event_record_class.connection.select_all("
SELECT event_type, event_json
  FROM #{quote_table_name event_record_class.table_name}
 WHERE event_type <> #{quote snapshot_event_class}
 ORDER BY id
")
      end
    end
  end
end
