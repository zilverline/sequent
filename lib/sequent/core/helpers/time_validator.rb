# frozen_string_literal: true

require 'active_model'

module Sequent
  module Core
    module Helpers
      # Validates Time
      # Automatically included when using a
      #
      #   attrs value: Time
      class TimeValidator < ActiveModel::EachValidator
        def validate_each(subject, attribute, value)
          return if value.is_a?(Time)

          Time.deserialize_from_json(value)
        rescue StandardError
          subject.errors.add attribute, :invalid_time
        end
      end
    end
  end
end
