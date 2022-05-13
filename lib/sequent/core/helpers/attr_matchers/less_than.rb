# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module AttrMatchers
        LessThan = Struct.new(:expected_value) do
          def matches_attr?(actual_value)
            actual_value < expected_value
          end

          def to_s
            "lt(#{ArgumentSerializer.serialize_value(expected_value)})"
          end
        end
      end
    end
  end
end

Sequent::Core::Helpers::AttrMatchers.register_matcher(
  :lt,
  Sequent::Core::Helpers::AttrMatchers::LessThan,
)
