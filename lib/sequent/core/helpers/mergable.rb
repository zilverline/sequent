module Sequent
  module Core
    module Helpers
      # Looks like Copyable but changes this instance
      #
      #   ben = Person.new(name: 'Ben').merge!(name: 'Ben Vonk')
      #
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

