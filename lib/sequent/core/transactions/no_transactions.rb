# frozen_string_literal: true

module Sequent
  module Core
    module Transactions
      #
      # NoTransactions is used when replaying the +ViewSchema+ for
      # view schema upgrades. Transactions are not needed there since the
      # view state will always be recreated anyway.
      #
      class NoTransactions
        def transactional
          yield
        end
      end
    end
  end
end
