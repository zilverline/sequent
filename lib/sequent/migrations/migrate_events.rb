##
# When you need to upgrade the event store based on information of the previous schema version
# this is the place you need to implement a migration.
# Examples are: corrupt events (due to insufficient testing for instance...)
# or adding extra events to the event stream if a new concept is introduced.
#
# To implement a migration you should create a class according to the following contract:
# module Database
#   class MigrateToVersionXXX
#     def initialize(env)
#       @env = env
#     end
#
#     def migrate
#       # your migration code here...
#     end
#   end
# end
#
module Sequent
  module Migrations
    class MigrateEvents

      ##
      # @param env The string representing the current environment. E.g. "development", "production"
      def initialize(env)
        @env = env
      end

      ##
      #
      # @param current_version The current version of the application. E.g. 10
      # @param new_version The version to migrate to. E.g. 11
      # @param &after_migration_block an optional block (with the current upgrade version as param) to run after the migrations run. E.g. close resources
      #
      def execute_migrations(current_version, new_version, &after_migration_block)
        if current_version != new_version and current_version > 0
          ((current_version + 1)..new_version).each do |upgrade_to_version|
            migration_class = begin
                                Class.const_get("Database::MigrateToVersion#{upgrade_to_version}")
                              rescue NameError
                                nil
                              end
            if migration_class
              begin
                migration_class.new(@env).migrate
              ensure
                yield(upgrade_to_version) if block_given?
              end
            end
          end
        end
      end
    end
  end
end
