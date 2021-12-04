# frozen_string_literal: true

require 'active_model'
require_relative 'value_validators'

module Sequent
  module Core
    module Helpers
      # Validates String's
      # Automatically included when using a
      #
      #   attrs value: String
      #
      # Basically all ruby String are valid Strings.
      #
      # For now we do fail when value is not a String
      # or contains a any chars defined in ValueValidators::INVALID_CHARS
      #
      class StringValidator < ActiveModel::EachValidator
        def validate_each(subject, attribute, value)
          unless Sequent::Core::Helpers::ValueValidators.for(String).valid_value?(value)
            subject.errors.add attribute,
                               :invalid_string
          end
        end
      end
    end
  end
end
