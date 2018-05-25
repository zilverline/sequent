require_relative 'helpers/self_applier'
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
      include Helpers::SelfApplier
      include Migratable

      def initialize(persistor = Sequent::Core::Persistors::ActiveRecordPersistor.new)
        @persistor = persistor
      end

      def self.replay_persistor
        nil
      end

      def_delegators :@persistor,
        # Updates the view state
        :update_record,
        # Create a single record in the view state
        :create_record,
        # Creates multiple records at once in the view state
        :create_records,
        # Creates or updates a record in the view state.
        :create_or_update_record,
        # Gets a record from the view state, fails if it not exists
        :get_record!,
        # Gets a record from the view state, returns +nil+ if it not exists
        :get_record,
        # Deletes all records given a where
        :delete_all_records,
        # Updates all record given a where and an update clause
        :update_all_records,
        # Decide for yourself what to do with the records
        # @deprecated
        :do_with_records,
        # Decide for yourself what to do with a single record
        # @deprecated
        :do_with_record,
        # Delete a single record
        # @deprecated
        :delete_record,
        # Find records given a where
        :find_records,
        # Returns the last record given a where
        :last_record,
        # Just executes the given sql
        :execute_sql,
        :commit

    end
  end
end
