require 'active_model'

module Sequent
  module Core
    module Helpers
      class DateValidator < ActiveModel::EachValidator
        def validate_each(subject, attribute, value)
          return if value.nil?
          return if value.is_a?(Date)
          begin
            Date.strptime(value, "%d-%m-%Y")
          rescue
            subject.errors.add attribute, :invalid_date
          end
        end
      end
    end
  end
end
