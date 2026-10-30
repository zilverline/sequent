# frozen_string_literal: true

require_relative 'helpers/message_handler'
require_relative 'persistors/active_record_persistor'
require_relative 'projectors'

module Sequent
  module Core
    module Migratable
      module ClassMethods
        def manages_tables(*tables)
          fail 'must specify at least one table to manage' if tables.empty?

          self.managed_tables = tables.freeze
        end

        def manages_no_tables
          self.managed_tables = [].freeze
        end

        def manages_no_tables? = managed_tables.empty?

        def version=(version)
          self.projector_version = version
        end

        def version = projector_version || Sequent.migrations_class&.version || 1
      end

      def self.projectors
        Sequent.configuration.event_handler_classes.select { |handler_class| handler_class.include?(Migratable) }
      end

      def self.included(host_class)
        host_class.extend(ClassMethods)

        host_class.class_attribute :projector_version,
                                   default: nil,
                                   instance_accessor: false
        host_class.class_attribute :managed_tables,
                                   default: nil,
                                   instance_reader: true,
                                   instance_writer: false
        host_class.class_attribute :additional_replay_indexes,
                                   default: [],
                                   instance_accessor: false
      end

      def self.none
        []
      end

      def self.all
        Migratable.projectors
      end
    end

    # Projectors listen to events and update the view state as they see fit.
    #
    # Example of updating view state, in this case the InvoiceRecord table representing an Invoice
    #
    #   class InvoiceProjector < Sequent::Core::Projector
    #     manages_tables InvoiceRecord
    #
    #     on InvoiceCreated do |event|
    #       create_record(
    #         InvoiceRecord,
    #         recipient: event.recipient,
    #         amount: event.amount
    #       )
    #     end
    #   end
    #
    # Please note that the actual storage is abstracted away in the +persistors+.
    # Due to this abstraction you can not traverse persist or traverse child objects
    # like you are used to do with ActiveRecord. The following example will not work:
    #
    #   invoice_record.line_item_records << create_record(LineItemRecord, ...)
    #
    # In this case you should simply do:
    #
    #   create_record(LineItemRecord, invoice_id: invoice_record.aggregate_id)
    #
    class Projector
      extend Forwardable
      include Helpers::MessageHandler
      include Migratable
      extend ActiveSupport::DescendantsTracker

      class NotManagedByThisProjector < RuntimeError
        def initialize(record_class)
          super
          @record_class = record_class
        end

        def message
          "#{@record_class} is not managed by this projector #{self.class.name}. Please check your configuration."
        end
      end

      class << self
        attr_accessor :abstract_class, :skip_autoregister
      end

      def initialize(persistor = default_persistor)
        ensure_valid!
        @persistor = persistor
      end

      ##
      # The persistor of a projector that is created without a persistor. Override this method to use
      # another persistor.
      def default_persistor
        Sequent::Core::Persistors::ActiveRecordPersistor.new
      end

      ##
      # The phase in which this projector handles events, see +StagedEventPublisher.with_phases+.
      # Either +:inline+ (the default) to handle each event in turn, or +:bulk+ to handle all
      # events of a commit at once, before the +inline+ projectors and workflows:
      #
      #   class MyProjector < Sequent::Projector
      #     self.phase = :bulk
      #
      #     on_batch MyEvent do |events|
      #       create_records(MyRecord, events.map { |event| {aggregate_id: event.aggregate_id} })
      #     end
      #   end
      #
      # Do not use a deferred phase like +before_commit+ for a projector, since the command handlers
      # of the next commands use its projections.
      class_attribute :phase, instance_writer: false, default: :inline

      ##
      # The lifetime of the instances of this projector. With the +:singleton+ lifetime a single instance is
      # registered, which handles all events. With the +:batch+ lifetime the class is registered, and the
      # event publisher creates a new instance for every batch of events it handles, like a controller is
      # created for every request, so the instance can keep state while handling the batch. Without a
      # lifetime, projectors in the +bulk+ phase have the +:batch+ lifetime, since they handle all events of a
      # command at once, and all others the +:singleton+ lifetime.
      class_attribute :lifetime, instance_writer: false, default: nil

      def self.on(*args, **opts, &block)
        ensure_type_based_handler!(args)
        super
      end

      def self.on_batch(*args, **opts, &block)
        ensure_type_based_handler!(args)
        super
      end

      def self.ensure_type_based_handler!(args)
        fail ArgumentError, 'only type based event handlers are allowed for projectors' unless args.all?(Class)
      end
      private_class_method :ensure_type_based_handler!

      def self.replay_persistor
        nil
      end

      def self.ensure_valid!
        if managed_tables.nil?
          fail <<~EOS.chomp
            A Projector must manage at least one table. Did you forget to add `managed_tables` to #{self}?
          EOS
        end
      end

      def_delegators :@persistor, :execute_sql, :flush

      # @deprecated Use +flush+ instead.
      def commit
        flush
      end

      def update_record(record_class, *rest, &block)
        ensure_record_class_supported!(record_class)
        @persistor.update_record(record_class, *rest, &block)
      end

      def create_record(record_class, *rest, &block)
        ensure_record_class_supported!(record_class)
        @persistor.create_record(record_class, *rest, &block)
      end

      def create_records(record_class, *rest)
        ensure_record_class_supported!(record_class)
        @persistor.create_records(record_class, *rest)
      end

      def create_or_update_record(record_class, *rest, &block)
        ensure_record_class_supported!(record_class)
        @persistor.create_or_update_record(record_class, *rest, &block)
      end

      def get_record!(record_class, *rest)
        ensure_record_class_supported!(record_class)
        @persistor.get_record!(record_class, *rest)
      end

      def get_record(record_class, *rest)
        ensure_record_class_supported!(record_class)
        @persistor.get_record(record_class, *rest)
      end

      def delete_all_records(record_class, *rest)
        ensure_record_class_supported!(record_class)
        @persistor.delete_all_records(record_class, *rest)
      end

      def update_all_records(record_class, *rest)
        ensure_record_class_supported!(record_class)
        @persistor.update_all_records(record_class, *rest)
      end

      def do_with_records(record_class, *rest, &block)
        ensure_record_class_supported!(record_class)
        @persistor.do_with_records(record_class, *rest, &block)
      end

      def do_with_record(record_class, *rest, &block)
        ensure_record_class_supported!(record_class)
        @persistor.do_with_record(record_class, *rest, &block)
      end

      def delete_record(record_class, *rest)
        ensure_record_class_supported!(record_class)
        @persistor.delete_record(record_class, *rest)
      end

      def find_records(record_class, *rest)
        ensure_record_class_supported!(record_class)
        @persistor.find_records(record_class, *rest)
      end

      def last_record(record_class, *rest)
        ensure_record_class_supported!(record_class)
        @persistor.last_record(record_class, *rest)
      end

      private

      def ensure_record_class_supported!(record_class)
        fail NotManagedByThisProjector, record_class unless managed_tables.include?(record_class)
      end

      def ensure_valid!
        self.class.ensure_valid!
      end
    end
  end
end
