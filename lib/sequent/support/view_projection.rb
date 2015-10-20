module Sequent
  module Support
    class ViewProjection
      attr_reader :name, :version, :schema_definition
      def initialize(name, version, schema_definition)
        @name = name
        @version = version
        @schema_definition = schema_definition
      end

      def build!
        load schema_definition
        event_store = Sequent.configuration.event_store
        event_store.replay_events { Events::ORDERED_BY_ID[event_store] }
      end

      def schema_name
        "#{name}_#{version}"
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
