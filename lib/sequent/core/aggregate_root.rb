require 'base64'
require_relative 'helpers/self_applier'
require_relative 'stream_record'

module Sequent
  module Core
    module SnapshotConfiguration
      module ClassMethods
        ##
        # Enable snapshots for this aggregate. The aggregate instance
        # must define the *load_from_snapshot* and *save_to_snapshot*
        # methods.
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
      include Helpers::SelfApplier
      include SnapshotConfiguration

      attr_reader :id, :uncommitted_events, :sequence_number, :event_stream

      class DomainError < RuntimeError
        attr_reader :i18n_parameters

        def initialize(i18n_parameters = {})
          @i18n_parameters = i18n_parameters
        end

        def message
          I18n.t(i18n_key, i18n_parameters)
        end

        def i18n_key
          "errors.#{self.class.name}"
        end
      end

      def self.load_from_history(stream, events)
        first, *rest = events
        if first.is_a? SnapshotEvent
          aggregate_root = Marshal.load(Base64.decode64(first.data))
          rest.each { |x| aggregate_root.apply_event(x) }
        else
          aggregate_root = allocate() # allocate without calling new
          aggregate_root.load_from_history(stream, events)
        end
        aggregate_root
      end

      def initialize(id)
        @id = id
        @uncommitted_events = []
        @sequence_number = 1
        @event_stream = EventStream.new aggregate_type: self.class.name,
                                        aggregate_id: id,
                                        snapshot_threshold: self.class.snapshot_default_threshold
      end

      def load_from_history(stream, events)
        raise "Empty history" if events.empty?
        @id = events.first.aggregate_id
        @uncommitted_events = []
        @sequence_number = 1
        @event_stream = stream
        events.each { |event| apply_event(event) }
      end

      def to_s
        "#{self.class.name}: #{@id}"
      end

      def clear_events
        @uncommitted_events = []
      end

      def take_snapshot!
        snapshot = build_event SnapshotEvent, data: Base64.encode64(Marshal.dump(self))
        @uncommitted_events << snapshot
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
      #     apply InvoiceSentEvent, send_date: DateTime.now
      #   end
      #
      def apply(event, params={})
        event = build_event(event, params) if event.is_a?(Class)
        apply_event(event)
        @uncommitted_events << event
      end
    end
  end
end
