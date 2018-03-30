# spec/account_spec.rb
require 'spec_helper'
require_relative '../lib/domain'

describe 'Account' do
  let(:aggregate_id) { Sequent.new_uuid }

  before :each do
    Sequent.configuration.command_handlers = [AccountCommandHandler.new]
  end

  it 'creates an account' do
    when_command CreateAccount.new(aggregate_id: aggregate_id, name: 'ben')
    then_events AccountCreated.new(aggregate_id: aggregate_id, sequence_number: 1),
      AccountNameChanged.new(aggregate_id: aggregate_id, sequence_number: 2, name: 'ben')
  end
end
