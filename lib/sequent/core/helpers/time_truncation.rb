# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      #
      # Truncates the times of events to the precision with which they are stored, ActiveSupport's
      # +time_precision+, so an event has the times with which it is loaded or replayed.
      #
      module TimeTruncation
        TIME_TYPES = [Time, DateTime, ActiveSupport::TimeWithZone].freeze

        # The class instance variable that keeps the instance variables of the attributes that can contain times. It is
        # kept on the class itself, so a class that is reloaded in development takes it along.
        TIME_ATTRIBUTES = :@_sequent_time_attributes

        class << self
          ##
          # Truncates the times of the attributes of +object+ in place. Only the attributes whose type can contain
          # times are checked, as declared using +attrs+.
          def truncate_attributes!(object)
            scale = 10**ActiveSupport::JSON::Encoding.time_precision
            time_attributes(object.class).each do |variable|
              value = object.instance_variable_get(variable)
              truncated = truncate(value, scale)
              object.instance_variable_set(variable, truncated) unless truncated.equal?(value)
            end
          end

          ##
          # Returns +value+ with its times truncated to 1 / +scale+ seconds, also those of the value objects and arrays
          # in it. A value that does not change is returned as it is, and a value object or array that changes is
          # copied, so the values of the domain code are not changed.
          def truncate(value, scale)
            case value
            when DateTime then truncate_date_time(value, scale)
            when Time, ActiveSupport::TimeWithZone then truncate_time(value, scale)
            when Array then truncate_array(value, scale)
            else value.class.respond_to?(:types) ? truncate_object(value, scale) : value
            end
          end

          private

          def time_attributes(klass)
            klass.instance_variable_get(TIME_ATTRIBUTES) || klass.instance_variable_set(
              TIME_ATTRIBUTES,
              klass.types.filter_map { |name, type| :"@#{name}" if contains_times?(type, Set.new) }.freeze,
            )
          end

          def contains_times?(type, seen)
            return true if TIME_TYPES.include?(type)
            return contains_times?(type.item_type, seen) if type.is_a?(ArrayWithType)
            return false unless type.respond_to?(:types) && seen.add?(type)

            type.types.each_value.any? { |attribute_type| contains_times?(attribute_type, seen) }
          end

          def truncate_time(time, scale)
            fraction = time.subsec * scale
            fraction.denominator == 1 ? time : time - ((fraction - fraction.floor) / scale)
          end

          def truncate_date_time(date_time, scale)
            fraction = date_time.sec_fraction * scale
            fraction.denominator == 1 ? date_time : date_time - ((fraction - fraction.floor) / scale / 86_400)
          end

          def truncate_array(array, scale)
            copy = nil
            array.each_with_index do |element, index|
              truncated = truncate(element, scale)
              next if truncated.equal?(element)

              copy ||= array.dup
              copy[index] = truncated
            end
            copy || array
          end

          def truncate_object(object, scale)
            copy = nil
            time_attributes(object.class).each do |variable|
              value = object.instance_variable_get(variable)
              truncated = truncate(value, scale)
              next if truncated.equal?(value)

              copy ||= object.dup
              copy.instance_variable_set(variable, truncated)
            end
            copy || object
          end
        end
      end
    end
  end
end
