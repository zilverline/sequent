# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Transactions::ActiveRecordTransactionProvider do
  let(:provider) { Sequent::Core::Transactions::ActiveRecordTransactionProvider.new }

  it 'returns the block result' do
    expect(provider.transaction { '10' }).to eq '10'
  end

  context 'with after_commit hooks' do
    it 'calls the after_commit hooks' do
      called = false
      provider.transaction do
        provider.after_commit { called = true }
      end
      expect(called).to be_truthy
    end
    it 'still returns the result of the block' do
      called = false
      result = provider.transaction do
        provider.after_commit { called = true }
        '11'
      end
      expect(called).to be_truthy
      expect(result).to eq('11')
    end
    it 'only calls after_commit when the outermost transaction completes' do
      called = false
      provider.transaction do
        provider.transaction do
          provider.after_commit { called = true }
        end
        expect(called).to be_falsy
      end
      expect(called).to be_truthy
    end
    it 'does not call after_commit on rollback' do
      called = false
      begin
        provider.transaction do
          provider.after_commit { called = true }
          fail 'rollback transaction'
        end
      rescue StandardError
        expect(called).to be_falsy
      end
    end
  end

  context 'with after_rollback hooks' do
    it 'calls the after_rollback hooks' do
      called = false
      begin
        provider.transaction do
          provider.after_rollback { called = true }
          fail 'rollback transaction'
        end
      rescue StandardError
        expect(called).to be_truthy
      end
    end
    it 'only calls after_rollback when the outermost transaction completes' do
      called = false
      begin
        provider.transaction do
          provider.transaction do
            provider.after_rollback { called = true }
          end
          throw 'rollback transaction'
        end
      rescue StandardError
        expect(called).to be_truthy
      end
    end
  end
end
