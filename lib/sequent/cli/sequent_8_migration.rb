# frozen_string_literal: true

module Sequent
  module Cli
    class Sequent8Migration
      class Stop < StandardError; end

      def initialize(prompt)
        @prompt = prompt
      end

      # @raise Gem::MissingSpecError
      def execute
        print_introduction
        abort_if_no('Do you wish to start the migration?')
        copy_schema_files
        abort_if_no('Do you which to continue?')
        stop_application
        migrate_data
        prompt.ask('Press <enter> if the migration is done and you checked the results?')
        migrated = commit_or_rollback

        if migrated
          prompt.say <<~EOS

            Step 5. Deploy your Sequent 8 based application and start it.

            Congratulations! You are now running your application on Sequent 8!
          EOS
        else
          prompt.say <<~EOS

            We are sorry the migration did not succeed. If you think this is a bug in Sequent don't hesitate to reach
            out and submit an issue on Github: https://github.com/zilverline/sequent.

            Don't forget to start your application again!
          EOS
        end
      end

      private

      attr_reader :prompt

      def print_introduction
        prompt.say <<~EOS
          This script will guide you through upgrading your Sequent application to Sequent 8.

          The Sequent 8 database has been further optimized for disk usage and
          performance. In addition it supports partitioning the tables for aggregates,
          commands, and events, making it easier to manage the database (VACUUM,
          CLUSTER) since these can work on the smaller partition tables.

          It is highly recommended to test this upgrade on a copy of your production database first.

          This script consists of the following steps:

          Step 1: Copy the Sequent 8 database schema and
          migration files to your project's `db/` directory. When this step is completed you
          can customize these files to your liking and commit the changes.

          One decision you need to make is whether you want to define partitions. This is
          mainly useful when your database tables are larger than 10 gigabytes or so. By
          default Sequent 8 uses a single "default" partition.

          The `db/sequent_schema_partitions.sql` file contains the database partitions for
          the `aggregates`, `commands`, and `events` tables, you can customize your
          partitions here.

          Step 2: Shutdown your application.

          Step 3: Run the migration script. The script starts a transaction but DOES NOT
          commit the results.

          Step 4: Check the results and COMMIT or ROLLBACK the result. If you COMMIT,
          you must perform a VACUUM ANALYZE to ensure PostgreSQL can efficiently query
          the new tables

          Step 5: Now you can deploy your Sequent 8 based application and start it again.

        EOS
      end

      def copy_schema_files
        prompt.say <<~EOS

          Step 1. First a copy of the Sequent 8 database schema and migration scripts are
          added to your db/ directory.
        EOS
        prompt.warn <<~EOS

          WARNING: this may overwrite your existing scripts, please use your version control system to commit or abort any of the changes!
        EOS

        abort_if_no('Do you which to continue?')

        FileUtils.copy_entry("#{sequent_gem_dir}/db", 'db')

        prompt.warn <<~EOS

          WARNING: The schema files have been copied, please verify and adjust the contents before committing and continuing.
        EOS
      end

      def stop_application
        prompt.say <<~EOS

          Step 2. Please shut down your existing application.
        EOS

        abort_if_no(<<~EOS)
          Only proceed once your application is stopped. Is your application stopped and do you want to continue?
        EOS
      end

      def migrate_data
        prompt.say <<~EOS

          Step 3. Open a `psql` connection to the database you wish to migrate.
        EOS
        prompt.warn <<~EOS

          It is highly recommended to test this on a copy of your production database first!
        EOS

        prompt.say <<~EOS

          Depending on the size of your database the migration can take a long time. Open the `psql` connection from a screen session if needed.
          If you run this from a screen session from another server you will need to copy all needed sql files to that server.

          ```
          psql -U myapp_user myapp_db
          ```
        EOS

        prompt.ask('Press <enter> to read the next instructions once you connected to the database...')

        prompt.say <<~EOS

          Run the database migration. This doesn't commit anything yet so you can check the results first.

          ```
          psql> \\i db/sequent_8_migration.sql
          ```
        EOS
      end

      def commit_or_rollback
        answer = prompt.yes? 'Did the migration succeed?'
        if answer
          prompt.say <<~EOS

            Step 4. After checking everything went OK, COMMIT and optimize the database:

            ```
            psql> COMMIT; VACUUM VERBOSE ANALYZE;
            ```
          EOS
        else
          prompt.say <<~EOS

            Step 4. Rollback the migration:

            ```
            psql> ROLLBACK;
            ```
          EOS
        end
        answer
      end

      def sequent_gem_dir = Gem::Specification.find_by_name('sequent').gem_dir

      def abort_if_no(message, abort_message: 'Stopped at your request. You can restart this migration at any time.')
        answer = prompt.yes?(message)
        fail Stop, abort_message unless answer
      end
    end
  end
end
