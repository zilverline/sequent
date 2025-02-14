# frozen_string_literal: true

require 'active_record'
require_relative 'sequent_oj'
require_relative '../application_record'

module Sequent
  module Core
    # == Event Record Hooks
    #
    # These hooks are called during the life cycle of
    # Sequent::Core::EventRecord. It is recommended to create a subclass of
    # +Sequent::Core::EventRecordHooks+ when implementing this in your
    # application.
    #
    #   Sequent.configure do |config|
    #     config.event_record_hooks_class = MyApp::EventRecordHooks
    #   end
    #
    #   module MyApp
    #     class EventRecordHooks < Sequent::EventRecordHooks
    #
    #       # Adds additional metadata to the +event_records+ table.
    #       def self.after_serialization(event_record, event)
    #         event_record.metadata = event.metadata if event.respond_to?(:metadata)
    #       end
    #
    #     end
    #   end
    class EventRecordHooks
      # Called after assigning Sequent's event attributes to the +event_record+.
      #
      # *Params*
      # - +event_record+ An instance of Sequent.configuration.event_record_class
      # - +event+ An instance of the Sequent::Core::Event being persisted
      #
      #     class EventRecordHooks < Sequent::EventRecordHooks
      #       def self.after_serialization(event_record, event)
      #         event_record.seen_by_hook = true
      #       end
      #     end
      def self.after_serialization(event_record, event)
        # noop
      end
    end

    module SerializesEvent
      def event
        payload = serialize_json? ? Sequent::Core::Oj.strict_load(event_json) : event_json
        Class.const_get(event_type).deserialize_from_json(payload)
      end

      def event=(event)
        self.aggregate_id = event.aggregate_id
        self.sequence_number = event.sequence_number
        self.event_type = event.class.name
        self.created_at = event.created_at
        self.event_json = serialize_json? ? self.class.serialize_to_json(event) : event.attributes

        Sequent.configuration.event_record_hooks_class.after_serialization(self, event)
      end

      module ClassMethods
        def serialize_to_json(event)
          Sequent::Core::Oj.dump(event)
        end

        def serialize_json?
          return true unless respond_to? :columns_hash

          json_column_type = columns_hash['event_json'].sql_type_metadata.type
          %i[json jsonb].exclude? json_column_type
        end
      end

      def self.included(host_class)
        host_class.extend(ClassMethods)
      end

      def serialize_json?
        self.class.serialize_json?
      end
    end

    class EventRecord < Sequent::ApplicationRecord
      include SerializesEvent

      self.primary_key = %i[aggregate_id sequence_number]
      self.table_name = 'event_records'
      self.ignored_columns = %w[xact_id]

      belongs_to :stream_record, foreign_key: :aggregate_id, primary_key: :aggregate_id

      belongs_to :parent_command, class_name: :CommandRecord, foreign_key: :command_record_id

      if Gem.loaded_specs['activerecord'].version < Gem::Version.create('7.2')
        has_many :child_commands,
                 class_name: :CommandRecord,
                 primary_key: %i[aggregate_id sequence_number],
                 query_constraints: %i[event_aggregate_id event_sequence_number]
      else
        has_many :child_commands,
                 class_name: :CommandRecord,
                 primary_key: %i[aggregate_id sequence_number],
                 foreign_key: %i[event_aggregate_id event_sequence_number]
      end

      validates_presence_of :aggregate_id, :sequence_number, :event_type, :event_json, :stream_record, :parent_command
      validates_numericality_of :sequence_number, only_integer: true, greater_than: 0

      def self.find_by_event(event)
        find_by(aggregate_id: event.aggregate_id, sequence_number: event.sequence_number)
      end

      def origin_command
        parent_command&.origin_command
      end

      # @deprecated
      alias parent parent_command
      alias children child_commands
      alias origin origin_command
    end
  end
end
