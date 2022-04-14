# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        IsA = Struct.new(:expected_class) do
          def matches_message?(message)
            message.is_a?(expected_class)
          end

          def matcher_description
            "is_a(#{expected_class})"
          end
        end
      end
    end
  end
end

Sequent::Core::Helpers::MessageMatchers.register_matcher(
  :is_a,
  Sequent::Core::Helpers::MessageMatchers::IsA,
)
