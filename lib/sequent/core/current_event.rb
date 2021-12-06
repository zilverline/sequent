# frozen_string_literal: true

module Sequent
  module Core
    class CurrentEvent
      def self.current=(event)
        Thread.current[:sequent_current_event] = event
      end

      def self.current
        Thread.current[:sequent_current_event]
      end
    end
  end
end
