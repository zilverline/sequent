# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module AttrMatchers
        class ArgumentSerializer
          class << self
            def serialize_value(value)
              return value.to_s if value.respond_to?(:matches_attr?)
              return %("#{value}") if value.is_a?(String)

              value
            end
          end
        end
      end
    end
  end
end
