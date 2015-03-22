require 'securerandom'

module Sequent
  module Core
    module Helpers
      module UuidHelper

        def new_uuid
          SecureRandom.uuid
        end

        module_function :new_uuid

      end
    end
  end
end
