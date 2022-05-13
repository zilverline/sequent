# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        Any = Struct.new(:opts) do
          include ExceptOpt

          def matches_message?(message)
            return false if excluded?(message)

            true
          end

          def to_s
            "any#{matcher_arguments}"
          end

          private

          def matcher_arguments
            "(except: #{except})" if except
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
