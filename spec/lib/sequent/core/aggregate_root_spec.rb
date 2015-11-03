require 'spec_helper'

describe Sequent::Core::AggregateRoot do

  class TestEvent < Sequent::Core::Event
    attrs field: String
  end

  class TestAggregateRoot < Sequent::Core::AggregateRoot
    attr_accessor :test_event_count

    enable_snapshots default_threshold: 30

    def initialize(params)
      super(params[:aggregate_id])
    end

    def generate_event
      apply TestEvent, field: "value"
    end

    def event_count
      @event_count ||= 0
    end

    private
    on TestEvent do |_|
      @event_count = event_count + 1
    end
  end

  let(:subject) { TestAggregateRoot.new(aggregate_id: "identifier", organization_id: "foo") }

  it "has an aggregate id" do
    expect(subject.id).to eq "identifier"
  end

  it "generates events with the aggregate_id set" do
    subject.generate_event
    expect(subject.uncommitted_events[0].aggregate_id).to eq "identifier"
  end

  it "generates sequence numbers starting with 1" do
    subject.generate_event
    expect(subject.uncommitted_events[0].sequence_number).to eq 1
  end

  it "generates consecutive sequence numbers" do
    subject.generate_event
    subject.generate_event
    expect(subject.uncommitted_events[0].sequence_number).to eq 1
    expect(subject.uncommitted_events[1].sequence_number).to eq 2
  end

  it "starts sequence numberings based on history" do
    subject = TestAggregateRoot.load_from_history :stream, [TestEvent.new(aggregate_id: "historical_id", sequence_number: 1, organization_id: "foo", field: "value")]
    subject.generate_event
    expect(subject.uncommitted_events[0].sequence_number).to eq 2
  end

  it "passes data to generated event" do
    subject.generate_event
    expect(subject.uncommitted_events[0].field).to eq "value"
  end

  it "clears uncommitted events" do
    subject.generate_event
    subject.clear_events
    expect(subject.uncommitted_events).to be_empty
  end

  it "has a nice to_s for readability" do
    expect(subject.to_s).to eq "TestAggregateRoot: identifier"
  end

  context "snapshotting" do
    before { subject.generate_event }

    it "adds an uncommitted snapshot event" do
      expect {
        subject.take_snapshot!
      }.to change { subject.uncommitted_events.count }.by(1)
    end

    it "restores state from the snapshot" do
      subject.take_snapshot!
      snapshot_event = subject.uncommitted_events.last
      restored = TestAggregateRoot.load_from_history :stream, [snapshot_event]
      expect(restored.event_count).to eq 1
    end
  end
end
