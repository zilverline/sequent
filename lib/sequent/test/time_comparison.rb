# frozen_string_literal: true

warn '[DEPRECATED] sequent/test/time_comparison monkey-patches standard time related classes'

module Sequent
  module Test
    module DateTimePatches
      module Normalize
        def normalize
          in_time_zone('UTC')
        end
      end

      module Compare
        alias :'___<=>' :'<=>' # rubocop:disable Style/Alias,Naming/MethodName

        # omit nsec in datetime comparisons
        def <=>(other)
          if other.is_a?(DateTimePatches::Normalize)
            precision = Sequent.configuration.time_precision
            return normalize.iso8601(precision) <=> other.normalize.iso8601(precision)
          end
          public_send(:'___<=>', other)
        end
      end
    end
  end
end

class Time
  prepend Sequent::Test::DateTimePatches::Normalize
  prepend Sequent::Test::DateTimePatches::Compare
end

class DateTime
  prepend Sequent::Test::DateTimePatches::Normalize
  prepend Sequent::Test::DateTimePatches::Compare
end

module ActiveSupport
  class TimeWithZone
    prepend Sequent::Test::DateTimePatches::Normalize
  end
end
