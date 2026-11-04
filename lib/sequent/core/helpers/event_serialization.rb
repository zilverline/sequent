# frozen_string_literal: true

require_relative '../sequent_oj'

module Sequent
  module Core
    class EventSerializationError < RuntimeError; end

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
      # +Sequent.configuration.verify_event_serialization+ is set, for instance in specs, storing an event fails when it
      # changes other than by truncating its times, so the domain code can be fixed to create the values it stores.
      #
      module EventSerialization
        ##
        # Deserializes an event from its type and its parsed JSON.
        def deserialize_event_json(event_type, payload)
          Class.const_get(event_type).deserialize_from_json(payload)
        end

        ##
        # Returns +event+ as it is loaded once it is stored.
        def stored_event(event)
          stored = deserialize_event_json(event.class.name, loaded_event_json(Oj.strict_load(Oj.dump(event))))
          EventSerialization.verify!(event, stored) if Sequent.configuration.verify_event_serialization
          stored
        end

        ##
        # Fails when +stored+ has other attribute values than +event+, except for times truncated to the
        # +time_precision+.
        def self.verify!(event, stored)
          differences = event.class.types.keys.filter_map do |name|
            value = event.public_send(name)
            stored_value = stored.public_send(name)
            "#{name}: #{value.inspect} is stored as #{stored_value.inspect}" unless same?(value, stored_value)
          end
          return if differences.empty?

          fail EventSerializationError,
               "#{event.class} changes when it is stored, so it is applied and projected differently when it is " \
               "loaded or replayed: #{differences.join('; ')}"
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

          precision = Sequent.configuration.time_precision
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

        private_class_method :same?, :same_time?, :same_array?, :same_hash?, :same_attributes?

        private

        # The JSON of an event as it is loaded, for event stores that change it when storing it.
        def loaded_event_json(event_json) = event_json
      end
    end
  end
end
