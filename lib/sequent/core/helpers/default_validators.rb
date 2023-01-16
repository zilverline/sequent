# frozen_string_literal: true

require_relative 'string_validator'
require_relative 'boolean_validator'
require_relative 'date_time_validator'
require_relative 'date_validator'
require_relative 'secret'

module Sequent
  module Core
    module Helpers
      class DefaultValidators
        VALIDATORS = {
          Integer => ->(klass, field) do
            klass.validates_numericality_of field, only_integer: true, allow_nil: true, allow_blank: true
          end,
          Date => ->(klass, field) do
            klass.validates field, 'sequent::Core::Helpers::Date' => true
          end,
          Time => ->(klass, field) do
            klass.validates field, 'sequent::Core::Helpers::Time' => true
          end,
          DateTime => ->(klass, field) do
            klass.validates field, 'sequent::Core::Helpers::DateTime' => true
          end,
          Boolean => ->(klass, field) do
            klass.validates field, 'sequent::Core::Helpers::Boolean' => true
          end,
          String => ->(klass, field) do
            klass.validates field, 'sequent::Core::Helpers::String' => true
          end,
          Sequent::Core::Helpers::Secret => ->(klass, field) do
            klass.after_validation do |object|
              if object.errors&.any?
                object.send("#{field}=", nil)
              else
                raw_value = object.send(field)
                object.send("#{field}=", Sequent::Secret.new(raw_value)) if raw_value
              end
            end
          end,
        }.freeze

        def self.for(type)
          new(type)
        end

        def initialize(type)
          @type = type
        end

        def add_validations_for(klass, field)
          validator = VALIDATORS[@type]
          validator&.call(klass, field)
        end
      end
    end
  end
end
