# frozen_string_literal: true

require_relative 'class_equals'
require_relative 'is_a'

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        module DSL
          module ClassMethods
            def is_a(expected_class)
              IsA.new(expected_class: expected_class)
            end
          end

          def self.included(host_class)
            host_class.extend(ClassMethods)
          end
        end
      end
    end
  end
end
