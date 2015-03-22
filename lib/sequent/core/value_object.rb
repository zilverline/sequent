require 'active_model'
require_relative 'helpers/string_support'
require_relative 'helpers/equal_support'
require_relative 'helpers/copyable'
require_relative 'helpers/attribute_support'
require_relative 'helpers/param_support'

module Sequent

  module Core
    class ValueObject
      include Sequent::Core::Helpers::StringSupport,
              Sequent::Core::Helpers::EqualSupport,
              Sequent::Core::Helpers::Copyable,
              Sequent::Core::Helpers::AttributeSupport,
              Sequent::Core::Helpers::ParamSupport,
              ActiveModel::Serializers::JSON,
              ActiveModel::Validations

      self.include_root_in_json=false

      def initialize(args = {})
        @errors = ActiveModel::Errors.new(self)
        update_all_attributes args
      end

    end

  end
end

