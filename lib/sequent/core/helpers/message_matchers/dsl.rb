# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        module DSL
          def register_matcher(name, matcher_class)
            if respond_to?(name)
              fail ArgumentError, "Cannot register message matcher because it would overwrite existing method '#{name}'"
            end

            define_method(name) do |*expected|
              matcher_class.new(*expected)
            end
          end
        end

        extend DSL
      end
    end
  end
end
