module Sequent
  module Core
    module Helpers
      # Looks like Copyable but changes this instance
      #
      #   ben = Person.new(name: 'Ben').merge!(name: 'Ben Vonk')
      #
      module Mergable

        def merge!(attrs = {})
          warn "[DEPRECATION] `merge!` is deprecated. Please use `copy` instead. This method will no longer be included in the next version of Sequent. You can still use it but you will have to include the module `Sequent::Core::Helpers::Mergable` yourself."
          attrs.each do |name, value|
            self.send("#{name}=", value)
          end
          self
        end

      end
    end
  end
end

