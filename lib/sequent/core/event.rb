require 'active_model'
require_relative 'helpers/string_support'
require_relative 'helpers/equal_support'
require_relative 'helpers/attribute_support'
require_relative 'helpers/copyable'

module Sequent
  module Core
    class Event
      include Sequent::Core::Helpers::StringSupport,
              Sequent::Core::Helpers::EqualSupport,
              Sequent::Core::Helpers::AttributeSupport,
              Sequent::Core::Helpers::Copyable
      attrs aggregate_id: String, sequence_number: Integer, created_at: DateTime

      def initialize(args = {})
        update_all_attributes args
        raise "Missing aggregate_id" unless @aggregate_id
        raise "Missing sequence_number" unless @sequence_number
        @created_at ||= DateTime.now
      end

      def payload
        result = {}
        instance_variables
          .reject { |k| payload_variables.include?(k) }
          .select { |k| self.class.types.keys.include?(to_attribute_name(k))}
          .each do |k|
          result[k.to_s[1 .. -1].to_sym] = instance_variable_get(k)
        end
        result
      end
      protected
      def payload_variables
        %i{@aggregate_id @sequence_number @created_at}
      end

      private
      def to_attribute_name(instance_variable_name)
        instance_variable_name[1 .. -1].to_sym
      end

    end

    class TenantEvent < Event

      attrs organization_id: String

      def initialize(args = {})
        super
        raise "Missing organization_id" unless @organization_id
      end

      protected
      def payload_variables
        super << :"@organization_id"
      end

    end

    class CreateEvent < TenantEvent

    end

    class SnapshotEvent < Event
      attrs data: String
    end

  end
end
