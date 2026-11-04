# frozen_string_literal: true

require_relative 'json'

module Sequent
  module Core
    # @deprecated Use +Sequent::Core::Json+ instead.
    class Oj
      def self.strict_load(json)
        warn_deprecated
        Json.strict_load(json)
      end

      def self.dump(obj)
        warn_deprecated
        Json.dump(obj)
      end

      def self.warn_deprecated
        return if @warned_deprecated

        @warned_deprecated = true
        warn '[DEPRECATED] Sequent::Core::Oj no longer uses Oj, use Sequent::Core::Json instead'
      end
      private_class_method :warn_deprecated
    end
  end
end
