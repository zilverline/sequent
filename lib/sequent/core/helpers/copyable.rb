# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      # Make a deep clone of an object that include AttributeSupport
      #
      #   person = Person.new(name: 'Ben').copy(name: 'Kim')
      #
      # You typically do not need to include this module in your classes. If you extend from
      # Sequent::Core::ValueObject, Sequent::Core::Event or Sequent::Core::BaseCommand you will
      # get this functionality for free.
      #
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
