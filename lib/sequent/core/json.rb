# frozen_string_literal: true

require 'json'
require 'active_support'
require 'active_support/core_ext/object/json'

module Sequent
  module Core
    module Json
      # An already generated JSON string that +dump+ embeds as it is. The +as_json+ of the +JSON::Fragment+ itself
      # would turn it into a hash.
      class Fragment < ::JSON::Fragment
        def as_json(*) = self
      end

      def self.dump(obj)
        ::JSON.generate(obj.as_json)
      end

      def self.strict_load(json)
        ::JSON.parse(json)
      end
    end
  end
end
