module Sequent
  module Core
    module Helpers
      class DefaultValidators
        VALIDATORS = {
          Integer => ->(klass, field) { klass.validates_numericality_of field, only_integer: true, allow_nil: true, allow_blank: true },
          Date => ->(klass, field) { klass.validates field, "sequent::Core::Helpers::Date" => true },
          DateTime => ->(klass, field) { klass.validates field, "sequent::Core::Helpers::DateTime" => true }
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
