# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module MessageMatchers
        InstanceOf = Struct.new(:expected_class) do
          def matches_message?(message)
            message.instance_of?(expected_class)
          end

          def to_s
            expected_class
          end
        end
      end
    end
  end
end

Sequent::Core::Helpers::MessageMatchers.register_matcher(
  :instance_of,
  Sequent::Core::Helpers::MessageMatchers::InstanceOf,
)
