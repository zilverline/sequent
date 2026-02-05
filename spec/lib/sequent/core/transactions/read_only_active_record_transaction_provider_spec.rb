# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Transactions::ReadOnlyActiveRecordTransactionProvider do
  let(:transaction_provider) do
    Sequent::Core::Transactions::ActiveRecordTransactionProvider.new
  end
  let(:subject) do
    Sequent::Core::Transactions::ReadOnlyActiveRecordTransactionProvider.new(transaction_provider)
  end
  it 'fails when trying to write in a read only transaction' do
    expect do
      subject.transaction do
        Sequent::ApplicationRecord.connection.execute('create table foos (id integer)')
      end
    end.to raise_error(ActiveRecord::StatementInvalid) do |e|
      expect(e.cause).to be_a(PG::ReadOnlySqlTransaction)
      expect(e.message).to include('CREATE TABLE in a read-only transaction')
    end
  end

  it 'should be able to do only read queries' do
    expect do
      subject.transaction do
        Sequent::ApplicationRecord.connection.execute('select count(*) from command_records')
      end
    end.to_not raise_error
  end

  context 'after the readonly block' do
    after do
      Sequent::ApplicationRecord.connection.execute('drop table if exists foos')
    end
    it 'is possible to write again' do
      subject.transaction do
        Sequent::ApplicationRecord.connection.execute('show search_path')
      end
      Sequent::ApplicationRecord.connection.execute('create table foos (id integer)')
    end
  end

  context 'nested transactions' do
    it 'fails when trying to write in a nested transaction' do
      expect do
        subject.transaction do
          Sequent::ApplicationRecord.connection.execute('show search_path')
          subject.transaction do
            Sequent::ApplicationRecord.connection.execute('create table foos (id integer)')
          end
        end
      end.to raise_error(ActiveRecord::StatementInvalid) do |e|
        expect(e.cause).to be_a(PG::ReadOnlySqlTransaction)
        expect(e.message).to include('CREATE TABLE in a read-only transaction')
      end
    end
    it 'fails when trying to write in a nested nested transaction' do
      expect do
        subject.transaction do
          Sequent::ApplicationRecord.connection.execute('show search_path')
          subject.transaction do
            Sequent::ApplicationRecord.connection.execute('show search_path')
            subject.transaction do
              Sequent::ApplicationRecord.connection.execute('create table foos (id integer)')
            end
          end
        end
      end.to raise_error(ActiveRecord::StatementInvalid) do |e|
        expect(e.cause).to be_a(PG::ReadOnlySqlTransaction)
        expect(e.message).to include('CREATE TABLE in a read-only transaction')
      end
    end

    it 'fails when requiring a new inside a readonly' do
      expect do
        subject.transaction do
          Sequent::ApplicationRecord.connection.execute('show search_path')
          transaction_provider.transaction do
            Sequent::ApplicationRecord.connection.execute('create table foos (id integer)')
          end
        end
      end.to raise_error(ActiveRecord::StatementInvalid) do |e|
        expect(e.cause).to be_a(PG::ReadOnlySqlTransaction)
        expect(e.message).to include('CREATE TABLE in a read-only transaction')
      end
    end
    it 'fails when opening a new ActiveRecord transaction directly in a readonly' do
      expect do
        subject.transaction do
          Sequent::ApplicationRecord.connection.execute('show search_path')
          ActiveRecord::Base.transaction(requires_new: true) do
            Sequent::ApplicationRecord.connection.execute('create table foos (id integer)')
          end
        end
      end.to raise_error(ActiveRecord::StatementInvalid) do |e|
        expect(e.cause).to be_a(PG::ReadOnlySqlTransaction)
        expect(e.message).to include('CREATE TABLE in a read-only transaction')
      end
    end
  end
end
