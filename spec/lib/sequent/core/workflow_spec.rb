require 'spec_helper'
require 'sequent/test/event_handler_helpers'

describe Sequent::Core::Workflow do
  include Sequent::Test::WorkflowHelpers

  class UserWasRegistered < Sequent::Core::Event
    attrs email: String
  end

  class SendWelcomeEmail < Sequent::Core::BaseCommand
    attrs email: String
  end

  class RegistrationWorkflow < Sequent::Core::Workflow
    on UserWasRegistered do |e|
      execute_commands SendWelcomeEmail.new(email: e.email)
    end
  end

  let(:workflow) { RegistrationWorkflow.new }

  it 'executes commands' do
    when_event UserWasRegistered.new(aggregate_id: 'user', sequence_number: 1, email: 'user@example.com')
    then_commands SendWelcomeEmail.new(aggregate_id: 'user', email: 'user@example.com')
  end
end
