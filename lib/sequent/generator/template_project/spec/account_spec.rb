require 'spec_helper'
require_relative '../lib/account'

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

describe AccountProjector do
  let(:aggregate_id) { Sequent.new_uuid }
  let(:account_projector) { AccountProjector.new }

  context AccountCreated do
    let(:account_created) { AccountCreated.new(aggregate_id: aggregate_id, sequence_number: 1) }

    it 'creates a projection' do
      account_projector.handle_message(account_created)
      expect(AccountRecord.count).to eq(1)
      record = AccountRecord.first
      expect(record.aggregate_id).to eq(aggregate_id)
    end
  end

  context AccountNameChanged do
    let(:account_created) { AccountCreated.new(aggregate_id: aggregate_id, sequence_number: 1) }
    let(:account_name_changed) do
      AccountNameChanged.new(aggregate_id: aggregate_id, name: 'ben', sequence_number: 2)
    end

    before { account_projector.handle_message(account_created) }

    it 'creates a projection' do
      account_projector.handle_message(account_name_changed)
      expect(AccountRecord.count).to eq(1)
      record = AccountRecord.first
      expect(record.name).to eq('ben')
    end
  end
end
