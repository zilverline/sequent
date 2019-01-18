require 'active_record'
require_relative 'sequent_oj'

module Sequent
  module Core

    module SerializesCommand
      def command
        args = Sequent::Core::Oj.strict_load(command_json)
        Class.const_get(command_type.to_sym).deserialize_from_json(args)
      end

      def command=(command)
        self.created_at = command.created_at
        self.aggregate_id = command.aggregate_id if command.respond_to? :aggregate_id
        self.organization_id = command.organization_id if command.respond_to? :organization_id
        self.user_id = command.user_id if command.respond_to? :user_id
        self.command_type = command.class.name
        self.command_json = Sequent::Core::Oj.dump(command.attributes)
        self.event_aggregate_id = command.event_aggregate_id if command.respond_to? :event_aggregate_id
        self.event_sequence_number = command.event_sequence_number if command.respond_to? :event_sequence_number
      end
    end

    # For storing Sequent::Core::Command in the database using active_record
    class CommandRecord < ActiveRecord::Base
      include SerializesCommand

      self.table_name = "command_records"

      belongs_to :event_record, foreign_key: 'event_aggregate_id', primary_key: 'aggregate_id', optional: true
      has_many :event_records

      validates_presence_of :command_type, :command_json

    end
  end
end
