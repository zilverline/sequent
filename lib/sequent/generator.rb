require 'fileutils'
require 'active_support'
require 'active_support/core_ext/string'

module Sequent
  class Generator
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
end
