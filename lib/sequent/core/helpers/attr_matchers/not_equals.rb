# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module AttrMatchers
        NotEquals = Struct.new(:expected_value) do
          def matches_attr?(actual_value)
            actual_value != expected_value
          end

          def matcher_description
            "neq(#{ArgumentSerializer.serialize_value(expected_value)})"
          end
        end
      end
    end
  end
end

Sequent::Core::Helpers::AttrMatchers.register_matcher(
  :neq,
  Sequent::Core::Helpers::AttrMatchers::NotEquals,
)
