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
    # without instantiating them. Creating a projector that manages such a record class fails (see
    # +ProjectionRecord.ensure_no_write_callbacks!+). Callbacks that run when reading records, like +after_find+ and
    # +after_initialize+, can be used. The callbacks that ActiveRecord adds itself are allowed by default. Callbacks
    # that must be kept anyway, for instance those added by a gem, or those that ActiveRecord adds and Sequent does
    # not recognize, can be allowed using +allow_write_callbacks+:
    #
    #   class InvoiceRecord < Sequent::ApplicationRecord
    #     include Sequent::Core::ProjectionRecord
    #
    #     allow_write_callbacks :audit_changes, /\Aaudit_/, SomeGem::SomeValidator
    #   end
    #
    # A module that includes +ProjectionRecord+ for the record classes that include it must extend
    # +ActiveSupport::Concern+.
    #
    module ProjectionRecord
      extend ActiveSupport::Concern

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
               "records or validations, since these do not run when replaying: #{callbacks.join(', ')}. " \
               'Move their logic to the projector, or allow callbacks that must be kept using ' \
               "#{record_class}.allow_write_callbacks."
        end

        ##
        # Describes the callbacks of +record_class+ that run when writing records, and its validations, except the
        # allowed ones (see +allow_write_callbacks+).
        def write_callbacks(record_class)
          WRITE_CALLBACK_KINDS.flat_map do |kind|
            record_class.__callbacks[kind].filter_map do |callback|
              describe_callback(kind, callback) unless allowed_callback?(record_class, callback.filter)
            end
          end
        end

        ##
        # The callbacks that ActiveRecord adds itself: those of a record class without callbacks of its own, and
        # those of associations. These are the allowed callbacks by default.
        def active_record_callbacks
          @active_record_callbacks ||= begin
            record_class = Class.new(ActiveRecord::Base) { self.abstract_class = true }
            filters = WRITE_CALLBACK_KINDS.flat_map { |kind| record_class.__callbacks[kind].map(&:filter) }
            [*filters.uniq, ASSOCIATION_CALLBACK].freeze
          end
        end

        private

        # A symbol allows the callbacks calling that method, a regular expression the callbacks calling a method with
        # a matching name, and a class the validators of that class.
        def allowed_callback?(record_class, filter)
          record_class.allowed_write_callbacks.any? do |allowed|
            case allowed
            when Module then filter.is_a?(allowed)
            when Regexp then filter.is_a?(Symbol) && filter.match?(allowed)
            else filter == allowed
            end
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

      included do
        unless is_a?(Class)
          fail ArgumentError, "#{self} includes Sequent::Core::ProjectionRecord, so it must extend ActiveSupport::Concern"
        end

        class_attribute :allowed_write_callbacks,
                        instance_accessor: false,
                        default: ProjectionRecord.active_record_callbacks
        private_class_method :allowed_write_callbacks=
        ActiveRecord::Relation.prepend(RelationWrites) unless ActiveRecord::Relation < RelationWrites
      end

      class_methods do
        ##
        # Allows the callbacks calling the methods with the given names or names matching the given regular
        # expressions, and the validators of the given classes, although these do not run when replaying (see
        # +ProjectionRecord+). These are added to the allowed callbacks of the superclass, which by default are the
        # ones ActiveRecord adds itself.
        def allow_write_callbacks(*callbacks)
          self.allowed_write_callbacks = (allowed_write_callbacks + callbacks).freeze
        end
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
