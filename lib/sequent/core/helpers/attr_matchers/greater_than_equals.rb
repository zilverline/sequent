# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module AttrMatchers
        GreaterThanEquals = Struct.new(:expected_value) do
          def matches_attr?(actual_value)
            actual_value >= expected_value
          end

          def to_s
            "gte(#{ArgumentSerializer.serialize_value(expected_value)})"
          end
        end
      end
    end
  end
end

Sequent::Core::Helpers::AttrMatchers.register_matcher(
  :gte,
  Sequent::Core::Helpers::AttrMatchers::GreaterThanEquals,
)
