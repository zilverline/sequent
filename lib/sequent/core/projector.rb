require_relative 'helpers/message_handler'
require_relative './persistors/active_record_persistor'

module Sequent
  module Core

    module Migratable
      module ClassMethods
        def manages_tables(*tables)
          @managed_tables = tables
        end

        def managed_tables
          @managed_tables
        end
      end

      def self.projectors
        Sequent.configuration.event_handlers.select { |x| x.is_a? Migratable }.map(&:class)
      end

      def self.included(host_class)
        host_class.extend(ClassMethods)
      end

      def self.none
        []
      end

      def self.all
        Migratable.projectors
      end

      def managed_tables
        self.class.managed_tables
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


      def initialize(persistor = Sequent::Core::Persistors::ActiveRecordPersistor.new)
        ensure_valid!
        @persistor = persistor
      end

      def self.replay_persistor
        nil
      end

      def_delegators :@persistor,
        :update_record,
        :create_record,
        :create_records,
        :create_or_update_record,
        :get_record!,
        :get_record,
        :delete_all_records,
        :update_all_records,
        :do_with_records,
        :do_with_record,
        :delete_record,
        :find_records,
        :last_record,
        :execute_sql,
        :commit

      private
      def ensure_valid!
        fail "A Projector must manage at least one table. Did you forget to add `managed_tables` to #{self.class.name}?" if self.class.managed_tables.nil? || self.class.managed_tables.empty?
      end
    end
  end
end
