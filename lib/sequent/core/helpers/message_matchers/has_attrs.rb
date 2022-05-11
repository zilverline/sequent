# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        HasAttrs = Struct.new(:message_matcher, :expected_attrs) do
          def initialize(message_matcher, expected_attrs)
            super

            fail ArgumentError, 'Missing required message matcher' if message_matcher.nil?
            fail ArgumentError, 'Missing required expected attrs' if expected_attrs.blank?

            self.message_matcher = ArgumentCoercer.coerce_argument(message_matcher)
          end

          def matches_message?(message)
            message_matcher.matches_message?(message) &&
              matches_attrs?(message, expected_attrs)
          end

          def matcher_description
            "has_attrs(#{ArgumentSerializer.serialize_value(message_matcher)}, #{matcher_arguments})"
          end

          private

          def matches_attrs?(message, expected_attrs, path = [])
            expected_attrs.all? do |(name, expected_value)|
              matches_attr?(message, expected_value, path.dup.push(name))
            end
          end

          def matches_attr?(message, expected_value, path)
            return matches_attrs?(message, expected_value, path) if expected_value.is_a?(Hash)

            expected_value = AttrMatchers::Equals.new(expected_value) unless expected_value.respond_to?(:matches_attr?)
            value = path.reduce(message) { |memo, p| memo.public_send(p) }

            expected_value.matches_attr?(value)
          end

          def matcher_arguments
            expected_attrs
              .map do |(name, value)|
                "#{name}: #{ArgumentSerializer.serialize_value(value)}"
              end
              .join(', ')
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
