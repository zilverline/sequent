# frozen_string_literal: true

require 'spec_helper'
require_relative '../migration_class'
require 'tmpdir'

require 'sequent/support'

describe Sequent::Support::Database do
  let(:database_name) { Sequent.new_uuid }
  let(:db_config) do
    if Sequent.configuration.enable_multiple_database_support
      return Database
          .test_config
          .deep_merge(Sequent.configuration.primary_database_key => {'database' => database_name}).stringify_keys
    else
      return Database.test_config.merge(
        'database' => database_name,
      )
    end
  end

  shared_examples 'class methods' do
    describe '.create' do
      after do
        Sequent::Support::Database.disconnect!
        Sequent::Support::Database.drop!(db_config)
      end
      it 'creates the database' do
        expect { Sequent::Support::Database.create!(db_config) }.to change { database_exists? }.from(false).to(true)
      end
    end

    describe '.drop' do
      before { Sequent::Support::Database.create!(db_config) }
      it 'drop the database' do
        expect { Sequent::Support::Database.drop!(db_config) }.to change { database_exists? }.from(true).to(false)
      end
    end

    describe '.establish_connection' do
      before { Sequent::Support::Database.create!(db_config) }
      after do
        Sequent::Support::Database.disconnect!
        Sequent::Support::Database.drop!(db_config)
        Sequent::Support::Database.disconnect!
      end

      it 'connects the Sequent::ApplicationRecord pool' do
        Sequent::Support::Database.establish_connection(db_config)
        Sequent::ApplicationRecord.connection.reconnect!
        expect(Sequent::ApplicationRecord.connection).to be_active
      end
    end

    describe '.with_schema_search_path' do
      before { Sequent::Support::Database.create!(db_config) }
      after do
        Sequent::Support::Database.disconnect!
        Sequent::Support::Database.drop!(db_config)
      end

      it 'connects the Sequent::ApplicationRecord pool' do
        Sequent::Support::Database.with_schema_search_path('test2', db_config) do
          Sequent::ApplicationRecord.connection.reconnect!
          expect(Sequent::ApplicationRecord.connection).to be_active
        end
      end
    end

    describe '.read_config' do
      let(:test_config) do
        File.join(Sequent.configuration.database_config_directory, 'database.yml')
      end
      before do
        Sequent.configuration.database_config_directory = 'tmp'
        if Sequent.configuration.enable_multiple_database_support
          db_config = {}
          db_config[Sequent.configuration.primary_database_key.to_s] =
            Database.test_config[Sequent.configuration.primary_database_key.to_s].to_h
          db_config = db_config.to_h
          File.write(test_config, {'test' => db_config}.to_yaml)
        else
          File.write(test_config, {'test' => Database.test_config.to_h}.to_yaml)
        end
      end
      # after { File.delete(test_config) }

      it 'works' do
        expect(Sequent::Support::Database.read_config('test')).to be
      end
    end
  end

  describe 'class methods' do
    context 'with multiple database support',
            skip: Gem.loaded_specs['activerecord'].version < Gem::Version.create('6.1.0') do
              before { Sequent.configuration.enable_multiple_database_support = true }
              include_examples 'class methods'
              after { Sequent.configuration.enable_multiple_database_support = false }
            end
    context 'no multiple database support' do
      include_examples 'class methods'
    end
  end

  shared_examples 'instance methods' do
    describe '#create_schema!' do
      before do
        Sequent::ApplicationRecord.connection.execute('drop schema if exists eventstore')
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

  describe 'instance methods' do
    subject(:database) { Sequent::Support::Database.new }
    context 'with multiple database support',
            skip: Gem.loaded_specs['activerecord'].version < Gem::Version.create('6.1.0') do
              before do
                Sequent.configuration.enable_multiple_database_support = true
                Sequent::Support::Database.create!(db_config)
                Sequent::Support::Database.establish_connection(db_config)
              end
              after { Sequent::Support::Database.drop!(db_config) }
              after :all do
                Sequent.configuration.enable_multiple_database_support = false
              end
              include_examples 'instance methods'
            end
    context 'no multiple database support' do
      before do
        Sequent::Support::Database.create!(db_config)
        Sequent::Support::Database.establish_connection(db_config)
      end
      after { Sequent::Support::Database.drop!(db_config) }
      include_examples 'instance methods'
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
          postgresql://#{test_config['username']}:#{test_config['password']}@#{test_config['host']}:5432/#{test_config['database']}
        EOS
      }
    end

    it 'connects using an url option' do
      Sequent::Support::Database.establish_connection(db_config)
      Sequent::ApplicationRecord.connection.reconnect!
      expect(Sequent::ApplicationRecord.connection).to be_active

      Sequent::Support::Database.with_schema_search_path('view_schema', db_config) do
        expect(Sequent::ApplicationRecord.connection.schema_search_path).to eq 'view_schema'
        expect(Sequent::ApplicationRecord.connection).to be_active
      end

      expect(Sequent::ApplicationRecord.connection.schema_search_path).to eq test_config['schema_search_path']
    end

    context 'multiple database support',
            skip: Gem.loaded_specs['activerecord'].version < Gem::Version.create('7.0.0') do
              before { Sequent.configuration.enable_multiple_database_support = true }
              after { Sequent.configuration.enable_multiple_database_support = false }
              let(:test_config) { Database.test_config[Sequent.configuration.primary_database_key] }
              let(:db_config) do
                {
                  Sequent.configuration.primary_database_key => {
                    'url' => <<~EOS.chomp,
                      postgresql://#{test_config['username']}:#{test_config['password']}@#{test_config['host']}:5432/#{test_config['database']}
                    EOS
                    'schema_search_path' => test_config['schema_search_path'],
                  },
                  'replica' => {
                    'replica' => true,
                    'url' => <<~EOS.chomp,
                      postgresql://#{test_config['username']}:#{test_config['password']}@#{test_config['host']}:5432/#{test_config['database']}
                    EOS
                    'schema_search_path' => test_config['schema_search_path'],
                  },
                }
              end
              it 'connects using an url option' do
                Sequent::Support::Database.establish_connection(db_config)
                expect(Sequent::ApplicationRecord.connection).to be_active

                Sequent::Support::Database.with_schema_search_path('view_schema', db_config) do
                  expect(Sequent::ApplicationRecord.connection.schema_search_path).to eq 'view_schema'
                  expect(Sequent::ApplicationRecord.connection).to be_active
                end

                expect(Sequent::ApplicationRecord.connection.schema_search_path).to eq test_config['schema_search_path']
              end
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
