# frozen_string_literal: true

require 'bundler/setup'
Bundler.setup

ENV['SEQUENT_ENV'] ||= 'test'

require 'sequent/test'
require 'database_cleaner'

require_relative '../my_app'

module DomainTests
  def self.included(base)
    base.metadata[:domain_tests] = true
  end
end

RSpec.configure do |config|
  config.include Sequent::Test::CommandHandlerHelpers
  config.include DomainTests, file_path: %r{/spec\/lib/}

  config.before :suite do
    Sequent::Support::Database.connect!('test')
    Sequent::Support::Database.drop_schema!(Sequent.configuration.view_schema_name)

    Sequent::Test::DatabaseHelpers.maintain_test_database_schema(env: 'test')
  end

  # Domain tests run with a clean sequent configuration and the in memory FakeEventStore
  config.around :each, :domain_tests do |example|
    old_config = Sequent.configuration
    Sequent::Configuration.reset
    Sequent.configuration.event_store = Sequent::Test::CommandHandlerHelpers::FakeEventStore.new
    Sequent.configuration.event_handlers = []
    example.run
  ensure
    Sequent::Configuration.restore(old_config)
  end

  config.around do |example|
    Sequent.configuration.aggregate_repository.clear
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.cleaning do
      example.run
    ensure
      Sequent.configuration.aggregate_repository.clear
    end
  end
end
