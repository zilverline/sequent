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
          return false if other == nil
          return false if self.class != other.class
          self.class.types.each do |name, _|
            self_value = self.send(name)
            other_value = other.send(name)
            if self_value.class == DateTime && other_value.class == DateTime
              # Compare using time precision defined.
              return false unless (self_value.iso8601(ActiveSupport::JSON::Encoding.time_precision) == other_value.iso8601(ActiveSupport::JSON::Encoding.time_precision))
            else
              return false unless (self_value == other_value)
            end
          end
          true
        end

        def hash
          hash = 17
          self.class.types.each do |name, _|
            hash = hash * 31 + self.send(name).hash
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
