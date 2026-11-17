# frozen_string_literal: true

require 'json'
require 'active_support'
require 'active_support/core_ext/object/json'

module Sequent
  module Core
    module Json
      def self.dump(obj)
        ::JSON.generate(obj.as_json)
      end

      def self.strict_load(json)
        ::JSON.parse(json)
      end
    end
  end
end
