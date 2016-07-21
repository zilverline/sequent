require_relative '../ext/ext'

module Sequent
  module Core
    module Helpers
      class ValueValidators
        VALIDATORS = {
          ::Symbol => ->(_) { true },
          ::String => ->(value) { value.nil? || value.is_a?(String) },
          ::Integer => ->(value) { valid_integer?(value) },
          ::Boolean => ->(value) { valid_bool?(value) },
          ::Date => ->(value) { valid_date?(value) },
          ::DateTime => ->(value) { valid_date_time?(value) }
        }

        def self.valid_integer?(value)
          value.blank? || Integer(value)
        rescue
          false
        end

        def self.valid_bool?(value)
          return true if value.blank?
          value.is_a?(TrueClass) || value.is_a?(FalseClass) || value == "true" || value == "false"
        end

        def self.valid_date?(value)
          return true if value.blank?
          return true if value.is_a?(Date)
          return false unless value =~ /\d{4}-\d{2}-\d{2}/
          !!Date.iso8601(value) rescue false
        end

        def self.valid_date_time?(value)
          return true if value.blank?
          value.is_a?(DateTime) || !!DateTime.iso8601(value.dup) rescue false
        end

        def self.for(klass)
          new(klass)
        end

        def initialize(klass)
          @klass = klass
        end

        def valid_value?(value)
          VALIDATORS[@klass].call(value)
        end
      end
    end
  end
end
