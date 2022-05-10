# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        class ArgumentSerializer
          class << self
            def serialize_value(value)
              return value unless value.is_a?(String)

              %("#{value}")
            end
          end
        end
      end
    end
  end
end
