require_relative '../ext/ext'
require_relative 'array_with_type'

module Sequent
  module Core
    module Helpers
      class StringToValueParsers
        PARSERS = {
          ::Symbol => ->(value) { Symbol.deserialize_from_json(value) },
          ::String => ->(value) { value&.to_s },
          ::Integer => ->(value) { parse_to_integer(value) },
          ::BigDecimal => ->(value) { parse_to_bigdecimal(value) },
          ::Float => ->(value) { parse_to_float(value) },
          ::Boolean => ->(value) { parse_to_bool(value) },
          ::Date => ->(value) { parse_to_date(value) },
          ::DateTime => ->(value) { parse_to_date_time(value) },
          ::Hash => ->(value) { parse_to_hash(value) },
          ::Sequent::Core::Helpers::ArrayWithType => ->(values, type_in_array) { parse_array(values, type_in_array) },
          ::Sequent::Core::Helpers::Secret => ->(value) { Sequent::Core::Helpers::Secret.new(value).encrypt },
        }

        def self.parse_to_integer(value)
          return value if value.is_a?(Integer)
          Integer(value, 10) unless value.blank?
        end

        def self.parse_to_bigdecimal(value)
          BigDecimal(value) unless value.blank?
        end

        def self.parse_to_float(value)
          Float(value) unless value.blank?
        end

        def self.parse_to_bool(value)
          if value.blank? && !(value.is_a?(TrueClass) || value.is_a?(FalseClass))
            nil
          else
            (value.is_a?(TrueClass) || value == "true")
          end
        end

        def self.parse_to_date(value)
          return if value.blank?
          value.is_a?(Date) ? value : Date.iso8601(value.dup)
        end

        def self.parse_to_date_time(value)
          value.is_a?(DateTime) ? value : DateTime.deserialize_from_json(value)
        end

        def self.parse_to_hash(value)
          fail "invalid value for hash(): \"#{value}\"" unless value.is_a?(Hash)

          value.is_a?(Hash) ? value : Hash.deserialize_from_json(value)
        end

        def self.parse_array(values, type_in_array)
          fail "invalid value for array(): \"#{values}\"" unless values.is_a?(Array)
          values.map do |item|
            if item.respond_to?(:parse_attrs_to_correct_types)
              item.parse_attrs_to_correct_types
            else
              Sequent::Core::Helpers::StringToValueParsers.for(type_in_array).parse_from_string(item)
            end
          end
        end

        def self.for(klass)
          new(klass)
        end

        def initialize(klass)
          if klass.is_a? Sequent::Core::Helpers::ArrayWithType
            @array_with_type = klass
            @klass = klass.class
          else
            @klass = klass
          end
        end

        def parse_from_string(value)
          parser = PARSERS.fetch(@klass) { |key| fail "Unsupported value type: #{key}" }
          if @array_with_type
            parser.call(value, @array_with_type.item_type)
          else
            parser.call(value)
          end
        end
      end
    end
  end
end
