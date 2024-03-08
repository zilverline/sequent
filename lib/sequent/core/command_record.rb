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
        self.organization_id = command.organization_id if serialize_attribute?(command, :organization_id)
        self.event_aggregate_id = command.event_aggregate_id if serialize_attribute?(command, :event_aggregate_id)
        self.event_sequence_number = command.event_sequence_number if serialize_attribute?(
          command,
          :event_sequence_number,
        )
      end

      private

      def serialize_json?
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

      self.table_name = 'command_records'

      has_many :event_records

      validates_presence_of :command_type, :command_json

      def parent
        EventRecord
          .where(aggregate_id: event_aggregate_id, sequence_number: event_sequence_number)
          .where('event_type != ?', Sequent::Core::SnapshotEvent.name)
          .first
      end

      def children
        event_records
      end

      def origin
        parent.present? ? find_origin(parent) : self
      end

      def find_origin(record)
        return find_origin(record.parent) if record.parent.present?

        record
      end
    end
  end
end
