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

ActiveRecord::Base.configurations = YAML.load_file('db/database.yml', aliases: true)
ActiveRecord::Base.establish_connection(:test)

RSpec.configure do |config|
  config.include Sequent::Test::CommandHandlerHelpers
  config.include DomainTests, file_path: %r{/spec\/lib/}

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
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.cleaning do
      example.run
    ensure
      Sequent.configuration.aggregate_repository.clear
    end
  end
end
