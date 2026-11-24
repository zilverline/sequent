# frozen_string_literal: true

require 'spec_helper'

class UnbufferedPersistorRecord < Sequent::ApplicationRecord; end

class UnbufferedPersistorArrayRecord < Sequent::ApplicationRecord; end

describe Sequent::Core::Persistors::UnbufferedPersistor do
  let(:record_class) { UnbufferedPersistorRecord }
  let(:persistor) { described_class.new }
  let(:created_at) { Time.utc(2026, 1, 1) }

  before do
    exec_sql(<<~SQL)
      DROP TABLE IF EXISTS unbuffered_persistor_records;
      CREATE TABLE unbuffered_persistor_records (
        id bigserial PRIMARY KEY,
        name character varying,
        amount integer,
        created_at timestamp without time zone NOT NULL,
        updated_at timestamp without time zone NOT NULL
      );
    SQL
    record_class.reset_column_information
  end

  def create(name, amount: nil)
    persistor.create_record(record_class, name:, amount:, created_at:)
  end

  def names(where_clause) = persistor.find_records(record_class, where_clause).map(&:name)

  def queries(&)
    payloads = []
    callback = ->(*, payload) { payloads << payload unless payload[:name] == 'SCHEMA' }
    ActiveSupport::Notifications.subscribed(callback, 'sql.active_record', &)
    payloads
  end

  describe 'statements' do
    it 'sends the values as binds, and prepares the statements' do
      payloads = queries do
        persistor.create_record(record_class, name: 'distinctive-name', amount: 987_654, created_at:)
        persistor.update_all_records(record_class, {name: 'distinctive-name'}, {amount: 876_543})
        persistor.get_record(record_class, name: 'distinctive-name')
        persistor.delete_all_records(record_class, name: 'distinctive-name')
      end

      expect(payloads.size).to eq 4
      payloads.each do |payload|
        expect(payload[:sql]).not_to include('distinctive-name', '987654', '876543')
        expect(payload[:binds]).not_to be_empty
        expect(payload[:statement_name]).to be_present
      end
    end

    it 'prepares a statement of the same shape once' do
      payloads = queries do
        create('a')
        create('b')
      end

      expect(payloads.map { |payload| payload[:sql] }.uniq.size).to eq 1
      expect(payloads.map { |payload| payload[:statement_name] }.uniq.size).to eq 1
    end

    it 'clears the query cache' do
      record_class.connection.cache do
        create('a')
        expect(record_class.where(name: 'a').count).to eq 1
        persistor.delete_all_records(record_class, name: 'a')
        expect(record_class.where(name: 'a').count).to eq 0
      end
    end

    it 'inserts records with different columns without a value' do
      persistor.create_records(
        record_class,
        [
          {name: 'a', created_at:},
          {name: 'b', amount: 2, created_at:},
          {name: 'c', created_at:, updated_at: created_at + 1},
        ],
      )

      expect(record_class.order(:id).pluck(:name, :amount, :updated_at)).to eq(
        [['a', nil, created_at], ['b', 2, created_at], ['c', nil, created_at + 1]],
      )
    end
  end

  describe 'inserting several records' do
    def insert_payloads(&) = queries(&).select { |payload| payload[:name].end_with?('Insert') }

    it 'prepares one statement for any number of records, with a bind for every column' do
      payloads = insert_payloads do
        persistor.create_records(record_class, Array.new(2) { |i| {name: "a#{i}", amount: i, created_at:} })
        persistor.create_records(record_class, Array.new(5) { |i| {name: "b#{i}", amount: i, created_at:} })
      end

      expect(payloads.size).to eq 2
      expect(payloads.map { |payload| payload[:sql] }.uniq).to eq(
        [
          'INSERT INTO "unbuffered_persistor_records" ("name", "amount", "created_at", "updated_at") ' \
          'SELECT * FROM unnest($1::character varying[], $2::integer[], $3::timestamp without time zone[], ' \
          '$4::timestamp without time zone[])',
        ],
      )
      expect(payloads.map { |payload| payload[:statement_name] }.uniq.size).to eq 1
      expect(payloads.map { |payload| payload[:statement_name] }).to all(be_present)
      expect(payloads.map { |payload| payload[:binds].size }).to eq [4, 4]
      expect(record_class.count).to eq 7
    end

    it 'returns the columns in the order of the records' do
      records = Array.new(5) do |i|
        Sequent::Core::Persistors::RecordStructs.create(record_class, {name: "n#{i}", created_at:})
      end

      result = Sequent::Core::Persistors::Statements::Insert.new(record_class, *records)
        .execute(returning: %i[id name])

      expect(result.rows.map(&:last)).to eq %w[n0 n1 n2 n3 n4]
      expect(result.rows.map(&:first)).to eq result.rows.map(&:first).sort
    end

    context 'with an array column' do
      let(:array_class) { UnbufferedPersistorArrayRecord }

      before do
        exec_sql(<<~SQL)
          DROP TABLE IF EXISTS unbuffered_persistor_array_records;
          CREATE TABLE unbuffered_persistor_array_records (
            id bigserial PRIMARY KEY,
            name character varying,
            tags character varying[],
            created_at timestamp without time zone NOT NULL,
            updated_at timestamp without time zone NOT NULL
          );
        SQL
        array_class.reset_column_information
      end

      it 'inserts the records with a multi-row VALUES statement that is not prepared' do
        payloads = insert_payloads do
          persistor.create_records(
            array_class,
            [
              {name: 'a', tags: %w[x y], created_at:},
              {name: 'b', tags: [], created_at:},
              {name: 'c', tags: %w[z], created_at:},
            ],
          )
        end

        expect(payloads.size).to eq 1
        expect(payloads.first[:sql]).to include('VALUES')
        expect(payloads.first[:sql]).not_to include('unnest')
        expect(payloads.first[:statement_name]).to be_blank
        expect(array_class.order(:id).pluck(:name, :tags)).to eq [['a', %w[x y]], ['b', []], ['c', %w[z]]]
      end
    end
  end

  describe 'where clauses' do
    before do
      create('a', amount: 1)
      create('b')
      create('c', amount: 3)
    end

    it 'matches nil as NULL' do
      expect(names(amount: nil)).to eq ['b']
    end

    it 'matches an array, and a nil in it as NULL' do
      expect(names(amount: [1, 3])).to match_array %w[a c]
      expect(names(amount: [1, nil])).to match_array %w[a b]
      expect(names(amount: [nil])).to eq ['b']
    end

    it 'matches nothing for an empty array' do
      expect(names(amount: [])).to be_empty
    end

    it 'matches several columns' do
      expect(names(name: %w[a b], amount: 1)).to eq ['a']
    end

    it 'leaves other values to ActiveRecord' do
      expect(names(amount: 2..3)).to eq ['c']
      expect(names(amount: record_class.select(:amount).where(name: 'a'))).to eq ['a']
      expect(persistor.update_all_records(record_class, {amount: 2..3}, {name: 'z'})).to eq 1
      expect(persistor.delete_all_records(record_class, amount: 1..2)).to eq 1
      expect(names({})).to match_array %w[b z]
    end

    it 'updates and deletes by where clause' do
      expect(persistor.update_all_records(record_class, {amount: [1, nil]}, {name: 'z', amount: 5})).to eq 2
      expect(record_class.order(:id).pluck(:name, :amount)).to eq [['z', 5], ['z', 5], ['c', 3]]
      expect(persistor.delete_all_records(record_class, name: 'z')).to eq 2
      expect(record_class.pluck(:name)).to eq ['c']
    end
  end
end
