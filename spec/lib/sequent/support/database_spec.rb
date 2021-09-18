require 'spec_helper'
require_relative '../migration_class'
require 'tmpdir'

require 'sequent/support'
require 'tmpdir' # ruby 2.2.2 fails on Dir.tmpdir when not requiring

describe Sequent::Support::Database do
  let(:database_name) { Sequent.new_uuid }
  let(:db_config) do
    Database.test_config.merge(
      'database' => database_name,
    )
  end

  describe 'class methods' do
    describe '.create' do
      after { Sequent::Support::Database.drop!(db_config) }
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
      end

      it 'connects the Sequent::ApplicationRecord pool' do
        Sequent::Support::Database.establish_connection(db_config)
        expect(Sequent::ApplicationRecord.connection).to be_active
      end
    end

    describe ".read_config" do
      before do
        allow(YAML).to receive(:load).with(anything).and_return({ test: db_config })
        Sequent.configuration.database_config_directory = "spec/fixtures"
      end

      context "without pg_url config" do
        it "returns the proper database configurations" do
          configs = described_class.read_config(:test)
          expect(configs[:database]).to eq(database_name)
        end
      end

      context "with pg_url config" do
        let(:db_config) do
          test_config = Database.test_config

          {
            "url" => "postgresql://#{test_config['username']}:#{test_config['password']}@#{test_config['host']}:5432/#{database_name}"
          }
        end

        it "returns the proper database configurations" do
          configs = described_class.read_config(:test)
          expect(configs[:database]).to eq(database_name)
        end
      end

      context "with not support active-record version" do
        before do
          allow(ActiveRecord::Base)
            .to receive(:respond_to?).with(:resolve_config_for_connection)
            .and_return(false)

          allow(ActiveRecord::Base.configurations)
            .to receive(:respond_to?).with(:resolve)
            .and_return(false)
        end

        it "raises ActiveRecordNotSupportedError" do
          expect {
            described_class.read_config(:test)
          }.to raise_error(ActiveRecordVersionNotSupportedError)
        end
      end
    end
  end

  context 'instance methods' do
    before do
      Sequent::Support::Database.create!(db_config)
      Sequent::Support::Database.establish_connection(db_config)
    end
    after { Sequent::Support::Database.drop!(db_config) }

    subject(:database) { Sequent::Support::Database.new }

    describe '#create_schema!' do
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

    describe '#migrate' do
      let(:migrations_path) { File.expand_path(database_name, Dir.tmpdir).tap { |dir| Dir.mkdir(dir) } }
      after { FileUtils.rm_rf(migrations_path) }

      it 'runs pending migrations' do
        File.open(File.expand_path("1_test_migration.rb", migrations_path), 'w') do |f|
          f.write <<EOF
class TestMigration < MigrationClass
  def change
    create_table "my_table", id: false do |t|
      t.string "id", null: false
    end
  end
end
EOF
          f.flush
          expect { database.migrate(migrations_path, verbose: false) }.to change {
            table_exists?('my_table')
          }.from(false).to(true)
        end
      end
    end
  end

  describe 'connection options' do
    let(:db_config) do
      test_config = Database.test_config
      # Use test config from all other tests but turn it into an URL. Hardcode
      # the default port to enforce a proper URL.
      {
        "url" => "postgresql://#{test_config['username']}:#{test_config['password']}@#{test_config['host']}:5432/#{test_config['database']}"
      }
    end

    it 'connects using an url option' do
      Sequent::Support::Database.establish_connection(db_config)
      expect(Sequent::ApplicationRecord.connection).to be_active
    end
  end

  def database_exists?
    results = Sequent::ApplicationRecord.connection.select_all %Q(
SELECT 1 FROM pg_database
 WHERE datname = '#{database_name}'
)
    results.count == 1
  end

  def table_exists?(table_name)
    results = Sequent::ApplicationRecord.connection.select_all %Q(
SELECT 1 FROM pg_tables
 WHERE tablename = '#{table_name}'
)
    results.count == 1
  end
end
