require 'active_model'

module Sequent
  module Core
    module Helpers
      module TypeConversionSupport
        def parse_attrs_to_correct_types!
          attributes.each do |name, type|
            raw_value = self.instance_variable_get("@#{name}")
            next if raw_value.nil?
            if raw_value.respond_to?(:parse_attrs_to_correct_types!)
              raw_value.parse_attrs_to_correct_types!
            else
              parsed_value = type.parse_from_string(raw_value)
              self.instance_variable_set("@#{name}", parsed_value)
            end
          end
          self
        end
      end
    end
  end
end
