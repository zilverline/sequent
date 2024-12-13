# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      #
      # You typically do not need to include this module in your classes. If you extend from
      # Sequent::Core::ValueObject, Sequent::Core::Event or Sequent::Core::BaseCommand you will
      # get this functionality for free.
      #
      module EqualSupport
        def ==(other)
          return false if other.nil?
          return false if self.class != other.class

          self.class.types.each_key do |name|
            self_value = send(name)
            other_value = other.send(name)
            if self_value.class == DateTime && other_value.class == DateTime
              # we don't care about milliseconds. If you know a better way of checking for equality please improve.
              return false unless self_value.iso8601 == other_value.iso8601
            else
              return false unless self_value == other_value
            end
          end
          true
        end

        def hash
          hash = 17
          self.class.types.each_key do |name|
            hash = (hash * 31) + send(name).hash
          end
          hash
        end

        def eql?(other)
          self == other
        end
      end
    end
  end
end
