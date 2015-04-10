require 'active_model'
module Sequent
  module Core
    module Helpers
      #
      # Validator for associations. Typically used in Sequent::Core::Command,
      # Sequent::Core::Event and Sequent::Core::ValueObjects.
      #
      # Example:
      #
      #   class RegisterForTrainingCommand < UpdateCommand
      #     attrs trainee: Person
      #
      #     validates_presence_of :trainee
      #     validates_with Sequent::Core::Helpers::AssociationValidator, associations: [:trainee]
      #
      #   end
      class AssociationValidator < ActiveModel::Validator

        def validate(record)
          associations = options[:associations]
          associations = [associations] unless associations.instance_of?(Array)
          associations.each do |association|
            next unless association # since ruby 2.0...?
            value = record.instance_variable_get("@#{association.to_s}")
            if value && !value.kind_of?(Array) && record.respond_to?(:attributes) && !value.kind_of?(record.attributes[association])
              record.errors[association] = "is not of type #{record.attributes[association]}"
            elsif value && value.kind_of?(Array)
              item_type = record.class.type_for(association).item_type
              record.errors[association] = "is invalid" if value.any? do |v|
                if v.nil?
                  true
                elsif v.respond_to? :valid?
                  not v.valid?
                else
                  not item_type.valid_value?(v)
                end
              end
            else
              record.errors[association] = "is invalid" if value && value.invalid?

            end
          end
        end
      end
    end
  end
end
