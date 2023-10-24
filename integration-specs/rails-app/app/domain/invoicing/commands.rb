# frozen_string_literal: true

module Invoicing
  module Commands
    class Create < Sequent::Command
      attrs amount: BigDecimal

      validates :amount, presence: true, numericality: true
    end
  end
end
