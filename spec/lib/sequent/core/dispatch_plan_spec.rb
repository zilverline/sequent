# frozen_string_literal: true

require 'spec_helper'

class DispatchPlanEvent < Sequent::Core::Event; end
class DispatchPlanOtherEvent < Sequent::Core::Event; end
class DispatchPlanUnhandledEvent < Sequent::Core::Event; end

class DispatchPlanProjector < Sequent::Core::Projector
  self.skip_autoregister = true
  manages_no_tables

  attr_reader :handled

  def initialize(...)
    super
    @handled = []
  end

  around_handler :record_around

  def record_around(messages)
    @handled << [:around, messages.first.class]
    yield
  end

  on DispatchPlanEvent do |event|
    fail 'failed to handle' if event.sequence_number == 99

    @handled << [:on, event.sequence_number]
  end

  on DispatchPlanOtherEvent do |event|
    @handled << [:other, event.sequence_number]
  end
end

class DispatchPlanWorkflow < Sequent::Core::Workflow
  self.skip_autoregister = true

  attr_reader :handled

  def initialize
    super
    @handled = []
  end

  on is_a(Sequent::Core::Event) do |event|
    @handled << event.sequence_number
  end
end

class DispatchPlanOverridingHandler < Sequent::Core::Workflow
  self.skip_autoregister = true

  attr_reader :handled

  def initialize
    super
    @handled = []
  end

  def handle_message(message)
    @handled << message.sequence_number
  end
end

describe Sequent::Core::DispatchPlan do
  let(:projector) { DispatchPlanProjector.new }
  let(:workflow) { DispatchPlanWorkflow.new }
  let(:event_handlers) { [projector, workflow] }
  let(:plan) { described_class.new(event_handlers) }

  def event(event_class, sequence_number)
    event_class.new(aggregate_id: Sequent.new_uuid, sequence_number:)
  end

  it 'matches the event handlers that handle an event, in order, with their handler blocks' do
    matches = plan.matches(event(DispatchPlanEvent, 1))

    expect(matches.map(&:event_handler)).to eq [projector, workflow]
    expect(matches.first.handler_blocks)
      .to eq DispatchPlanProjector.message_router.match_message(event(DispatchPlanEvent, 2))
  end

  it 'leaves out the event handlers that do not handle an event' do
    expect(plan.matches(event(DispatchPlanUnhandledEvent, 1)).map(&:event_handler)).to eq [workflow]
  end

  it 'matches event handlers that only match event classes once per event class' do
    expect(DispatchPlanProjector.message_router).to receive(:match_message).twice.and_call_original

    3.times { |i| plan.matches(event(DispatchPlanEvent, i)) }
    2.times { |i| plan.matches(event(DispatchPlanOtherEvent, i)) }
  end

  it 'matches event handlers with other matchers for every event' do
    expect(DispatchPlanWorkflow.message_router).to receive(:match_message).exactly(3).times.and_call_original

    3.times { |i| plan.matches(event(DispatchPlanEvent, i)) }
  end

  it 'passes every event to an event handler that overrides handle_message' do
    handler = DispatchPlanOverridingHandler.new
    plan = described_class.new([handler])

    plan.matches(event(DispatchPlanUnhandledEvent, 1)).each { |match| match.dispatch(event(DispatchPlanEvent, 1)) }

    expect(handler.handled).to eq [1]
  end

  it 'passes every event to an event handler that is not a message handler' do
    handler = Struct.new(:handled) { def handle_message(message) = handled << message.sequence_number }.new([])
    plan = described_class.new([handler])

    expect(plan.matches(event(DispatchPlanEvent, 1)).map(&:event_handler)).to eq [handler]
  end

  context 'when publishing events' do
    before { Sequent.configuration.event_handlers = event_handlers }

    it 'dispatches the events to the handler blocks, running the hooks' do
      Sequent.configuration.event_publisher.publish_events(
        [event(DispatchPlanEvent, 1), event(DispatchPlanOtherEvent, 2), event(DispatchPlanEvent, 3)],
      )

      expect(projector.handled).to eq [
        [:around, DispatchPlanEvent],
        [:on, 1],
        [:around, DispatchPlanOtherEvent],
        [:other, 2],
        [:around, DispatchPlanEvent],
        [:on, 3],
      ]
      expect(workflow.handled).to eq [1, 2, 3]
    end

    it 'raises a PublishEventError for the event handler that failed' do
      expect { Sequent.configuration.event_publisher.publish_events([event(DispatchPlanEvent, 99)]) }
        .to raise_error(Sequent::Core::EventPublisher::PublishEventError) { |error|
          expect(error.event_handler_class).to eq DispatchPlanProjector
        }
    end
  end
end
