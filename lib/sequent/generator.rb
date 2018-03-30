module Sequent
  class Generator
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def execute
      FileUtils.mkdir_p(name)
      FileUtils.copy_entry(File.expand_path('generator/template_project', __dir__), name)
    end
  end
end
