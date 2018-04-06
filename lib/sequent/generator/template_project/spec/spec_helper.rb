require 'bundler/setup'
Bundler.setup

require 'sequent/test'
require 'database_cleaner'

require_relative '../my_app'

Sequent::Support::Database.establish_connection(MyApp::DB_CONFIG['test'])
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
