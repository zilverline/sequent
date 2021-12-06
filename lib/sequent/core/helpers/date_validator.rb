# frozen_string_literal: true

require 'active_model'
require_relative 'value_validators'

module Sequent
  module Core
    module Helpers
      # Validates Dates
      # Automatically included when using a
      #
      #   attrs value: Date
      class DateValidator < ActiveModel::EachValidator
        def validate_each(subject, attribute, value)
          unless Sequent::Core::Helpers::ValueValidators.for(Date).valid_value?(value)
            subject.errors.add attribute,
                               :invalid_date
          end
        end
      end
    end
  end
end
