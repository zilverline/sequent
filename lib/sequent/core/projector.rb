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
        Sequent.configuration.event_handlers.select { |x| x.is_a? Migratable }.map(&:class)
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

      def initialize(persistor = Sequent::Core::Persistors::ActiveRecordPersistor.new)
        ensure_valid!
        @persistor = persistor
      end

      def self.replay_persistor
        nil
      end

      def_delegators :@persistor, :execute_sql, :commit

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
        if self.class.managed_tables.nil?
          fail <<~EOS.chomp
            A Projector must manage at least one table. Did you forget to add `managed_tables` to #{self.class.name}?
          EOS
        end
      end
    end
  end
end
