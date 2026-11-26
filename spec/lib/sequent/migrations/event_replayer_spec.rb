# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Migrations::EventReplayer do
  let(:replayer) { Class.new { include Sequent::Migrations::EventReplayer }.new }
  let(:event_store) { Sequent.configuration.event_store }
  let(:aggregate_ids) { %w[11111111 55555555 99999999].map { |prefix| "#{prefix}-0000-4000-8000-000000000000" } }
  let(:keys) { %w[a b c].product(aggregate_ids) }
  let(:event_type_ids) { Sequent::Internal::EventType.where(type: 'Sequent::Core::Event').pluck(:id) }

  def endpoint(key) = key && Sequent::Migrations::Grouper::GroupEndpoint.new(*key)

  def streamed_keys(group)
    replayer
      .event_stream(group, event_type_ids, nil, nil)
      .reselect('events.partition_key, events.aggregate_id')
      .map { |event| [event.partition_key, event.aggregate_id] }
  end

  before do
    keys.each do |events_partition_key, aggregate_id|
      event_store.commit_events(
        Sequent::Core::Command.new(aggregate_id:),
        [
          [
            Sequent::Core::EventStream.new(aggregate_type: 'Aggregate', aggregate_id:, events_partition_key:),
            [Sequent::Core::Event.new(aggregate_id:, sequence_number: 1)],
          ],
        ],
      )
    end
  end

  describe '#event_stream' do
    it 'streams the events from the begin up to the end of the group, in order' do
      bounds = [nil, *keys]
      bounds.product(bounds, [true, false]).each do |lower, upper, exclude_end|
        group = Range.new(endpoint(lower), endpoint(upper), exclude_end)
        expected = keys.select do |key|
          (lower.nil? || (key <=> lower) >= 0) &&
            (upper.nil? || (exclude_end ? (key <=> upper).negative? : (key <=> upper) <= 0))
        end

        expect(streamed_keys(group))
          .to eq(expected), "group #{lower.inspect} #{exclude_end ? '...' : '..'} #{upper.inspect}"
      end
    end
  end
end
