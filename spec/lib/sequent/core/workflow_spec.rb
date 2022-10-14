# frozen_string_literal: true

require 'spec_helper'
require 'sequent/test/workflow_helpers'

describe Sequent::Core::Workflow do
  class RegisterUser < Sequent::Command; end

  class SendWelcomeEmail < Sequent::Command; end

  class CreateNotification < Sequent::Command; end

  class UserWasRegistered < Sequent::Core::Event; end

  class WelcomeEmailWasSent < Sequent::Core::Event; end

  class User < Sequent::AggregateRoot
    def initialize(id)
      super
      apply UserWasRegistered
    end

    def welcome_email_send
      apply WelcomeEmailWasSent
    end
  end

  class RegistrationCommandHandler < Sequent::CommandHandler
    class << self
      attr_accessor :commands

      def clear_commands
        self.commands = []
      end
    end

    on RegisterUser do |command|
      Sequent.aggregate_repository.add_aggregate(User.new(command.aggregate_id))
    end
    on CreateNotification do |command|
      self.class.commands << command
    end
    on SendWelcomeEmail do |command|
      self.class.commands << command
      user = Sequent.aggregate_repository.load_aggregate(command.aggregate_id)
      user.welcome_email_send
    end
  end

  class RegistrationWorkflow < Sequent::Workflow
    on UserWasRegistered do |e|
      execute_commands CreateNotification.new(aggregate_id: e.aggregate_id)

      after_commit do
        execute_commands SendWelcomeEmail.new(aggregate_id: e.aggregate_id)
      end
    end

    on WelcomeEmailWasSent do |e|
      after_commit do
        execute_commands CreateNotification.new(aggregate_id: e.aggregate_id)
      end
    end
  end

  before do
    RegistrationCommandHandler.clear_commands
    Sequent.configuration.command_handlers = [RegistrationCommandHandler.new]
    Sequent.configuration.event_handlers = [RegistrationWorkflow.new]
  end

  it 'executes commands registered with after_commit' do
    Sequent.command_service.execute_commands RegisterUser.new(aggregate_id: Sequent.new_uuid)
    expect(RegistrationCommandHandler.commands).to have(3).items
    expect(RegistrationCommandHandler.commands.map(&:class)).to eq [
      CreateNotification,
      SendWelcomeEmail,
      CreateNotification,
    ]
  end
end
