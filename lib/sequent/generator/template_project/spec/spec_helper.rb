require 'bundler/setup'
Bundler.setup

require 'sequent/test'

# setup sequent
# Always use the fake event store in this case
Sequent.configuration.event_store = Sequent::Test::CommandHandlerHelpers::FakeEventStore.new

RSpec.configure do |config|
  config.include Sequent::Test::CommandHandlerHelpers

  config.before :each do
    Sequent.configuration.aggregate_repository.clear
  end
end
