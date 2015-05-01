require 'active_model'
require_relative 'helpers/string_support'
require_relative 'helpers/equal_support'
require_relative 'helpers/copyable'
require_relative 'helpers/attribute_support'
require_relative 'helpers/param_support'

module Sequent

  module Core
    #
    # ValueObject is a container for data that belongs together but requires no identity
    #
    # If something requires identity is up to you to decide. An example in for instance
    # the invoicing domain could be a person's Address.
    #
    #   class Address < Sequent::Core::ValueObject
    #     attrs street: String, city: String, country: Country
    #   end
    #
    # A ValueObject is equal to another ValueObject if and only if all +attrs+ are equal.
    #
    # You can copy a valueobject as follows:
    #
    #   new_address = address.copy(street: "New Street")
    #
    # This a deep clone of the address with the street attribute containing "New Street"
    class ValueObject
      include Sequent::Core::Helpers::StringSupport,
              Sequent::Core::Helpers::EqualSupport,
              Sequent::Core::Helpers::Copyable,
              Sequent::Core::Helpers::AttributeSupport,
              Sequent::Core::Helpers::ParamSupport,
              ActiveModel::Validations
      include Sequent::Core::Helpers::TypeConversionSupport

      def initialize(args = {})
        update_all_attributes args
      end

    end

  end
end

