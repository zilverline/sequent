# frozen_string_literal: true

module Invoicing
  module Events
    class Created < Sequent::Event; end
    class AmountSet < Sequent::Event
      attrs amount: BigDecimal
    end
  end
end
