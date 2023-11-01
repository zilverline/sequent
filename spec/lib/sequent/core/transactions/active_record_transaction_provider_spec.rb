# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Transactions::ActiveRecordTransactionProvider do
  let(:provider) { Sequent::Core::Transactions::ActiveRecordTransactionProvider.new }

  it 'returns the block result' do
    expect(provider.transactional { '10' }).to eq '10'
  end

  context 'with after_commit hooks' do
    it 'calls the after_commit hooks' do
      called = false
      provider.after_commit { called = true }
      provider.transactional {}
      expect(called).to be_truthy
    end
    it 'still returns the result of the block' do
      called = false
      provider.after_commit { called = true }
      expect(provider.transactional { '11' }).to eq '11'
      expect(called).to be_truthy
    end
  end
end
