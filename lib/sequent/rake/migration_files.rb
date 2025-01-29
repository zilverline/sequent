# frozen_string_literal: true

module Sequent
  module Rake
    class MigrationFiles
      MIGRATION_DIRECTORY = File.realpath(File.join(__dir__, '../../../db/migrate'))

      def copy(to)
        FileUtils.mkdir_p(to)
        now = Time.current.strftime('%Y%m%d%H%M%S')
        current_entries = current_migration_files(to)

        Dir
          .entries(MIGRATION_DIRECTORY)
          .reject { |dir| dir.start_with?('.') }
          .sort
          .each_with_index do |file, index|
            full_file_name = File.join(MIGRATION_DIRECTORY, file)

            if File.directory?(full_file_name)
              copy_directory(file, MIGRATION_DIRECTORY, to)
            else
              _timestamp, *file_parts = file.split('_')
              next if current_entries.include?(file_parts.join('_'))

              file_name = [(now.to_i + index).to_s, *file_parts].join('_')
              destination_file_name = File.join(to, file_name)
              FileUtils.cp(full_file_name, destination_file_name, preserve: true, verbose: true)
            end
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

      def copy_directory(directory_name, from, to)
        source = File.join(from, directory_name)
        dest = File.join(to, directory_name)
        FileUtils.mkdir_p(dest)

        existing = Dir.entries(dest)

        Dir
          .entries(source)
          .reject { |file| file.start_with?('.') }
          .sort
          .each do |file|
            full_file_name = File.join(source, file)
            if File.directory?(full_file_name)
              copy_directory(file, source, dest)
            else
              next if existing.include?(file)

              FileUtils.cp(File.join(source, file), File.join(dest, file), preserve: true, verbose: true)
            end
          end
      end
    end
  end
end
