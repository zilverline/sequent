# frozen_string_literal: true

module Invoicing
  class Invoice < Sequent::AggregateRoot
    def initialize(command)
      super(command.aggregate_id)
      apply Events::Created
      apply Events::AmountSet, amount: command.amount
    end

    on Events::Created do
    end
  end
end
