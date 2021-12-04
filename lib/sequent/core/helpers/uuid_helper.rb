# frozen_string_literal: true

require 'securerandom'

module Sequent
  module Core
    module Helpers
      module UuidHelper
        def new_uuid
          warn <<~EOS
            DEPRECATION WARNING: Sequent::Core::Helpers::UuidHelper.new_uuid is deprecated. Use Sequent.new_uuid instead
          EOS
          Sequent.new_uuid
        end

        module_function :new_uuid
      end
    end
  end
end
