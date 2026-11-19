# frozen_string_literal: true

require_relative '../json'

module Sequent
  module Core
    class EventSerializationError < RuntimeError
      attr_reader :event, :differences

      def initialize(event, differences)
        @event = event
        @differences = differences
        super(
          "#{event.class} changes when it is stored, so it is applied and projected differently when it is " \
          "loaded or replayed: #{differences.join('; ')}",
        )
      end
    end

    module Helpers
      #
      # Serializes events the way the event stores store them, and deserializes them the way the event stores load
      # them.
      #
      # A replay reads the events from the event store, so it sees them as they are serialized to JSON and deserialized
      # again: times truncated to the +time_precision+, symbols as strings, hashes with string keys and attributes cast
      # to their type. The event stores therefore publish the events as they are stored (see +stored_event+), so
      # projectors and workflows see the same values when the events are stored and when they are replayed.
      #
      # The aggregate that applied an event keeps the values it applied. When
      # +Sequent.configuration.verify_event_serialization+ is set, for instance in specs, storing an event calls
      # +Sequent.configuration.event_serialization_error_handler+ with an EventSerializationError when the event
      # changes other than by truncating its times, so the domain code can be fixed to create the values it stores. The
      # default handler raises the error, which fails the command. Another handler can report it instead.
      #
      module EventSerialization
        ##
        # Deserializes an event from its type and its parsed JSON.
        def deserialize_event_json(event_type, payload)
          Class.const_get(event_type).deserialize_from_json(payload)
        end

        ##
        # Returns +event+ as it is loaded once it is stored. +json+ is the JSON of +event+, when it is dumped already.
        def stored_event(event, json: Json.dump(event))
          ensure_stored_types!(event)
          stored = deserialize_event_json(event.class.name, loaded_event_json(Json.strict_load(json)))
          if Sequent.configuration.verify_event_serialization
            error = EventSerialization.serialization_error(event, stored)
            Sequent.configuration.event_serialization_error_handler.call(error) if error
          end
          stored
        end

        ##
        # Fails when +event+ has another aggregate_id than the +stream+ it is stored in, since it would be stored under
        # the id of the stream but published with its own.
        def self.ensure_stream_aggregate_id!(stream, event)
          return if event.aggregate_id == stream.aggregate_id

          fail ArgumentError,
               "aggregate_id of #{event.class} is #{event.aggregate_id.inspect}, " \
               "not #{stream.aggregate_id.inspect} of its stream"
        end

        # Returns an EventSerializationError when +stored+ has other attribute values than +event+, except for times
        # truncated to the +time_precision+, and nil when it has not. The values are compared as they are kept in the
        # event, not through its readers, which may change them.
        def self.serialization_error(event, stored)
          differences = attribute_differences(event, stored)
          EventSerializationError.new(event, differences) if differences.any?
        end

        TIME_CLASSES = [Time, DateTime, ActiveSupport::TimeWithZone].freeze

        def self.attribute_differences(value, stored, path = nil)
          value.class.types.keys.flat_map do |name|
            differences(
              value.instance_variable_get(:"@#{name}"),
              stored.instance_variable_get(:"@#{name}"),
              path ? "#{path}.#{name}" : name.to_s,
            )
          end
        end

        # A hash with indifferent access or symbol keys behaves differently from the hash with string keys it is
        # stored as, so the class and keys must match as well.
        def self.differences(value, stored, path)
          nested =
            case value
            when *TIME_CLASSES then [] if same_time?(value, stored)
            when Array then array_differences(value, stored, path)
            when Hash then hash_differences(value, stored, path)
            else
              if value.class.respond_to?(:types)
                attributes_differences(value, stored, path) if stored.instance_of?(value.class)
              elsif value.instance_of?(stored.class) && value == stored
                []
              end
            end
          nested || ["#{path}: #{value.inspect} is stored as #{stored.inspect}"]
        end

        # A value object with an equality of its own, like a quantity stored in a normalized form, is the same when it
        # says so. The equality of +EqualSupport+ calls the readers and ignores the class of a hash, so it is not used.
        def self.attributes_differences(value, stored, path)
          return [] if value.class.instance_method(:==).owner != EqualSupport && value == stored

          attribute_differences(value, stored, path)
        end

        def self.same_time?(value, stored)
          return false unless TIME_CLASSES.any? { |time_class| stored.is_a?(time_class) }
          return false unless value.is_a?(DateTime) == stored.is_a?(DateTime)

          precision = Sequent.configuration.time_precision
          value.to_time.getutc.iso8601(precision) == stored.to_time.getutc.iso8601(precision)
        end

        def self.array_differences(value, stored, path)
          return unless value.instance_of?(stored.class) && value.size == stored.size

          value.zip(stored).each_with_index.flat_map { |(v, s), index| differences(v, s, "#{path}[#{index}]") }
        end

        def self.hash_differences(value, stored, path)
          return unless value.instance_of?(stored.class) && value.keys == stored.keys
          return unless value.default == stored.default && value.default_proc == stored.default_proc

          value.flat_map { |key, v| differences(v, stored[key], "#{path}[#{key.inspect}]") }
        end

        private_class_method :attribute_differences, :attributes_differences, :differences
        private_class_method :same_time?, :array_differences, :hash_differences

        private

        def ensure_stored_types!(event)
          unless event.sequence_number.is_a?(Integer) && event.sequence_number.positive?
            fail_stored_type(event, :sequence_number, 'a positive Integer')
          end
          fail_stored_type(event, :created_at, 'a Time') unless event.created_at.is_a?(Time)
        end

        def fail_stored_type(event, name, expected)
          fail ArgumentError, "#{name} of #{event.class} must be #{expected}, not #{event.public_send(name).inspect}"
        end

        # The JSON of an event as it is loaded, for event stores that change it when storing it.
        def loaded_event_json(event_json) = event_json
      end
    end
  end
end
