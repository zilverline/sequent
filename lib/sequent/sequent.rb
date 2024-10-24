# frozen_string_literal: true

require_relative 'configuration'
require_relative 'core/event'
require_relative 'core/command'
require_relative 'core/base_command_handler'
require_relative 'core/aggregate_root'
require_relative 'core/projector'
require_relative 'core/workflow'
require_relative 'core/value_object'
require_relative 'internal/internal'
require_relative 'migrations/migrations'

module Sequent
  def self.new_uuid
    Sequent.configuration.uuid_generator.uuid
  end

  #
  # Setup Sequent.
  #
  # Setup is typically called in an +initializer+ or setup phase of your application.
  # A minimal setup could look like this:
  #
  #   Sequent.configure do |config|
  #     config.enable_autoregistration = true
  #   end
  #
  # Calling configure a second time will create a new configuration
  def self.configure
    Configuration.reset
    yield Configuration.instance
    Configuration.instance.autoregister!
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

  # Short hand for Sequent.configuration.logger
  def self.logger
    configuration.logger
  end

  # Short hand for Sequent.configuration.aggregate_repository
  def self.aggregate_repository
    configuration.aggregate_repository
  end

  def self.dry_run(*commands)
    Sequent::Util::DryRun.these_commands(commands)
  end

  # Shortcut classes for easy usage
  Event = Sequent::Core::Event
  Command = Sequent::Core::Command
  CommandHandler = Sequent::Core::BaseCommandHandler
  AggregateRoot = Sequent::Core::AggregateRoot
  Projector = Sequent::Core::Projector
  Workflow = Sequent::Core::Workflow
  ValueObject = Sequent::Core::ValueObject
end
