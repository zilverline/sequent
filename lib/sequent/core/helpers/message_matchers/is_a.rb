# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        IsA = Struct.new(:expected_class, :opts) do
          include ExceptOpt

          def matches_message?(message)
            message.is_a?(expected_class) unless excluded?(message)
          end

          def to_s
            "is_a(#{matcher_arguments})"
          end

          private

          def matcher_arguments
            arguments = expected_class.to_s
            arguments += ", except: #{except}" if except
            arguments
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
