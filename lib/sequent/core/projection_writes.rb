# frozen_string_literal: true

module Sequent
  module Core
    #
    # Decides whether the records of projections (see +ProjectionRecord+) can be written. By default they cannot,
    # so only projectors write them: a projector allows writing them while it writes using its persistor. The
    # +CommandService+ forbids writing them while it executes commands, also when writing them is allowed, so a
    # command handler or workflow that writes them directly fails.
    #
    # Specs can allow writing them, so their setup can create the records of projections directly, while commands
    # executed by the specs still cannot write them:
    #
    #   RSpec.configure do |config|
    #     config.around { |example| Sequent::Core::ProjectionWrites.allow { example.run } }
    #   end
    #
    # The state is kept per fiber, and every block restores the previous state.
    #
    module ProjectionWrites
      class ForbiddenError < RuntimeError; end

      STATE_KEY = :sequent_projection_writes

      class << self
        ##
        # Whether the records of projections can be written.
        def allowed?
          %i[allowed projection].include?(Thread.current[STATE_KEY])
        end

        ##
        # Allows writing the records of projections in the block, except while executing commands.
        def allow(&block)
          with_state(:allowed, &block)
        end

        ##
        # Forbids writing the records of projections in the block, except for projectors.
        def forbid(&block)
          with_state(:forbidden, &block)
        end

        ##
        # Allows writing the records of projections in the block, for a projector writing its projection.
        def during_projection(&block)
          with_state(:projection, &block)
        end

        ##
        # Fails unless the records of +record_class+, a projection, can be written.
        def ensure_allowed!(record_class)
          return if allowed?

          fail ForbiddenError,
               "#{record_class} is the record of a projection, which only its projector can write " \
               '(see Sequent::Core::ProjectionWrites)'
        end

        private

        def with_state(state)
          previous_state = Thread.current[STATE_KEY]
          Thread.current[STATE_KEY] = state
          yield
        ensure
          Thread.current[STATE_KEY] = previous_state
        end
      end
    end

    #
    # Marks an ActiveRecord class as the record of a projection, which only projectors can write (see
    # +ProjectionWrites+). Saving, updating or destroying its records fails with an +ActiveRecord::ReadOnlyRecord+
    # error, and writing its records without instantiating them (like +insert_all+, +update_all+ or +delete_all+)
    # fails with a +ProjectionWrites::ForbiddenError+, unless writing them is allowed.
    #
    #   class InvoiceRecord < Sequent::ApplicationRecord
    #     include Sequent::Core::ProjectionRecord
    #   end
    #
    module ProjectionRecord
      # The relation methods that write records without instantiating them.
      module RelationWrites
        %i[
          insert insert! insert_all insert_all! upsert upsert_all update_all update_counters touch_all delete_all
        ].each do |method_name|
          define_method(method_name) do |*args, **kwargs, &block|
            ProjectionWrites.ensure_allowed!(klass) if klass < ProjectionRecord
            super(*args, **kwargs, &block)
          end
        end
      end

      def self.included(record_class)
        super
        ActiveRecord::Relation.prepend(RelationWrites) unless ActiveRecord::Relation < RelationWrites
      end

      def readonly?
        super || !ProjectionWrites.allowed?
      end
    end
  end
end
