# frozen_string_literal: true

module Sequent
  module Core
    class UnknownActiveProjectorError < ProjectorMigrationError; end
    class DifferentProjectorVersionIsActiveError < ProjectorMigrationError; end
    class ProjectorIsActivatingError < ProjectorMigrationError; end

    #
    # Subtype of EventPublisher that only dispatches events to Projectors that are marked active in
    # the projector_states table. Also fails if there are unknown active projectors. This allows
    # upgrading to new code (with new projectors) without having to shutdown the old code first, as
    # the old code will start failing as soon as the new code's Sequent configuration is activated
    # (using `Sequent#activate_current_configuration!`).
    #
    class ActiveProjectorsEventPublisher < EventPublisher
      private

      def process_events(event_handlers, ...)
        # Process all events inside a transaction to ensure consistency with the projector state
        # (active or not) and updating the projector tables. Normally a transaction is already
        # active due to using the `CommandService#execute_command`, but if this event publisher is
        # used directly it is also important to run inside a transaction.
        Sequent.configuration.transaction_provider.transaction do
          ensure_no_unknown_active_projectors!(event_handlers)
          active_event_handlers = event_handlers.select { |x| active?(x) }
          super(active_event_handlers, ...)
        end
      end

      def ensure_no_unknown_active_projectors!(event_handlers)
        registered_projectors = event_handlers
          .select { |x| x.is_a?(Projector) }
          .map { |x| x.class.name }
        activated_projectors = Projectors.projector_states
          .values
          .select { |s| s.active_version.present? || s.activating_version.present? }
          .to_set(&:name)
        unknown_active_projectors = activated_projectors - registered_projectors
        if unknown_active_projectors.present?
          fail UnknownActiveProjectorError,
               "cannot publish event when unknown projectors are active #{unknown_active_projectors}"
        end
      end

      def active?(handler)
        return true unless handler.is_a?(Projector)

        version = handler.class.version
        return true if version.nil?

        projector_state = Projectors.projector_states[handler.class.name]
        return false if projector_state.nil?

        if projector_state.activating_version.present?
          # Activating projectors are replaying the last remaining events before going live, so new events cannot be
          # processed until activation is completed.
          fail ProjectorIsActivatingError, "projector #{handler.class} is currently activating"
        end

        # Projector is not yet active (probably just replaying)
        return false if projector_state.active_version.nil?

        # Projector is active and has the same version
        return true if projector_state.active_version == version

        # A different projector version is active, so we cannot write new events since our projector version is not
        # compatible with the active version.
        fail DifferentProjectorVersionIsActiveError,
             "projector #{handler.class} version #{version} does not match state #{projector_state}"
      end
    end
  end
end
