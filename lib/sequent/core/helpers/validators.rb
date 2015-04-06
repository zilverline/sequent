require 'active_model'

module Sequent
  module Core
    module Helpers
      class DateValidator < ActiveModel::EachValidator
        def validate_each(subject, attribute, value)
          return if value.nil?
          return if value.is_a?(Date)
          begin
            Date.parse_from_string(value)
          rescue
            subject.errors.add attribute, :invalid_date
          end
        end
      end

      class DateTimeValidator < ActiveModel::EachValidator
        def validate_each(subject, attribute, value)
          return if value.is_a?(DateTime)
          begin
            DateTime.deserialize_from_json(value)
          rescue
            subject.errors.add attribute, :invalid_date_time
          end
        end
      end
    end
  end
end
