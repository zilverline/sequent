# frozen_string_literal: true

require 'active_model'
require_relative 'value_validators'

module Sequent
  module Core
    module Helpers
      # Validates Boolean's
      # Automatically included when using a
      #
      #   attrs value: Boolean
      #
      # The values:
      #
      # `true`, `false`, `'true'`, `'false'`, `nil`, and `blank?`
      #
      # are considered valid Booleans.
      #
      # They will be converted to `true`, `false` or `nil`
      class BooleanValidator < ActiveModel::EachValidator
        def validate_each(subject, attribute, value)
          unless Sequent::Core::Helpers::ValueValidators.for(Boolean).valid_value?(value)
            subject.errors.add attribute,
                               :invalid_boolean
          end
        end
      end
    end
  end
end
