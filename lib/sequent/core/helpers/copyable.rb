module Sequent
  module Core
    module Helpers
      module Copyable
        def copy(attrs = {})
          the_copy = Marshal.load(Marshal.dump(self))
          attrs.each do |name, value|
            the_copy.send("#{name}=", value)
          end
          the_copy
        end

      end
    end
  end
end

