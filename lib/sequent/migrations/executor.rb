# frozen_string_literal: true

require_relative 'sql'

module Sequent
  module Migrations
    ##
    # The executor is the implementation of the 3-phase deploy in Sequent.
    # is responsible for executing the `Planner::Plan`.
    #
    class Executor
      include Sql

      def execute_online(plan)
        plan.replay_tables.each do |migration|
          table = migration.record_class
          sql_file = "#{Sequent.configuration.migration_sql_files_directory}/#{table.table_name}.sql"
          statements = sql_file_to_statements(sql_file) { |raw_sql| raw_sql.gsub('%SUFFIX%', "_#{migration.version}") }
          statements.each(&method(:exec_sql))
          new_table_name = "#{table.table_name}_#{migration.version}"
          set_table_name(table, new_table_name)
        end
      end

      def create_indexes_after_execute_online(plan)
        plan.replay_tables.each do |migration|
          table = migration.record_class
          original_table_name = table.table_name.gsub("_#{migration.version}", '')
          indexes_file_name = <<~EOS.chomp
            #{Sequent.configuration.migration_sql_files_directory}/#{original_table_name}.indexes.sql
          EOS
          next unless File.exist?(indexes_file_name)

          statements = sql_file_to_statements(indexes_file_name) do |raw_sql|
            raw_sql.gsub('%SUFFIX%', "_#{migration.version}")
          end
          statements.each(&method(:exec_sql))
        end
      end

      def execute_offline(plan, current_version)
        plan.replay_tables.each do |migration|
          table = migration.record_class
          new_table_name = table.table_name.gsub("_#{migration.version}", '')
          # 2 Rename old table
          exec_sql("ALTER TABLE IF EXISTS #{new_table_name} RENAME TO #{new_table_name}_#{current_version}")
          # 3 Rename new table
          exec_sql("ALTER TABLE #{table.table_name} RENAME TO #{new_table_name}")
          # Use new table from now on
          set_table_name(table, new_table_name)
        end

        plan.alter_tables.each do |migration|
          table = migration.record_class
          sql_file = <<~EOS.chomp
            #{Sequent.configuration.migration_sql_files_directory}/#{table.table_name}_#{migration.version}.sql
          EOS
          statements = sql_file_to_statements(sql_file)
          statements.each(&method(:exec_sql))
        end
      end

      def reset_table_names(plan)
        plan.replay_tables.each do |migration|
          table = migration.record_class
          new_table_name = table.table_name.gsub("_#{migration.version}", '')
          set_table_name(table, new_table_name)
        end
      end

      def set_table_names_to_new_version(plan)
        plan.replay_tables.each do |migration|
          table = migration.record_class
          next if table.table_name.end_with?("_#{migration.version}")

          new_table_name = "#{table.table_name}_#{migration.version}"
          set_table_name(table, new_table_name)

          unless table.table_exists?
            fail MigrationError,
                 "Table #{table.table_name} does not exist. Did you run ViewSchema.migrate_online first?"
          end
        end
      end

      private

      def set_table_name(table, table_name)
        [table, *table.descendants].each do |klass|
          klass.table_name = table_name
          klass.reset_column_information
        end
      end
    end
  end
end
