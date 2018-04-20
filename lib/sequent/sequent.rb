require_relative 'configuration'

module Sequent
  def self.new_uuid
    Sequent.configuration.uuid_generator.uuid
  end

  def self.configure
    yield Configuration.instance
  end

  def self.configuration
    Configuration.instance
  end

  # Short hand for Sequent.configuration.command_service
  def self.command_service
    configuration.command_service
  end

  def self.new_version
    migration_class.version
  end

  def self.migration_class
    Class.const_get(configuration.migrations_class_name)
  end

  def self.logger
    configuration.logger
  end
end
