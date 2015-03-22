module Sequent
  module Core
    module Helpers

      module StringSupport
        def to_s
          s = "#{self.class.name}: "
          self.instance_variables.each do |name|
            value = self.instance_variable_get("#{name}")
            s += "#{name}=[#{value}], "
          end
          "{" + s.chomp(", ") + "}"
        end
      end

    end
  end
end
