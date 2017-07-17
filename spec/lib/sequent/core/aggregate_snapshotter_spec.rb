require 'spec_helper'

describe Sequent::Core::AggregateSnapshotter do
  class MyEvent < Sequent::Core::Event; end
  class MyAggregate < Sequent::Core::AggregateRoot; end

  let(:command_handler) { described_class.new }
  let(:event_store) { Sequent::configuration.event_store }
  let(:aggregate_id) { Sequent.new_uuid }

  let(:take_snapshot) { Sequent::Core::TakeSnapshot.new(aggregate_id: aggregate_id) }

  around do |example|
    commands_handlers = Sequent::configuration.command_handlers
    begin
      example.run
    ensure
      Sequent::configuration.command_handlers = commands_handlers
    end
  end

  before :each do
    Sequent::configuration.command_handlers << described_class.new
    event_store.commit_events(
      Sequent::Core::CommandRecord.new,
      [
        [
          Sequent::Core::EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id, snapshot_threshold: 1),
          [MyEvent.new(aggregate_id: aggregate_id, sequence_number: 1)]
        ]
      ]
    )
  end

  it 'can take a snapshot' do
    Sequent.command_service.execute_commands(*take_snapshot)

    expect(Sequent::Core::EventRecord.last.event_type).to eq Sequent::Core::SnapshotEvent.name
  end
end
