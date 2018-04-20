require_relative '../spec_helper'
require_relative '../../lib/account'

describe Account::Projector do
  let(:aggregate_id) { Sequent.new_uuid }
  let(:account_projector) { Account::Projector.new }

  context Account::AccountAdded do
    let(:account_created) { Account::AccountAdded.new(aggregate_id: aggregate_id, sequence_number: 1) }

    it 'creates a projection' do
      account_projector.handle_message(account_created)
      expect(AccountRecord.count).to eq(1)
      record = AccountRecord.first
      expect(record.aggregate_id).to eq(aggregate_id)
    end
  end

  context Account::AccountNameChanged do
    let(:account_created) { Account::AccountAdded.new(aggregate_id: aggregate_id, sequence_number: 1) }
    let(:account_name_changed) do
      Account::AccountNameChanged.new(aggregate_id: aggregate_id, name: 'ben', sequence_number: 2)
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
