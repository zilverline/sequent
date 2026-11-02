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

      STATE_KEY = :"#{self}.state"

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
    # error, and deleting them or writing them without instantiating them (like +insert_all+, +update_all+ or
    # +delete_all+) fails with a +ProjectionWrites::ForbiddenError+, unless writing them is allowed.
    #
    #   class InvoiceRecord < Sequent::ApplicationRecord
    #     include Sequent::Core::ProjectionRecord
    #   end
    #
    # Its records cannot have callbacks that run when writing records, or validations, since these only run when a
    # projector saves a record using the +ActiveRecordPersistor+, and not when replaying or when writing records
    # without instantiating them. A projector that manages such a record class fails (see
    # +ProjectionRecord.ensure_no_write_callbacks!+). Callbacks that run when reading records, like +after_find+ and
    # +after_initialize+, can be used.
    #
    module ProjectionRecord
      class WriteCallbacksError < RuntimeError; end

      # The callback chains that run when writing or validating records.
      WRITE_CALLBACK_KINDS = %i[save create update destroy commit rollback touch validate validation].freeze

      # The callbacks ActiveRecord adds to the records of associations.
      ASSOCIATION_CALLBACK = /
        \A(autosave_associated_records_for|validate_associated_records_for)_
        |_collection_association\z
        |\A_ensure_no_duplicate_errors\z
      /x

      class << self
        ##
        # Fails when +record_class+ has callbacks that run when writing records, or validations.
        def ensure_no_write_callbacks!(record_class)
          callbacks = write_callbacks(record_class)
          return if callbacks.empty?

          fail WriteCallbacksError,
               "#{record_class} is the record of a projection, so it cannot have callbacks that run when writing " \
               "records or validations, since these do not run when replaying: #{callbacks.join(', ')}"
        end

        ##
        # Describes the callbacks of +record_class+ that run when writing records, and its validations, except the
        # ones ActiveRecord adds itself.
        def write_callbacks(record_class)
          WRITE_CALLBACK_KINDS.flat_map do |kind|
            record_class.__callbacks[kind].filter_map do |callback|
              next if active_record_callback?(kind, callback.filter)

              describe_callback(kind, callback)
            end
          end
        end

        private

        def active_record_callback?(kind, filter)
          return true if filter.is_a?(Symbol) && filter.match?(ASSOCIATION_CALLBACK)

          active_record_filters.fetch(kind).include?(filter)
        end

        # The callbacks of a record class without callbacks of its own.
        def active_record_filters
          @active_record_filters ||= begin
            record_class = Class.new(ActiveRecord::Base) { self.abstract_class = true }
            WRITE_CALLBACK_KINDS.to_h { |kind| [kind, record_class.__callbacks[kind].to_set(&:filter)] }
          end
        end

        def describe_callback(kind, callback)
          filter = callback.filter
          case filter
          when ActiveModel::Validator
            attributes = filter.respond_to?(:attributes) ? " #{filter.attributes.join(', ')}" : ''
            "#{filter.class.name}#{attributes}"
          when Symbol, String then "#{callback.kind}_#{kind} #{filter}"
          else "#{callback.kind}_#{kind} (block)"
          end
        end
      end

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

      # ActiveRecord deletes read-only records, so this checks itself whether writing is allowed.
      def delete
        ProjectionWrites.ensure_allowed!(self.class)
        super
      end
    end
  end
end
