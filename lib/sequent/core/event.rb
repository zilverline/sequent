# frozen_string_literal: true

require 'active_model'
require_relative 'helpers/string_support'
require_relative 'helpers/equal_support'
require_relative 'helpers/attribute_support'
require_relative 'helpers/copyable'

module Sequent
  module Core
    class Event
      include Sequent::Core::Helpers::Copyable
      include Sequent::Core::Helpers::AttributeSupport
      include Sequent::Core::Helpers::EqualSupport
      include Sequent::Core::Helpers::StringSupport
      attrs aggregate_id: String, sequence_number: Integer, created_at: Time

      def initialize(args = {})
        update_all_attributes args
        fail 'Missing aggregate_id' unless @aggregate_id
        fail 'Missing sequence_number' unless @sequence_number

        @created_at ||= Time.now
      end

      def payload
        result = {}
        instance_variables
          .reject { |k| payload_variables.include?(k) }
          .select { |k| self.class.types.keys.include?(to_attribute_name(k)) }
          .each do |k|
            result[k.to_s[1..-1].to_sym] = instance_variable_get(k)
          end
        result
      end

      protected

      def payload_variables
        %i[@aggregate_id @sequence_number @created_at]
      end

      private

      def to_attribute_name(instance_variable_name)
        instance_variable_name[1..-1].to_sym
      end
    end

    class SnapshotEvent < Event
      attrs data: String
    end
  end
end
