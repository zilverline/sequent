# frozen_string_literal: true

require 'base64'
require_relative 'helpers/message_handler'
require_relative 'helpers/autoset_attributes'
require_relative 'stream_record'
require_relative 'aggregate_roots'

module Sequent
  module Core
    module SnapshotConfiguration
      module ClassMethods
        ##
        # Enable snapshots for this aggregate. The aggregate instance
        # must define the *take_snapshot* methods.
        #
        def enable_snapshots(default_threshold: 20)
          @snapshot_default_threshold = default_threshold
        end

        def snapshots_enabled?
          !snapshot_default_threshold.nil?
        end

        attr_reader :snapshot_default_threshold
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
      include Helpers::MessageHandler
      include Helpers::AutosetAttributes
      include SnapshotConfiguration
      extend ActiveSupport::DescendantsTracker

      attr_reader :id, :uncommitted_events, :sequence_number
      attr_accessor :latest_snapshot_sequence_number

      def self.load_from_history(stream, events)
        first, *rest = events
        if first.is_a? SnapshotEvent
          # rubocop:disable Security/MarshalLoad
          aggregate_root = Marshal.load(Base64.decode64(first.data))
          # rubocop:enable Security/MarshalLoad
          aggregate_root.latest_snapshot_sequence_number = first.sequence_number
          rest.each { |x| aggregate_root.apply_event(x) }
        else
          aggregate_root = allocate # allocate without calling new
          aggregate_root.load_from_history(stream, events)
        end
        aggregate_root
      end

      def initialize(id)
        @id = id
        @uncommitted_events = []
        @sequence_number = 1
      end

      def load_from_history(stream, events)
        fail 'Empty history' if events.empty?

        @id = events.first.aggregate_id
        @uncommitted_events = []
        @sequence_number = 1
        @event_stream = stream
        events.each { |event| apply_event(event) }
      end

      def initialize_for_streaming(stream)
        @uncommitted_events = []
        @sequence_number = 1
        @event_stream = stream
      end

      def stream_from_history(stream_events)
        _stream, event = stream_events
        fail 'Empty history' if event.blank?

        @id ||= event.aggregate_id
        apply_event(event)
      end

      def self.stream_from_history(stream)
        aggregate_root = allocate
        aggregate_root.initialize_for_streaming(stream)
        aggregate_root
      end

      def to_s
        "#{self.class.name}: #{@id}"
      end

      def unique_keys
        {}
      end

      def event_stream
        EventStream.new(
          aggregate_type: self.class.name,
          aggregate_id: id,
          events_partition_key: events_partition_key,
          snapshot_outdated_at: snapshot_outdated? ? Time.now : nil,
          unique_keys:,
        )
      end

      # Provide the partitioning key for storing events. This value
      # must be a string and will be used by PostgreSQL to store the
      # events in the right partition.
      #
      # The value may change over the lifetime of the aggregate, old
      # events will be moved to the correct partition after a
      # change. This can be an expensive database operation.
      def events_partition_key
        nil
      end

      def clear_events
        @uncommitted_events = []
      end

      def snapshot_outdated?
        snapshot_threshold = self.class.snapshot_default_threshold
        events_since_latest_snapshot = @sequence_number - (latest_snapshot_sequence_number || 1)
        snapshot_threshold.present? && events_since_latest_snapshot >= snapshot_threshold
      end

      def take_snapshot
        build_event SnapshotEvent, data: Base64.encode64(Marshal.dump(self))
      end

      def apply_event(event)
        handle_message(event)
        @sequence_number = event.sequence_number + 1
      end

      protected

      def build_event(event, params = {})
        event.new(params.merge({aggregate_id: @id, sequence_number: @sequence_number}))
      end

      # Provide subclasses nice DSL to 'apply' events via:
      #
      #   def send_invoice
      #     apply InvoiceSentEvent, send_date: Time.now
      #   end
      #
      def apply(event, params = {})
        event = build_event(event, params) if event.is_a?(Class)
        apply_event(event)
        @uncommitted_events << event
      end

      # Only apply the event if one of the attributes of the event changed
      #
      # on NameSet do |event|
      #   @first_name = event.first_name
      #   @last_name = event.last_name
      # end
      #
      # # The event is applied
      # apply_if_changed NameSet, first_name: 'Ben', last_name: 'Vonk'
      #
      # # This event is not applied
      # apply_if_changed NameSet, first_name: 'Ben', last_name: 'Vonk'
      #
      def apply_if_changed(event_class, args = {})
        if args.empty?
          apply event_class
        elsif self.class
            .event_attribute_keys(event_class)
            .any? { |k| instance_variable_get(:"@#{k}") != args[k.to_sym] }
          apply event_class, args
        end
      end
    end
  end
end
