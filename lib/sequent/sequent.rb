require_relative 'configuration'
require_relative 'core/event'
require_relative 'core/command'
require_relative 'core/base_command_handler'
require_relative 'core/aggregate_root'
require_relative 'core/projector'
require_relative 'core/workflow'

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

  # Shortcut classes for easy usage
  Event = Sequent::Core::Event
  Command = Sequent::Core::Command
  CommandHandler = Sequent::Core::BaseCommandHandler
  AggregateRoot = Sequent::Core::AggregateRoot
  Projector = Sequent::Core::Projector
  Workflow = Sequent::Core::Workflow
end
