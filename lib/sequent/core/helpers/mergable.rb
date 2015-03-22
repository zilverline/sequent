module Sequent
  module Core
    module Helpers

      module Mergable

        def merge!(attrs = {})
          attrs.each do |name, value|
            self.send("#{name}=", value)
          end
          self
        end

      end

    end
  end
end

