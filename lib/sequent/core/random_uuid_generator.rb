# frozen_string_literal: true

module Sequent
  module Core
    module RandomUuidGenerator
      def self.uuid
        SecureRandom.uuid
      end
    end
  end
end
