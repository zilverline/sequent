# frozen_string_literal: true

module Sequent
  module Core
    class ProjectorState < ActiveRecord::Base
      def activating? = activating_version.present?
      def replaying? = replaying_version.present?

      def to_s = {name:, active_version:, replaying_version:, activating_version:}.compact.to_s
    end

    class Projectors
      class << self
        PROJECTOR_STATES_KEY = :"#{self}.projector_states"

        def projectors
          Sequent::Projector.descendants
        end

        def all
          projectors
        end

        def find(projector_name)
          projectors.find { |c| c.name == projector_name }
        end

        def find_by_managed_table(record_class)
          projectors.select { |p| p.managed_tables&.include?(record_class) }
        end

        def register_inactive_projectors!(projector_classes, _version)
          update_projector_state(
            projector_classes,
            active_version: nil,
            replaying_version: nil,
            activating_version: nil,
          )
        end

        def register_replaying_projectors!(projector_classes, version)
          update_projector_state(projector_classes, replaying_version: version, activating_version: nil)
        end

        def register_activating_projectors!(projector_classes, version)
          update_projector_state(projector_classes, activating_version: version, replaying_version: nil)
        end

        def register_active_projectors!(projector_classes, version)
          update_projector_state(
            projector_classes,
            active_version: version,
            activating_version: nil,
            replaying_version: nil,
          )
        end

        def projector_states
          cached = Thread.current[PROJECTOR_STATES_KEY]
          return cached if cached.present?

          transaction_provider.transactional do
            cleanup = -> { Thread.current[PROJECTOR_STATES_KEY] = nil }
            transaction_provider.after_commit(&cleanup)
            transaction_provider.after_rollback(&cleanup)

            Thread.current[PROJECTOR_STATES_KEY] = ProjectorState.all.to_h { |s| [s.name, s] }
          end
        end

        def lock_projector_states_for_update
          # Lock table so no read can take place while updating the projector states
          connection.exec_update("LOCK TABLE #{ProjectorState.quoted_table_name} IN ACCESS EXCLUSIVE MODE")
        end

        private

        def connection
          ActiveRecord::Base.connection
        end

        def transaction_provider
          Sequent.configuration.transaction_provider
        end

        def update_projector_state(projector_classes, **attrs)
          transaction_provider.transactional do
            lock_projector_states_for_update

            rows = projector_classes.map do |projector_class|
              {
                name: projector_class.name,
                **attrs,
              }
            end
            ProjectorState.upsert_all(rows)
          end
        end
      end
    end
  end
end
