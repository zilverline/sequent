module Sequent
  module Migrations
    class Planner
      Plan = Struct.new(:projectors, :migrations) do
        def replay_tables
          migrations.select { |m| m.class == ReplayTable }
        end

        def alter_tables
          migrations.select { |m| m.class == AlterTable }
        end

        def empty?
          migrations.empty?
        end
      end

      attr_reader :versions

      def initialize(versions)
        @versions = versions
      end

      def plan(old, new)
        migrations = versions.slice(*Range.new(old + 1, new).to_a.map(&:to_s))

        Plan.new(
          migrations.yield_self(&method(:select_projectors)),
          migrations
            .yield_self(&method(:create_migrations))
            .yield_self(&method(:remove_redundant_migrations))
        )
      end

      private

      def select_projectors(migrations)
        migrations
          .values
          .flatten
          .select { |v| v.is_a?(Class) && v < Sequent::Projector }.uniq
      end

      def remove_redundant_migrations(migrations)
        redundant_migrations = migrations
                                 .yield_self(&method(:group_identical_migrations))
                                 .yield_self(&method(:select_redundant_migrations))
                                 .yield_self(&method(:remove_redundancy))
                                 .values
                                 .flatten

        (migrations - redundant_migrations)
          .yield_self(&method(:remove_alter_tables_before_replay_table))
      end

      def group_identical_migrations(migrations)
        migrations
          .group_by { |migration| {migration_type: migration.class, record_class: migration.record_class} }
      end

      def select_redundant_migrations(grouped_migrations)
        grouped_migrations.select { |type, ms| type[:migration_type] == ReplayTable && ms.length > 1 }
      end

      def remove_alter_tables_before_replay_table(migrations)
        migrations - migrations
                       .each_with_index
                       .select { |migration, _index| migration.class == AlterTable }
                       .select { |migration, index| migrations
                                                      .slice((index + 1)..-1)
                                                      .find { |m| m.class == ReplayTable && m.record_class == migration.record_class }
                       }.map(&:first)
      end

      def remove_redundancy(grouped_migrations)
        grouped_migrations.reduce({}) { |memo, (key, ms)|
          memo[key] = ms
                        .yield_self(&method(:order_by_version_desc))
                        .slice(1..-1)
          memo
        }
      end

      def order_by_version_desc(migrations)
        migrations.sort_by { |m| m.version.to_i }
          .reverse
      end

      def create_migrations(migrations)
        migrations
          .yield_self(&method(:map_to_migrations))
          .values
          .compact
          .flatten
      end

      def map_to_migrations(migrations)
        migrations.reduce({}) do |memo, (version, _migrations)|
          fail "Declared migrations for version #{version} must be an Array. For example: {'3' => [FooProjector]}" unless _migrations.is_a?(Array)

          memo[version] = _migrations.flat_map do |migration|
            if migration.is_a?(AlterTable)
              alter_table_sql_file_name = "#{Sequent.configuration.migration_sql_files_directory}/#{migration.table_name}_#{version}.sql"
              fail "Missing file #{alter_table_sql_file_name} to apply for version #{version}" unless File.exist?(alter_table_sql_file_name)
              migration.copy(version)
            else
              migration.is_a?(Sequent::Projector)
              migration.managed_tables.map { |table| ReplayTable.create(table, version) }
            end
          end

          memo
        end
      end
    end
  end
end
