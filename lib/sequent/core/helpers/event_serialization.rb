# frozen_string_literal: true

require_relative '../sequent_oj'

module Sequent
  module Core
    #
    # An event that changes when it is stored, or that can not be deserialized once it is stored. It is passed to the
    # +event_serialization_error_handler+, which can raise it (see +RAISE+) or report it.
    #
    class EventSerializationError < RuntimeError
      # An attribute of the event that has another value once the event is stored.
      Difference = Data.define(:attribute, :value, :stored_value) do
        def to_s = "#{attribute}: #{value.inspect} is stored as #{stored_value.inspect}"
      end

      # Raises the error, for development and specs.
      RAISE = ->(error) { fail error }

      attr_reader :event, :differences

      def initialize(event, differences = [], message = nil)
        @event = event
        @differences = differences
        super(
          message ||
            "#{event.class} changes when it is stored, so it is applied and projected differently when it is loaded " \
            "or replayed: #{differences.join('; ')}",
        )
      end
    end

    module Helpers
      #
      # Deserializes events the way the event stores load them, and verifies that events do not change when they are
      # stored.
      #
      # An event is applied and published with the values the domain code gave it, but an aggregate that is loaded
      # again and a replay read it as it is serialized to JSON and deserialized: symbols as strings, hashes with string
      # keys and attributes cast to their type. When +Sequent.configuration.event_serialization_error_handler+ is set,
      # every event that an aggregate applies and that changes when it is stored is passed to it as an
      # +EventSerializationError+, before the aggregate applies it, so the domain code
      # can be fixed to create the values it stores: +EventSerializationError::RAISE+ fails in development and specs,
      # and a handler that reports the error can be used in production. A +TimeWithZone+ is not reported, although it
      # is loaded as a +Time+ with the same offset, since it only differs in its zone.
      #
      module EventSerialization
        ##
        # Deserializes an event from its type and its parsed JSON.
        def deserialize_event_json(event_type, payload)
          EventSerialization.deserialize_event_json(event_type, payload)
        end

        def self.deserialize_event_json(event_type, payload)
          Class.const_get(event_type).deserialize_from_json(payload)
        end

        ##
        # Returns +event+ as it is loaded once it is stored.
        def self.stored_event(event)
          deserialize_event_json(event.class.name, loaded_event_json(Oj.strict_load(Oj.dump(event))))
        end

        ##
        # Passes an +EventSerializationError+ to +Sequent.configuration.event_serialization_error_handler+, when it is
        # set and +event+ changes when it is stored.
        def self.verify(event)
          handler = Sequent.configuration.event_serialization_error_handler
          return unless handler

          error = serialization_error(event)
          handler.call(error) if error
        end

        ##
        # Returns the +EventSerializationError+ for +event+ when it has other attribute values once it is stored, or
        # when it can not be deserialized.
        def self.serialization_error(event)
          stored = stored_event(event)
          differences = event.class.types.keys.filter_map do |name|
            value = event.public_send(name)
            stored_value = stored.public_send(name)
            EventSerializationError::Difference.new(name, value, stored_value) unless same?(value, stored_value)
          end
          EventSerializationError.new(event, differences) unless differences.empty?
        rescue StandardError => e
          EventSerializationError.new(
            event,
            [],
            "#{event.class} can not be deserialized once it is stored: #{e.class}: #{e.message}",
          )
        end

        TIME_CLASSES = [Time, DateTime, ActiveSupport::TimeWithZone].freeze

        def self.same?(value, stored)
          case value
          when *TIME_CLASSES then same_time?(value, stored)
          when Array then same_array?(value, stored)
          when Hash then same_hash?(value, stored)
          else
            return same_attributes?(value, stored) if value.class.respond_to?(:types)

            value.instance_of?(stored.class) && value == stored
          end
        end

        def self.same_time?(value, stored)
          return false unless TIME_CLASSES.any? { |time_class| stored.is_a?(time_class) }

          precision = ActiveSupport::JSON::Encoding.time_precision
          value.to_time.getutc.iso8601(precision) == stored.to_time.getutc.iso8601(precision)
        end

        def self.same_array?(value, stored)
          stored.is_a?(Array) && value.size == stored.size && value.zip(stored).all? { |v, s| same?(v, s) }
        end

        # A hash with indifferent access or symbol keys behaves differently from the hash with string keys it is
        # stored as, so the class and keys must match as well.
        def self.same_hash?(value, stored)
          value.instance_of?(stored.class) && value.keys == stored.keys &&
            value.all? { |key, v| same?(v, stored[key]) }
        end

        def self.same_attributes?(value, stored)
          stored.instance_of?(value.class) &&
            value.class.types.keys.all? { |name| same?(value.public_send(name), stored.public_send(name)) }
        end

        # The event store keeps the aggregate_id, sequence_number and created_at of an event in columns, from which they
        # are loaded: the aggregate_id as a lowercase UUID, and the created_at in the time zone of ActiveRecord.
        def self.loaded_event_json(event_json)
          created_at = event_json['created_at'] && Time.iso8601(event_json['created_at'])
          created_at = ActiveRecord.default_timezone == :utc ? created_at&.getutc : created_at&.getlocal
          event_json.merge(
            'aggregate_id' => event_json['aggregate_id']&.downcase,
            'created_at' => created_at&.iso8601(ActiveSupport::JSON::Encoding.time_precision),
          )
        end

        private_class_method :same?, :same_time?, :same_array?, :same_hash?, :same_attributes?, :loaded_event_json
      end
    end
  end
end
