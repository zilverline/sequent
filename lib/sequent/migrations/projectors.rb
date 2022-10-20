# frozen_string_literal: true

require_relative 'planner'
module Sequent
  module Migrations
    class Projectors
      def self.versions
        fail "Define your own #{name} class that extends this class and implements this method"
      end

      def self.version
        fail "Define your own #{name} class that extends this class and implements this method"
      end

      def self.migrations_between(old, new)
        Planner.new(versions).plan(old, new)
      end
    end
  end
end
