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
  let(:snapshot_threshold) { 1 }
  let(:events) { [MyEvent.new(aggregate_id: aggregate_id, sequence_number: 1)] }

  before :each do
    Sequent::configuration.command_handlers << described_class.new
    event_store.commit_events(
      Sequent::Core::CommandRecord.new,
      [
        [
          Sequent::Core::EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id, snapshot_threshold: 1),
          events
        ]
      ]
    )
  end

  it 'can take a snapshot' do
    Sequent.command_service.execute_commands(*take_snapshot)

    expect(Sequent::Core::EventRecord.last.event_type).to eq Sequent::Core::SnapshotEvent.name
  end

  context 'loads aggregates with snapshots' do
    let(:snapshot_threshold) { 2 }
    let(:events) { [MyEvent.new(aggregate_id: aggregate_id, sequence_number: 1), MyEvent.new(aggregate_id: aggregate_id, sequence_number: 2), MyEvent.new(aggregate_id: aggregate_id, sequence_number: 3)] }

    let(:aggregate_id_2) { Sequent.new_uuid }

    before :each do
      event_store.commit_events(
        Sequent::Core::CommandRecord.new,
        [
          [
            Sequent::Core::EventStream.new(aggregate_type: 'MyAggregate', aggregate_id: aggregate_id_2, snapshot_threshold: 10),
            [MyEvent.new(aggregate_id: aggregate_id_2, sequence_number: 1)]
          ]
        ]
      )

      Sequent.command_service.execute_commands(*take_snapshot)
    end

    it 'loads both events' do
      expect(event_store.load_events_for_aggregates([aggregate_id, aggregate_id_2])).to have(2).items
    end
  end
end
