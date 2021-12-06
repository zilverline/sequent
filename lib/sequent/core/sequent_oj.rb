# frozen_string_literal: true

require 'oj'

module Sequent
  module Core
    # small wrapper class to centralize oj and its settings.
    class Oj
      ::Oj.default_options = {
        bigdecimal_as_decimal: false,
        mode: :rails,
      }

      def self.strict_load(json)
        ::Oj.strict_load(json, {})
      end

      def self.dump(obj)
        ::Oj.dump(obj)
      end
    end
  end
end
