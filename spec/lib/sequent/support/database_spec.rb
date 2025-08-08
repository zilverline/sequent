# frozen_string_literal: true

require 'spec_helper'
require_relative '../migration_class'
require 'tmpdir'

require 'sequent/support'

describe Sequent::Support::Database do
  let(:database_name) { Sequent.new_uuid }
  let(:db_config) do
    Database.test_config.merge(
      'database' => database_name,
    )
  end
  let(:resolved_config) do
    ActiveRecord::Base.configurations = ActiveRecord::DatabaseConfigurations.new(test: db_config)
    ActiveRecord::Base.configurations.resolve(:test)
  end

  describe 'class methods' do
    describe '.create' do
      after do
        Sequent::Support::Database.disconnect!
        Sequent::Support::Database.drop!(resolved_config)
      end
      it 'creates the database' do
        expect { Sequent::Support::Database.create!(resolved_config) }.to change {
          database_exists?
        }.from(false).to(true)
      end
    end

    describe '.drop' do
      before { Sequent::Support::Database.create!(resolved_config) }
      it 'drop the database' do
        expect { Sequent::Support::Database.drop!(resolved_config) }.to change { database_exists? }.from(true).to(false)
      end
    end

    describe '.establish_connection' do
      before { Sequent::Support::Database.create!(resolved_config) }
      after do
        Sequent::Support::Database.disconnect!
        Sequent::Support::Database.drop!(resolved_config)
        Sequent::Support::Database.disconnect!
      end

      it 'connects the Sequent::ApplicationRecord pool' do
        Sequent::Support::Database.establish_connection(db_config)
        Sequent::ApplicationRecord.connection.reconnect!
        expect(Sequent::ApplicationRecord.connection).to be_active
      end
    end

    describe '.with_search_path' do
      before { Sequent::Support::Database.create!(resolved_config) }

      it 'changes the search path' do
        Sequent::Support::Database.with_search_path('foo') do
          expect(ActiveRecord::Base.connection.select_value("SELECT current_setting('search_path')")).to eq('foo')
        end
      end

      it 'restores the search path' do
        Sequent::Support::Database.with_search_path('foo') {}
        expect(ActiveRecord::Base.connection.select_value("SELECT current_setting('search_path')"))
          .to eq('public, view_schema, sequent_schema')
      end
    end
  end

  describe 'instance methods' do
    subject(:database) { Sequent::Support::Database.new }

    before do
      Sequent::Support::Database.create!(resolved_config)
      Sequent::Support::Database.establish_connection(db_config)
    end
    after { Sequent::Support::Database.drop!(resolved_config) }

    describe '#create_schema!' do
      before do
        Sequent::ApplicationRecord.connection.execute('DROP SCHEMA IF EXISTS eventstore CASCADE')
      end
      it 'creates the schema' do
        expect { database.create_schema!('eventstore') }.to change {
          database.schema_exists?('eventstore')
        }.from(false).to(true)
      end

      it 'ignores existing schema' do
        database.create_schema!('eventstore')
        expect { database.create_schema!('eventstore') }.to_not raise_error
      end

      it 'schema does not exist when specified table is not present' do
        database.create_schema!('eventstore')
        expect(database.schema_exists?('eventstore', 'event_records')).to eq(false)
        database.execute_sql('CREATE VIEW eventstore.event_records (id) AS SELECT 1')
        expect(database.schema_exists?('eventstore', 'event_records')).to eq(true)
      end
    end

    describe '#drop_schema!' do
      it 'drops the schema' do
        database.create_schema!('my_app')
        expect { database.drop_schema!('my_app') }.to change {
          database.schema_exists?('my_app')
        }.from(true).to(false)
      end

      it 'ignores non-existing schema' do
        expect { database.drop_schema!('my_app') }.to_not raise_error
      end
    end
  end

  describe 'connection options' do
    let(:test_config) { Database.test_config }
    let(:db_config) do
      # Use test config from all other tests but turn it into an URL. Hardcode
      # the default port to enforce a proper URL.
      {
        'schema_search_path' => test_config['schema_search_path'],
        'url' => <<~EOS.chomp,
          postgresql://#{test_config['username']}:#{test_config['password']}@#{test_config['host']}:#{ENV['PGPORT'] || 5432}/#{test_config['database']}
        EOS
      }
    end

    it 'connects using an url option' do
      Sequent::Support::Database.establish_connection(db_config)
      Sequent::ApplicationRecord.connection.reconnect!
      expect(Sequent::ApplicationRecord.connection).to be_active
      expect(Sequent::ApplicationRecord.connection.schema_search_path.gsub(' ', ''))
        .to eq test_config['schema_search_path'].gsub(' ', '')
    end
  end

  def database_exists?
    results = Sequent::ApplicationRecord.connection.select_all %(
SELECT 1 FROM pg_database
 WHERE datname = '#{database_name}'
)
    results.count == 1
  end

  def table_exists?(table_name)
    results = Sequent::ApplicationRecord.connection.select_all %(
SELECT 1 FROM pg_tables
 WHERE tablename = '#{table_name}'
)
    results.count == 1
  end
end
