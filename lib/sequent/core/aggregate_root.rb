require_relative 'helpers/self_applier'
require_relative 'stream_record'

module Sequent
  module Core
    module SnapshotConfiguration
      module ClassMethods
        def enable_snapshots(threshold = 20)
          @snapshot_threshold = threshold
          on SnapshotEvent do |event|
            load_from_snapshot event
          end
        end

        attr_reader :snapshot_threshold
      end

      def self.included(host_class)
        host_class.extend(ClassMethods)
      end
    end

    # Base class for all your domain classes.
    #
    # +load_from_history+ functionality to be loaded_from_history, meaning a stream of events.
    #
    class AggregateRoot
      include Helpers::SelfApplier
      include SnapshotConfiguration

      attr_reader :id, :uncommitted_events, :sequence_number, :event_stream

      def self.load_from_history(stream, events)
        aggregate_root = allocate() # allocate without calling new
        aggregate_root.load_from_history(stream, events)
        aggregate_root
      end

      def initialize(id)
        @id = id
        @uncommitted_events = []
        @sequence_number = 1
        @event_stream = EventStream.new aggregate_type: self.class.name,
                                        aggregate_id: id,
                                        snapshot_threshold: self.class.snapshot_threshold
      end

      def load_from_history(stream, events)
        raise "Empty history" if events.empty?
        @id = events.first.aggregate_id
        @uncommitted_events = []
        @sequence_number = events.last.sequence_number + 1
        @event_stream = stream
        events.each { |event| handle_message(event) }
      end

      def to_s
        "#{self.class.name}: #{@id}"
      end

      def clear_events
        @uncommitted_events = []
      end

      def take_snapshot!
        snapshot = build_event SnapshotEvent, data: self.save_to_snapshot
        @uncommitted_events << snapshot
      end

      protected

      def build_event(event, params = {})
        event.new({aggregate_id: @id, sequence_number: @sequence_number}.merge(params))
      end

      # Provide subclasses nice DSL to 'apply' events via:
      #
      #   def send_invoice
      #     apply InvoiceSentEvent, send_date: DateTime.now
      #   end
      #
      def apply(event, params={})
        event = build_event(event, params) if event.is_a?(Class)
        handle_message(event)
        @uncommitted_events << event
        @sequence_number += 1
      end
    end

    # You can use this class when running in a multi tenant environment
    # It basically makes sure that the +organization_id+ (the tenant_id for historic reasons)
    # is available for the subclasses
    class TenantAggregateRoot < AggregateRoot
      attr_reader :organization_id

      def initialize(id, organization_id)
        super(id)
        @organization_id = organization_id
      end

      def load_from_history(stream, events)
        raise "Empty history" if events.empty?
        @organization_id = events.first.organization_id
        super
      end

      protected

      def build_event(event, params = {})
        super(event, {organization_id: @organization_id}.merge(params))
      end
    end
  end
end
