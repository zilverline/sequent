module Sequent
  module Core
    module Transactions

      class NoTransactions
        def transactional
          yield
        end
      end

    end
  end
end
