# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      #
      # You typically do not need to include this module in your classes. If you extend from
      # Sequent::Core::ValueObject, Sequent::Core::Event or Sequent::Core::BaseCommand you will
      # get this functionality for free.
      #
      # Two objects are equal when they are of the same class and the values of their attributes are strictly equal.
      # The values are compared as they are kept, not through the readers. See +EqualSupport.strictly_equal?+.
      #
      module EqualSupport
        ##
        # Compares two values without converting either: they must be of the same class (a +Time+ and an
        # +ActiveSupport::TimeWithZone+ count as one), so 1 is not 1.0 and a +HashWithIndifferentAccess+ is not a
        # +Hash+. Times must be the same instant at full precision. Hashes and arrays are compared recursively; the
        # order of the keys of a hash does not matter.
        def self.strictly_equal?(value, other)
          if time?(value) && time?(other)
            value.to_r == other.to_r
          elsif !value.instance_of?(other.class)
            false
          elsif value.is_a?(Hash)
            value.size == other.size && value.all? { |key, v| other.key?(key) && strictly_equal?(v, other[key]) }
          elsif value.is_a?(Array)
            value.size == other.size && value.zip(other).all? { |v, o| strictly_equal?(v, o) }
          else
            value == other
          end
        end

        def self.time?(value)
          value.instance_of?(Time) || value.instance_of?(ActiveSupport::TimeWithZone)
        end

        private_class_method :time?

        def ==(other)
          return false unless other.instance_of?(self.class)

          self.class.types.each_key.all? do |name|
            EqualSupport.strictly_equal?(
              instance_variable_get(:"@#{name}"),
              other.instance_variable_get(:"@#{name}"),
            )
          end
        end

        def hash
          [self.class, *self.class.types.each_key.map { |name| instance_variable_get(:"@#{name}") }].hash
        end

        def eql?(other)
          self == other
        end
      end
    end
  end
end
