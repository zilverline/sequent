require 'active_record'
require_relative 'sequent_oj'

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
        payload = Sequent::Core::Oj.strict_load(self.event_json)
        Class.const_get(self.event_type).deserialize_from_json(payload)
      end

      def event=(event)
        self.aggregate_id = event.aggregate_id
        self.sequence_number = event.sequence_number
        self.organization_id = event.organization_id if event.respond_to?(:organization_id)
        self.event_type = event.class.name
        self.created_at = event.created_at
        self.event_json = self.class.serialize_to_json(event)

        Sequent.configuration.event_record_hooks_class.after_serialization(self, event)
      end

      module ClassMethods
        def serialize_to_json(event)
          Sequent::Core::Oj.dump(event)
        end
      end

      def self.included(host_class)
        host_class.extend(ClassMethods)
      end
    end

    class EventRecord < ActiveRecord::Base
      include SerializesEvent

      self.table_name = "event_records"

      belongs_to :stream_record
      belongs_to :command_record

      validates_presence_of :aggregate_id, :sequence_number, :event_type, :event_json, :stream_record, :command_record
      validates_numericality_of :sequence_number, only_integer: true, greater_than: 0
    end

  end
end
