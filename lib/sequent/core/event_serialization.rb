# frozen_string_literal: true

require_relative 'sequent_oj'

module Sequent
  module Core
    class EventSerializationError < RuntimeError; end

    #
    # A replay reads the events from the event store, so it sees them as they are serialized to JSON and deserialized
    # again: times are truncated to the +time_precision+, symbols become strings and attributes are cast to their type.
    # The event stores therefore publish events the same way, so projectors and workflows see the same values when the
    # events are stored and when they are replayed.
    #
    # The aggregate that applied an event still has the values it applied. When
    # +Sequent.configuration.verify_event_serialization+ is set, for instance in specs, storing an event fails when it
    # changes other than by truncating its times, so the domain code can be fixed to create the values it stores.
    #
    module EventSerialization
      class << self
        ##
        # Returns +event+ as it is read from the event store.
        def as_stored(event)
          stored = event.class.deserialize_from_json(Oj.strict_load(Oj.dump(event)))
          verify!(event, stored) if Sequent.configuration.verify_event_serialization
          stored
        end

        ##
        # Fails when +stored+ has other attribute values than +event+, except for times truncated to the
        # +time_precision+.
        def verify!(event, stored)
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

        private

        def same?(value, stored)
          case value
          when Time, DateTime, ActiveSupport::TimeWithZone then same_time?(value, stored)
          when Array then same_array?(value, stored)
          when Hash then stored.is_a?(Hash) && value.keys == stored.keys && value.all? { |k, v| same?(v, stored[k]) }
          else
            return same_attributes?(value, stored) if value.class.respond_to?(:types)

            value.instance_of?(stored.class) && value == stored
          end
        end

        def same_array?(value, stored)
          stored.is_a?(Array) && value.size == stored.size && value.zip(stored).all? { |v, s| same?(v, s) }
        end

        def same_time?(value, stored)
          return false unless stored.respond_to?(:to_time)

          precision = Sequent.configuration.time_precision
          value.to_time.utc.iso8601(precision) == stored.to_time.utc.iso8601(precision)
        end

        def same_attributes?(value, stored)
          stored.instance_of?(value.class) &&
            value.class.types.keys.all? { |name| same?(value.public_send(name), stored.public_send(name)) }
        end
      end
    end
  end
end
