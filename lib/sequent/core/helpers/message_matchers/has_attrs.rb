# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        HasAttrs = Struct.new(:expected_attrs) do
          def initialize(expected_attrs)
            super

            fail ArgumentError, 'Missing required expected attrs' if expected_attrs.blank?
          end

          def matches_message?(message)
            expected_attrs.all? do |(name, value)|
              if value.respond_to?(:matches_attr?)
                value.matches_attr?(message.attributes[name])
              else
                message.attributes[name] == value
              end
            end
          end

          def matcher_description
            "has_attrs(#{matcher_arguments})"
          end

          private

          def matcher_arguments
            expected_attrs
              .map do |(name, value)|
                "#{name}: #{serialize_value(value)}"
              end
              .join(', ')
          end

          def serialize_value(value)
            return value unless value.is_a?(String)

            "'#{value}'"
          end
        end
      end
    end
  end
end

Sequent::Core::Helpers::MessageMatchers.register_matcher(
  :has_attrs,
  Sequent::Core::Helpers::MessageMatchers::HasAttrs,
)
