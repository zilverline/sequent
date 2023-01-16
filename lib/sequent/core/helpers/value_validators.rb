# frozen_string_literal: true

require_relative '../ext/ext'

module Sequent
  module Core
    module Helpers
      class ValueValidators
        INVALID_STRING_CHARS = [
          "\u0000",
        ].freeze

        VALIDATORS = {
          ::Symbol => ->(_) { true },
          ::String => ->(value) { valid_string?(value) },
          ::Integer => ->(value) { valid_integer?(value) },
          ::Boolean => ->(value) { valid_bool?(value) },
          ::Date => ->(value) { valid_date?(value) },
          ::Time => ->(value) { valid_time?(value) },
          ::DateTime => ->(value) { valid_date_time?(value) },
        }.freeze

        def self.valid_integer?(value)
          value.blank? || Integer(value)
        rescue StandardError
          false
        end

        def self.valid_bool?(value)
          return true if value.blank?

          value.is_a?(TrueClass) || value.is_a?(FalseClass) || value == 'true' || value == 'false'
        end

        def self.valid_date?(value)
          return true if value.blank?
          return true if value.is_a?(Date)
          return false unless value =~ /\d{4}-\d{2}-\d{2}/

          begin
            !!Date.iso8601(value)
          rescue StandardError
            false
          end
        end

        def self.valid_date_time?(value)
          return true if value.blank?

          begin
            value.is_a?(DateTime) || !!DateTime.iso8601(value.dup)
          rescue StandardError
            false
          end
        end

        def self.valid_time?(value)
          return true if value.blank?

          begin
            value.is_a?(Time) || !!Time.iso8601(value.dup)
          rescue StandardError
            false
          end
        end

        def self.valid_string?(value)
          return true if value.nil?

          value.to_s && INVALID_STRING_CHARS.none? { |invalid_char| value.to_s.include?(invalid_char) }
        rescue StandardError
          false
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
