require_relative 'helpers/self_applier'
require_relative 'helpers/uuid_helper'

module Sequent
  module Core
    # Base class for command handlers
    # CommandHandlers are responsible for propagating a command to the correct Sequent::Core::AggregateRoot
    # or creating a new one. For example:
    #
    #   class InvoiceCommandHandler < Sequent::Core::BaseCommandHandler
    #     on CreateInvoiceCommand do |command|
    #       repository.add_aggregate Invoice.new(command.aggregate_id)
    #     end
    #
    #     on PayInvoiceCommand do |command|
    #       do_with_aggregate(command, Invoice) {|invoice|invoice.pay(command.pay_date)}
    #     end
    #   end
    class BaseCommandHandler
      include Sequent::Core::Helpers::SelfApplier,
              Sequent::Core::Helpers::UuidHelper

      attr_accessor :repository

      def initialize(repository = Sequent.configuration.aggregate_repository)
        @repository = repository
      end

      protected
      def do_with_aggregate(command, clazz, aggregate_id = nil)
        aggregate = @repository.load_aggregate(aggregate_id.nil? ? command.aggregate_id : aggregate_id, clazz)
        yield aggregate if block_given?
      end

    end
  end
end
