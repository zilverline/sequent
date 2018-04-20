require 'fileutils'
require 'active_support'

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
      `find #{name} -type f | xargs sed -i '' 's/MyApp/#{name_camelized}/g'`
      `find #{name} -type f | xargs sed -i '' 's/my_app/#{name_underscored}/g'`
    end
  end
end
