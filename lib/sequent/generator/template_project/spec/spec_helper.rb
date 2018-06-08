require 'bundler/setup'
Bundler.setup

ENV['RACK_ENV'] ||= 'test'

require 'sequent/test'
require 'database_cleaner'

require_relative '../my_app'

db_config = Sequent::Support::Database.read_config('test')
Sequent::Support::Database.establish_connection(db_config)

Sequent::Support::Database.drop_schema!(Sequent.configuration.view_schema_name)

Sequent::Migrations::ViewSchema.new(db_config: db_config).create_view_tables
Sequent.configuration.event_store = Sequent::Test::CommandHandlerHelpers::FakeEventStore.new

RSpec.configure do |config|
  config.include Sequent::Test::CommandHandlerHelpers

  config.around do |example|
    Sequent.configuration.aggregate_repository.clear
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
