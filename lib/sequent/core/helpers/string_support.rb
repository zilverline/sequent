# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      #
      # You typically do not need to include this module in your classes. If you extend from
      # Sequent::Core::ValueObject, Sequent::Core::Event or Sequent::Core::BaseCommand you will
      # get this functionality for free.
      #
      module StringSupport
        def to_s
          s = "#{self.class.name}: "
          instance_variables.each do |name|
            value = instance_variable_get(name.to_s)
            s += "#{name}=[#{value}], "
          end
          "{#{s.chomp(', ')}}"
        end
      end
    end
  end
end
