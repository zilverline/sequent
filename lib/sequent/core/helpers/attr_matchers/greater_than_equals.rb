# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module AttrMatchers
        GreaterThanEquals = Struct.new(:expected_value) do
          def matches_attr?(actual_value)
            actual_value >= expected_value
          end

          def matcher_description
            "greater_than_equals(#{expected_value})"
          end
        end
      end
    end
  end
end

Sequent::Core::Helpers::AttrMatchers.register_matcher(
  :greater_than_equals,
  Sequent::Core::Helpers::AttrMatchers::GreaterThanEquals,
)
