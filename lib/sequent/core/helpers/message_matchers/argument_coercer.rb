# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        class ArgumentCoercer
          class << self
            def coerce_argument(arg)
              fail ArgumentError, 'Cannot coerce nil argument' if arg.nil?

              return MessageMatchers::InstanceOf.new(arg) if [Class, Module].include?(arg.class)
              return arg if arg.respond_to?(:matches_message?)

              fail ArgumentError,
                   "Can't coerce argument '#{arg}'; " \
                   'must be either a Class, Module or message matcher (respond to :matches_message?)'
            end
          end
        end
      end
    end
  end
end
