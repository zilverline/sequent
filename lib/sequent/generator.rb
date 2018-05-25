require 'fileutils'
require 'active_support'
require 'active_support/core_ext/string'

class TargetAlreadyExists < StandardError; end

module Sequent
  module Generator
    class Project
      def initialize(path_or_name)
        @path_or_name = path_or_name
      end

      def execute
        make_directory
        copy_files
        rename_app_file
        replace_app_name
      end

      private

      def make_directory
        FileUtils.mkdir_p(path)
      end

      def copy_files
        FileUtils.copy_entry(File.expand_path('generator/template_project', __dir__), path)
      end

      def rename_app_file
        FileUtils.mv("#{path}/my_app.rb", "#{path}/#{name_underscored}.rb")
      end

      def replace_app_name
        files = Dir["#{path}/**/*"].select { |f| File.file?(f) }

        files.each do |filename|
          contents = File.read(filename)
          contents.gsub!('my_app', name_underscored)
          contents.gsub!('MyApp', name_camelized)
          File.open(filename, 'w') { |f| f.puts contents }
        end
      end

      def path
        @path ||= File.expand_path(@path_or_name)
      end

      def name
        @name ||= File.basename(path)
      end

      def name_underscored
        @name_underscored ||= name.underscore
      end

      def name_camelized
        @name_camelized ||= name.camelize
      end
    end

    class Aggregate
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def execute
        ensure_not_used!
        copy_files
        rename_files
        replace_app_name
      end

      private

      def copy_files
        FileUtils.copy_entry(File.expand_path('generator/template_aggregate', __dir__), path)
      end

      def rename_files
        FileUtils.mv("#{path}/template_aggregate.rb", "#{path}/#{name_underscored}.rb")
        FileUtils.mv("#{path}/template_aggregate", "#{path}/#{name_underscored}")

        FileUtils.mv("#{path}/#{name_underscored}/template_aggregate_command_handler.rb", "#{path}/#{name_underscored}/#{name_underscored}_command_handler.rb")
        FileUtils.mv("#{path}/#{name_underscored}/template_aggregate.rb", "#{path}/#{name_underscored}/#{name_underscored}.rb")
      end

      def replace_app_name
        files = Dir["#{path}/**/*"].select { |f| File.file?(f) }

        files.each do |filename|
          contents = File.read(filename)
          contents.gsub!('template_aggregate', name_underscored)
          contents.gsub!('TemplateAggregate', name_camelized)
          File.open(filename, 'w') { |f| f.puts contents }
        end
      end

      def path
        @path ||= File.expand_path("lib")
      end

      def name
        @name ||= File.basename(path)
      end

      def name_underscored
        @name_underscored ||= name.underscore
      end

      def name_camelized
        @name_camelized ||= name.camelize
      end

      def ensure_not_used!
        if File.directory?("#{path}/#{name_underscored}") || File.exist?("#{path}/#{name_underscored}.rb")
          raise TargetAlreadyExists
        end
      end
    end
  end
end
