require 'spec_helper'

require 'sequent/support'

class ArSessionTest < ActiveRecord::Base; end

describe Sequent::Core::RecordSessions::ActiveRecordSession do
  let(:migrations_path) { File.expand_path(database_name, Dir.tmpdir).tap { |dir| Dir.mkdir(dir) } }
  let(:database_name) { Sequent.new_uuid }
  let(:db_config) do
    {'adapter' => 'postgresql',
     'host' => 'localhost',
     'database' => database_name}
  end
  before do
    Sequent::Support::Database.create!(db_config)
    Sequent::Support::Database.establish_connection(db_config)
  end
  after { Sequent::Support::Database.drop!(db_config) }

  let(:database) { Sequent::Support::Database.new }

  after { FileUtils.rm_rf(migrations_path) }

  before :each do
    File.open(File.expand_path("1_test_migration.rb", migrations_path), 'w') do |f|
      f.write <<EOF
if ActiveRecord::VERSION::MAJOR <= 4
  MigrationClass = ActiveRecord::Migration
else
  MigrationClass = ActiveRecord::Migration['4.2']
end

class TestMigration < MigrationClass
  def change
    create_table "ar_session_tests" do |t|
      t.string "name", null: false
      t.string "initials", default: [], array:true
    end
  end
end
EOF
      f.flush
      database.migrate(migrations_path, verbose: false)
    end

  end

  let(:session) { Sequent::Core::RecordSessions::ActiveRecordSession.new }

  context 'create_records' do
    it 'can insert records by batch' do
      expect { session.create_records(ArSessionTest, [{name: 'kim'}, {name: 'ben'}]) }.to change { ArSessionTest.count }.by(2)
    end

    it 'can insert array values' do
      expect { session.create_records(ArSessionTest, [{name: 'john', initials: ['j', 'f']}]) }.to change { ArSessionTest.count }.by(1)
    end
  end

end

