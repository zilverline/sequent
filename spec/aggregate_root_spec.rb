require 'spec_helper'

describe Sequent::Core::AggregateRoot do

  class TestEvent < Sequent::Core::TenantEvent
    attrs field: String
  end

  class TestAggregateRoot < Sequent::Core::TenantAggregateRoot
    attr_accessor :test_event_count

    def initialize(params)
      super(params[:aggregate_id], params[:organization_id])
    end

    def generate_event
      apply TestEvent, field: "value"
    end

    private
    on TestEvent do |_|

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
    subject = TestAggregateRoot.load_from_history [TestEvent.new(aggregate_id: "historical_id", sequence_number: 1, organization_id: "foo", field: "value")]
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

end
