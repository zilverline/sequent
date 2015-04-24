require_relative 'core/core'
require_relative 'migrations/migrations'
require_relative 'test/test'
require_relative 'configuration'

module Sequent
  def self.configure
    yield Configuration.instance
  end

  def self.configuration
    Configuration.instance
  end
end
