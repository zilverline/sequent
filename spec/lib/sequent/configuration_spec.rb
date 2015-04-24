require 'spec_helper'

describe Sequent::Configuration do
  let(:instance) { described_class.instance }

  it 'configures a new aggregate store if the event store changes' do
    new_event_store = double
    Sequent.configuration.event_store = new_event_store
    expect(Sequent.configuration.aggregate_repository.instance_variable_get(:@event_store)).to eq new_event_store
  end
end
