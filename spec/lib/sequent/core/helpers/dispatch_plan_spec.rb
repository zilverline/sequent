# frozen_string_literal: true

require 'spec_helper'

class DispatchPlanEvent < Sequent::Core::Event; end
class DispatchPlanOtherEvent < Sequent::Core::Event; end
class DispatchPlanUnhandledEvent < Sequent::Core::Event; end

# Matches when the projector handled an event before, so it depends on state changed by an earlier event handler.
DispatchPlanHandledMatcher = Data.define(:event_class) do
  def matches_message?(message) = message.is_a?(event_class) && DispatchPlanProjector.handled.any?
end

# Fails to match any message.
DispatchPlanFailingMatcher = Data.define do
  def matches_message?(_message) = fail('matcher failed')
end

class DispatchPlanProjector < Sequent::Core::Projector
  self.skip_autoregister = true
  manages_no_tables

  class << self
    attr_accessor :handled
  end

  on DispatchPlanEvent do |event|
    self.class.handled << event.sequence_number
  end

  on DispatchPlanOtherEvent do |event|
    self.class.handled << event.sequence_number
  end
end

class DispatchPlanWorkflow < Sequent::Core::Workflow
  self.skip_autoregister = true

  attr_reader :handled

  def initialize
    super
    @handled = []
  end

  on DispatchPlanHandledMatcher.new(DispatchPlanEvent) do |event|
    @handled << event.sequence_number
  end
end

describe Sequent::Core::Helpers::DispatchPlan do
  let(:workflow) { DispatchPlanWorkflow.new }
  let(:event_handlers) { [DispatchPlanProjector, workflow] }
  let(:plan) { described_class.new(event_handlers) }

  before { DispatchPlanProjector.handled = [] }

  def event(event_class, sequence_number)
    event_class.new(aggregate_id: Sequent.new_uuid, sequence_number:)
  end

  it 'has the entries of the event handlers that may handle an event, in order' do
    entries = plan.entries(event(DispatchPlanEvent, 1))

    expect(entries.map(&:event_handler)).to eq [DispatchPlanProjector, workflow]
    expect(entries.first.for_event(event(DispatchPlanEvent, 1)).handler_blocks)
      .to eq DispatchPlanProjector.message_router.match_message(event(DispatchPlanEvent, 2))
  end

  it 'leaves out the event handlers that only match other event classes' do
    expect(plan.entries(event(DispatchPlanUnhandledEvent, 1)).map(&:event_handler)).to eq [workflow]
  end

  it 'matches event handlers that only match event classes once per event class' do
    expect(DispatchPlanProjector.message_router).to receive(:match_message).twice.and_call_original

    3.times { |i| plan.entries(event(DispatchPlanEvent, i)) }
    2.times { |i| plan.entries(event(DispatchPlanOtherEvent, i)) }
  end

  it 'matches the other event handlers for every event, when asked' do
    expect(DispatchPlanWorkflow.message_router).to receive(:match_message).exactly(3).times.and_call_original

    3.times do |i|
      event = event(DispatchPlanEvent, i)
      plan.entries(event).each { |entry| entry.for_event(event) }
    end
  end

  it 'has the handler blocks of an event handler for an event' do
    expect(plan.handler_blocks(event(DispatchPlanEvent, 1), DispatchPlanProjector).size).to eq 1
    expect(plan.handler_blocks(event(DispatchPlanUnhandledEvent, 1), DispatchPlanProjector)).to be_empty
  end

  it 'tells whether an event handler handles any of the events' do
    expect(plan.handles_any?(DispatchPlanProjector, [event(DispatchPlanUnhandledEvent, 1)])).to be false
    expect(
      plan.handles_any?(
        DispatchPlanProjector,
        [event(DispatchPlanUnhandledEvent, 1), event(DispatchPlanEvent, 2)],
      ),
    )
      .to be true
  end

  context 'when publishing events inline' do
    let(:publisher) { Sequent::Core::InlineEventPublisher.new }

    it 'matches an event handler when its turn comes, after the event handlers before it' do
      publisher.publish_events([event(DispatchPlanEvent, 1)], event_handlers:)

      expect(DispatchPlanProjector.handled).to eq [1]
      expect(workflow.handled).to eq [1]
    end

    it 'raises a PublishEventError when a matcher fails' do
      failing_workflow = Class.new(Sequent::Core::Workflow) do
        self.skip_autoregister = true
        on(DispatchPlanFailingMatcher.new) { |_event| nil }
      end

      expect { publisher.publish_events([event(DispatchPlanEvent, 1)], event_handlers: [failing_workflow.new]) }
        .to raise_error(Sequent::Core::PublishEventError) { |error|
          expect(error.event_handler_class).to eq failing_workflow
          expect(error.cause.message).to eq 'matcher failed'
        }
    end
  end

  context 'when publishing events in bulk' do
    let(:publisher) { Sequent::Core::BulkEventPublisher.new }

    it 'passes the handler blocks of the plan to the event handlers' do
      expect(DispatchPlanProjector.message_router).to receive(:match_message).twice.and_call_original

      publisher.publish_events(
        [event(DispatchPlanEvent, 1), event(DispatchPlanOtherEvent, 2), event(DispatchPlanEvent, 3)],
        event_handlers: [DispatchPlanProjector],
      )

      expect(DispatchPlanProjector.handled).to eq [1, 2, 3]
    end
  end
end
