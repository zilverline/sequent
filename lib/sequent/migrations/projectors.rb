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

      def self.activate_current_configuration!
        current_version = Versions.current_version
        if version != current_version
          fail ArgumentError,
               "new version [#{version}] must be the same as current view schema version [#{current_version}]"
        end

        Sequent::Core::Projectors.register_active_projectors!(
          Sequent::Core::Migratable.projectors,
          version,
        )
      end
    end
  end
end
