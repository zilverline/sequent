# frozen_string_literal: true

module Sequent
  module Core
    class UnknownActiveProjectorError < ProjectorMigrationError; end
    class DifferentProjectorVersionIsActiveError < ProjectorMigrationError; end

    #
    # Subtype of EventPublisher that only dispatches events to Projectors that are marked active in
    # the projector_states table. Also fails if there are unknown active projectors. This allows
    # upgrading to new code (with new projectors) without having to shutdown the old code first, as
    # the old code will start failing as soon as the new code's Sequent configuration is activated
    # (using `Sequent#activate_current_configuration!`).
    #
    class ActiveProjectorsEventPublisher < EventPublisher
      def publish_events(events)
        return if configuration.disable_event_handlers

        ensure_no_unknown_active_projectors!

        super
      end

      private

      def process_events(...)
        # Process all events inside a transaction to ensure consistency with the projector state
        # (active or not) and updating the projector tables. Normally an transaction is already
        # active due to using the `CommandService#execute_command`, but if this event publisher is
        # used directly it is also important to run inside a transaction.
        Sequent.configuration.transaction_provider.transactional { super(...) }
      end

      def handle_message(handler, event)
        super if active?(handler)
      end

      def ensure_no_unknown_active_projectors!
        expected_version = Sequent.migrations_class&.version
        return if expected_version.nil?

        registered_projectors = Migratable.projectors.to_set(&:name)
        active_projectors = Projectors.projector_states
          .values
          .select { |s| s.active_version == expected_version }
          .to_set(&:name)
        unknown_active_projectors = active_projectors - registered_projectors
        if unknown_active_projectors.present?
          fail UnknownActiveProjectorError,
               "cannot publish event when unknown projectors are active #{unknown_active_projectors}"
        end
      end

      def active?(handler)
        return true unless handler.is_a?(Projector)

        version = Sequent.migrations_class&.version
        return true if version.nil?

        # Projector states are not enable so all projectors are considered active
        return true unless Sequent.configuration.enable_projector_states

        projector_state = Projectors.projector_states[handler.class.name]
        return false if projector_state.nil?

        return true if projector_state.activating_version.nil? && projector_state.active_version == version

        # A different projector version is active, so we cannot write
        # new events since they will not be properly propagated.
        fail DifferentProjectorVersionIsActiveError,
             "projector #{handler.class} version #{version} does not match state #{projector_state}"
      end
    end
  end
end
