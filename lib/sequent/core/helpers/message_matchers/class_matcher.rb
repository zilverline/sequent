# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        ClassMatcher = Struct.new(:expected_class, keyword_init: true) do
          def matches_message?(message)
            message.is_a?(expected_class)
          end
        end
      end
    end
  end
end
