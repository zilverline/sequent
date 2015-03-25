module Sequent
  module Core
    module Helpers
      #
      # Parses the strings "true", "false" and nil to true, false, false
      #
      # You need to include this module explicitly when working with booleans.
      #
      # Example:
      #
      #   class Registration < Sequent::Core::ValueObject
      #     include Sequent::Core::Helpers::BooleanSupport
      #     attrs accepted_terms: Boolean
      #   end
      module BooleanSupport

        def self.included(base)
          base.before_validation :parse_booleans
        end

        def parse_booleans
          attributes.each do |name, type|
            if type == Boolean
              raw_value = self.instance_variable_get("@#{name}")
              return if raw_value.kind_of? Boolean
              return unless [nil, "true", "false"].include?(raw_value)
              bool_value = raw_value == "true" ? true : false
              self.instance_variable_set "@#{name}", bool_value
            end
          end
        end
      end

    end
  end
end
