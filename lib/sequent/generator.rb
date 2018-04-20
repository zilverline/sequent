require 'fileutils'
require 'active_support'
require 'active_support/core_ext/string'

module Sequent
  class Generator
    attr_reader :name, :name_underscored, :name_camelized

    def initialize(name)
      @name = name
      @name_underscored = name.underscore
      @name_camelized = name.camelize
    end

    def execute
      make_directory
      copy_files
      rename_app_file
      replace_app_name
    end

    private

    def make_directory
      FileUtils.mkdir_p(name)
    end

    def copy_files
      FileUtils.copy_entry(File.expand_path('generator/template_project', __dir__), name)
    end

    def rename_app_file
      FileUtils.mv("#{name}/my_app.rb", "#{name}/#{name_underscored}.rb")
    end

    def replace_app_name
      files = Dir["./#{name}/**/*"].select { |f| File.file?(f) }

      files.each do |filename|
        contents = File.read(filename)
        contents.gsub!('my_app', name_underscored)
        contents.gsub!('MyApp', name_camelized)
        File.open(filename, 'w') { |f| f.puts contents }
      end
    end
  end
end
