require 'active_model'
module Sequent
  module Core
    module Helpers
      #
      # Validator for associations. Typically used in Sequent::Core::Command,
      # Sequent::Core::Event and Sequent::Core::ValueObjects.
      #
      # When you define attrs that are also value object or array(..) then this class is
      # automatically used.
      #
      # Example:
      #
      #   class RegisterForTrainingCommand < Sequent::Core::Command
      #     attrs trainee: Person
      #   end
      #
      # This will register :trainee with the AssociationValidator and is equivilant to
      #
      #   validates_with Sequent::Core::AssociationValidator, associations: [:trainee]
      #
      class AssociationValidator < ActiveModel::Validator

        def initialize(options = {})
          super
          raise "Must provide ':associations' to validate" unless options[:associations].present?
        end

        def validate(record)
          associations = options[:associations]
          associations = [associations] unless associations.instance_of?(Array)
          associations.each do |association|
            value = record.instance_variable_get("@#{association.to_s}")
            if value && incorrect_type?(value, record, association)
              record.errors[association] = "is not of type #{describe_type(record.class.types[association])}"
            elsif value && value.is_a?(Array)
              item_type = record.class.type_for(association).item_type
              record.errors[association] = "is invalid" unless validate_all(value, item_type).all?
            else
              record.errors[association] = "is invalid" if value && value.invalid?
            end
          end
        end

        private

        def incorrect_type?(value, record, association)
          return unless record.class.respond_to?(:types)
          type = record.class.types[association]
          if type.respond_to?(:candidate?)
            !type.candidate?(value)
          else
            !value.is_a?(type)
          end
        end

        def validate_all(values, item_type)
          values.map do |value|
            if value.nil?
              false
            elsif value.respond_to?(:valid?)
              value.valid?
            else
              Sequent::Core::Helpers::ValueValidators.for(item_type).valid_value?(value)
            end
          end
        end

        def describe_type(type)
          if type.is_a?(ArrayWithType)
            'array'
          else
            type.to_s
          end
        end
      end
    end
  end
end
