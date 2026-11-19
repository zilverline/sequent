# frozen_string_literal: true

require_relative '../json'

module Sequent
  module Core
    module Helpers
      #
      # Deserializes events the way the event stores load them.
      #
      # A replay reads the events from the event store, so it sees them as they are serialized to JSON and deserialized
      # again: times truncated to the +time_precision+, symbols as strings, hashes with string keys and attributes cast
      # to their type. The event stores therefore publish the events as they are stored (see +stored_event+), so
      # projectors and workflows see the same values when the events are stored and when they are replayed.
      #
      # The aggregate that applied an event keeps the values it applied.
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
          deserialize_event_json(event.class.name, loaded_event_json(Json.strict_load(Json.dump(event))))
        end

        private

        # The JSON of an event as it is loaded, for event stores that change it when storing it.
        def loaded_event_json(event_json) = event_json
      end
    end
  end
end
