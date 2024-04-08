# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::AggregateRoot do
  class TestEvent < Sequent::Core::Event
    attrs field: String, organization_id: String
  end

  class TestAggregateRoot < Sequent::Core::AggregateRoot
    attr_accessor :test_event_count

    enable_snapshots default_threshold: 30

    def initialize(params)
      super(params[:aggregate_id])
    end

    def generate_event
      apply TestEvent, field: 'value'
    end

    def event_count
      @event_count ||= 0
    end

    on TestEvent do |_|
      @event_count = event_count + 1
    end
  end

  let(:subject) { TestAggregateRoot.new(aggregate_id: 'identifier', organization_id: 'foo') }

  it 'has an aggregate id' do
    expect(subject.id).to eq 'identifier'
  end

  it 'generates events with the aggregate_id set' do
    subject.generate_event
    expect(subject.uncommitted_events[0].aggregate_id).to eq 'identifier'
  end

  it 'generates sequence numbers starting with 1' do
    subject.generate_event
    expect(subject.uncommitted_events[0].sequence_number).to eq 1
  end

  it 'generates consecutive sequence numbers' do
    subject.generate_event
    subject.generate_event
    expect(subject.uncommitted_events[0].sequence_number).to eq 1
    expect(subject.uncommitted_events[1].sequence_number).to eq 2
  end

  it 'starts sequence numberings based on history' do
    subject = TestAggregateRoot.load_from_history :stream,
                                                  [
                                                    TestEvent.new(
                                                      aggregate_id: 'historical_id',
                                                      sequence_number: 1,
                                                      organization_id: 'foo',
                                                      field: 'value',
                                                    ),
                                                  ]
    subject.generate_event
    expect(subject.uncommitted_events[0].sequence_number).to eq 2
  end

  it 'passes data to generated event' do
    subject.generate_event
    expect(subject.uncommitted_events[0].field).to eq 'value'
  end

  it 'clears uncommitted events' do
    subject.generate_event
    subject.clear_events
    expect(subject.uncommitted_events).to be_empty
  end

  it 'has a nice to_s for readability' do
    expect(subject.to_s).to eq 'TestAggregateRoot: identifier'
  end

  context 'snapshotting' do
    before { subject.generate_event }

    it 'returns a snapshot event' do
      snapshot = subject.take_snapshot
      expect(snapshot.aggregate_id).to be(subject.id)
      expect(snapshot.sequence_number).to eq(2)
      expect(snapshot.data).to be_present
    end

    it 'restores state from the snapshot' do
      snapshot_event = subject.take_snapshot
      restored = TestAggregateRoot.load_from_history :stream, [snapshot_event]
      expect(restored.event_count).to eq 1
    end
  end

  context 'AutosetAttributes' do
    require_relative 'fixtures'

    it 'autosets attributes' do
      subject = PersonAggregate.new('1')

      subject.set_name('kim', 'bos')
      expect(subject.first_name).to eq 'kim'
      expect(subject.last_name).to eq 'bos'

      subject.set_name('bos', 'kim')
      expect(subject.first_name).to eq 'bos'
      expect(subject.last_name).to eq 'kim'
    end

    context 'given a message matcher argument' do
      it 'autosets attributes' do
        subject = PersonAggregate.new('2')

        subject.set_age(12)
        expect(subject.age).to eq 12
        expect(subject.status).to eq(:immature)

        subject.set_age(20)
        expect(subject.age).to eq 20
        expect(subject.status).to eq(:mature)
      end
    end
  end

  context 'apply_if_changed' do
    require_relative 'fixtures'

    it 'only applies the event if one of the attributes changes' do
      subject = PersonAggregate.new('1')
      subject.clear_events

      subject.set_name_if_changed('kim', 'bos')
      subject.set_name_if_changed('kim', 'bos')
      expect(subject.uncommitted_events).to have(1).item

      subject = PersonAggregate.new('1')
      subject.clear_events
      subject.set_name_if_changed('kim', 'bos')
      subject.set_name_if_changed('kim2', 'bos')
      expect(subject.uncommitted_events).to have(2).items

      subject = PersonAggregate.new('1')
      subject.clear_events
      subject.set_name_if_changed('kim', 'bos')
      subject.set_name_if_changed('kim', 'bos2')
      expect(subject.uncommitted_events).to have(2).items
    end
  end

  context 'strict_check_attributes_on_apply_events' do
    require_relative 'fixtures'
    before do
      Sequent.configure do |c|
        c.strict_check_attributes_on_apply_events = true
      end
    end

    it 'fails when calling apply with unknown attributes' do
      subject = PersonAggregate.new('1')
      subject.clear_events
      expect do
        subject.set_name_with_unknown_event_attribute
      end.to raise_error(Sequent::Core::Helpers::AttributeSupport::UnknownAttributeError)
    end
  end
end
