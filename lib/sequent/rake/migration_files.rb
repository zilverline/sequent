# frozen_string_literal: true

module Sequent
  module Rake
    class MigrationFiles
      MIGRATION_DIRECTORY = File.join(__dir__, '../../../db/migrate')

      def copy(to)
        FileUtils.mkdir_p(to)
        now = Time.current.strftime('%Y%m%d%H%M%S')
        current_entries = current_migration_files(to)

        Dir
          .entries(MIGRATION_DIRECTORY)
          .reject { |dir| dir.start_with?('.') }
          .sort
          .each_with_index do |file, index|
            _timestamp, *file_parts = file.split('_')
            next if current_entries.include?(file_parts.join('_'))

            file_name = [(now.to_i + index).to_s, *file_parts].join('_')
            full_file_name = File.join(MIGRATION_DIRECTORY, file)
            destination_file_name = File.join(to, file_name)
            FileUtils.copy(full_file_name, destination_file_name)
          end
      end

      private

      def current_migration_files(to)
        Dir
          .entries(to)
          .reject { |f| f.start_with?('.') }
          .map do |f|
            _timestamp, *file_parts = f.split('_')
            file_parts.join('_')
          end
      end
    end
  end
end
