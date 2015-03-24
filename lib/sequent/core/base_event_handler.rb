require_relative 'helpers/self_applier'

module Sequent
  module Core
    # EventHandlers listen to events and handle them according to their responsibility.
    #
    # Examples:
    # * Updating view states
    # * Sending emails
    # * Executing other commands based on events (chainging)
    #
    # Example of updating view state, in this case the InvoiceRecord table representing an Invoice
    #
    #   class InvoiceCommandHandler < Sequent::Core::BaseCommandHandler
    #     on CreateInvoiceCommand do |command|
    #       create_record(
    #         InvoiceRecord,
    #         recipient: command.recipient,
    #         amount: command.amount
    #       )
    #     end
    #   end
    #
    # Please note that the actual storage is abstracted away in the +record_session+. Reason
    # is when replaying the entire event_store our default choice, active_record, is to slow.
    # Also we want to give the opportunity to use other storage mechanisms for the view state.
    # See the +def_delegators+ which method to implement.
    class BaseEventHandler
      extend Forwardable
      include Helpers::SelfApplier

      def initialize(record_session = Sequent::Core::RecordSessions::ActiveRecordSession.new)
        @record_session = record_session
      end

      def_delegators :@record_session, :update_record, :create_record, :create_or_update_record, :get_record!, :get_record,
                     :delete_all_records, :update_all_records, :do_with_records, :do_with_record, :delete_record,
                     :find_records, :last_record

    end
  end
end
