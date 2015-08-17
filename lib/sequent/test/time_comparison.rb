module Sequent
  module Test
    module DateTimePatches
      module Normalize
        def normalize
          in_time_zone("UTC")
        end
      end

      module Compare
        alias_method :'___<=>', :<=>

        # omit nsec in datetime comparisons
        def <=>(other)
          if other && other.is_a?(DateTimePatches::Normalize)
            result = normalize.iso8601 <=> other.normalize.iso8601
            return result unless result == 0
            # use usec here, which *truncates* the nsec (ie. like Postgres)
            return normalize.usec <=> other.normalize.usec
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

class ActiveSupport::TimeWithZone
  prepend Sequent::Test::DateTimePatches::Normalize
end
