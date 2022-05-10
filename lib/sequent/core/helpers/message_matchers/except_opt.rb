# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        module ExceptOpt
          private

          def excluded?(message)
            [except]
              .flatten
              .compact
              .any? { |x| message.is_a?(x) }
          end

          def except
            opts.try(:[], :except)
          end
        end
      end
    end
  end
end
