# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        IsA = Struct.new(:expected_class, :opts) do
          def matches_message?(message)
            message.is_a?(expected_class) unless excluded(message)
          end

          def matcher_description
            "is_a(#{matcher_arguments})"
          end

          private

          def excluded(message)
            return false unless except

            [except]
              .flatten
              .any? { |x| message.is_a?(x) }
          end

          def except
            opts.try(:[], :except)
          end

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
