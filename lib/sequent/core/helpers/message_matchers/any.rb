# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        class Any
          def matches_message?(_message)
            true
          end

          def matcher_description
            'any'
          end
        end
      end
    end
  end
end

Sequent::Core::Helpers::MessageMatchers.register_matcher(
  :any,
  Sequent::Core::Helpers::MessageMatchers::Any,
)
