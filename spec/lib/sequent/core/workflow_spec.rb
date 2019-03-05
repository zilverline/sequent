require 'spec_helper'
require 'sequent/test/event_handler_helpers'

describe Sequent::Core::Workflow do
  include Sequent::Test::WorkflowHelpers

  class CreateNotification < Sequent::Core::BaseCommand; end

  class UserWasRegistered < Sequent::Core::Event
    attrs email: String
  end

  class SendWelcomeEmail < Sequent::Core::BaseCommand
    attrs email: String
  end

  class RegistrationWorkflow < Sequent::Core::Workflow
    on UserWasRegistered do |e|
      execute_commands CreateNotification.new(aggregate_id: e.aggregate_id)

      after_commit do
        execute_commands SendWelcomeEmail.new(email: e.email)
      end
    end
  end

  let(:workflow) { RegistrationWorkflow.new }

  let(:notification_command) { CreateNotification.new(aggregate_id: 'user') }
  let(:email_command) { SendWelcomeEmail.new(aggregate_id: 'user', email: 'user@example.com') }

  it 'executes commands' do
    fake_transaction_provider.transactional do
      when_event UserWasRegistered.new(aggregate_id: 'user', sequence_number: 1, email: 'user@example.com')
      then_commands notification_command
    end
    then_commands notification_command, email_command
  end
end
