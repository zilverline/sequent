require_relative 'helpers/self_applier'

module Sequent
  module Core
    class AggregateRoot
      include Helpers::SelfApplier

      attr_reader :id, :uncommitted_events, :sequence_number

      def self.load_from_history(events)
        aggregate_root = allocate()
        aggregate_root.load_from_history(events)
        aggregate_root
      end

      def initialize(id)
        @id = id
        @uncommitted_events = []
        @sequence_number = 1
      end

      def load_from_history(events)
        raise "Empty history" if events.empty?
        @id = events.first.aggregate_id
        @uncommitted_events = []
        @sequence_number = events.size + 1
        events.each { |event| handle_message(event) }
      end

      def to_s
        "#{self.class.name}: #{@id}"
      end


      def clear_events
        uncommitted_events.clear
      end

      protected

      def build_event(event, params = {})
        event.new({aggregate_id: @id, sequence_number: @sequence_number}.merge(params))
      end

      def apply(event, params={})
        event = build_event(event, params) if event.is_a?(Class)
        handle_message(event)
        @uncommitted_events << event
        @sequence_number += 1
      end
    end

    class TenantAggregateRoot < AggregateRoot
      attr_reader :organization_id

      def initialize(id, organization_id)
        super(id)
        @organization_id = organization_id
      end

      def load_from_history(events)
        raise "Empty history" if events.empty?
        @organization_id = events.first.organization_id
        super(events)
      end

      protected

      def build_event(event, params = {})
        super(event, {organization_id: @organization_id}.merge(params))
      end
    end
  end
end
