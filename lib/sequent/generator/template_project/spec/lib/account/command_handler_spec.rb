require_relative '../../spec_helper'
require_relative '../../../lib/account'

describe AccountCommandHandler do
  let(:aggregate_id) { Sequent.new_uuid }

  before :each do
    Sequent.configuration.command_handlers = [AccountCommandHandler.new]
  end

  it 'creates an account' do
    when_command AddAccount.new(aggregate_id: aggregate_id, name: 'ben')
    then_events(
      AccountAdded.new(aggregate_id: aggregate_id, sequence_number: 1),
      AccountNameChanged.new(aggregate_id: aggregate_id, sequence_number: 2, name: 'ben')
    )
  end
end
