# frozen_string_literal: true

require 'active_record'
require_relative 'sequent_oj'

module Sequent
  module Core
    module SerializesCommand
      def command
        args = serialize_json? ? Sequent::Core::Oj.strict_load(command_json) : command_json
        Class.const_get(command_type).deserialize_from_json(args)
      end

      def command=(command)
        self.created_at = command.created_at
        self.aggregate_id = command.aggregate_id if command.respond_to? :aggregate_id
        self.user_id = command.user_id if command.respond_to? :user_id
        self.command_type = command.class.name
        self.command_json = serialize_json? ? Sequent::Core::Oj.dump(command.attributes) : command.attributes

        # optional attributes (here for historic reasons)
        # this should be moved to a configurable CommandSerializer
        self.event_aggregate_id = command.event_aggregate_id if serialize_attribute?(command, :event_aggregate_id)
        self.event_sequence_number = command.event_sequence_number if serialize_attribute?(
          command,
          :event_sequence_number,
        )
      end

      private

      def serialize_json?
        return true unless self.class.respond_to? :columns_hash

        json_column_type = self.class.columns_hash['command_json'].sql_type_metadata.type
        %i[json jsonb].exclude? json_column_type
      end

      def serialize_attribute?(command, attribute)
        [self, command].all? { |obj| obj.respond_to?(attribute) }
      end
    end

    # For storing Sequent::Core::Command in the database using active_record
    class CommandRecord < Sequent::ApplicationRecord
      include SerializesCommand

      self.primary_key = :id
      self.table_name = 'command_records'

      has_many :child_events,
               inverse_of: :parent_command,
               class_name: :EventRecord,
               foreign_key: :command_record_id

      validates_presence_of :command_type, :command_json

      # A `belongs_to` association fails in weird ways with ActiveRecord 7.1, probably due to the use of composite
      # primary keys so use an explicit query here and cache the result.
      def parent_event
        return nil unless event_aggregate_id && event_sequence_number

        @parent_event ||= EventRecord.find_by(aggregate_id: event_aggregate_id, sequence_number: event_sequence_number)
      end

      def origin_command
        parent_event&.parent_command&.origin_command || self
      end

      # @deprecated
      alias parent parent_event
      # @deprecated
      alias children child_events
      # @deprecated
      alias origin origin_command
    end
  end
end
