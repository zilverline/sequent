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
        def transaction
          yield ActiveRecord::Transaction::NULL_TRANSACTION
        end

        # Deprecated alias
        alias transactional transaction

        def after_commit = yield
        def after_rollback = nil
      end
    end
  end
end
