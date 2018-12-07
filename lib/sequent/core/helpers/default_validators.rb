require_relative 'string_validator'
require_relative 'boolean_validator'
require_relative 'date_time_validator'
require_relative 'date_validator'

module Sequent
  module Core
    module Helpers
      class DefaultValidators
        VALIDATORS = {
          Integer => ->(klass, field) do
            klass.validates_numericality_of field, only_integer: true, allow_nil: true, allow_blank: true
          end,
          Date => ->(klass, field) do
            klass.validates field, "sequent::Core::Helpers::Date" => true
          end,
          DateTime => ->(klass, field) do
            klass.validates field, "sequent::Core::Helpers::DateTime" => true
          end,
          Boolean => -> (klass, field) do
            klass.validates field, "sequent::Core::Helpers::Boolean" => true
          end,
          String => -> (klass, field) do
            klass.validates field, "sequent::Core::Helpers::String" => true
          end
        }

        def self.for(type)
          new(type)
        end

        def initialize(type)
          @type = type
        end

        def add_validations_for(klass, field)
          validator = VALIDATORS[@type]
          validator.call(klass, field) if validator
        end
      end
    end
  end
end
