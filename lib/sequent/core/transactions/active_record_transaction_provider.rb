module Sequent
  module Core
    module Transactions

      class ActiveRecordTransactionProvider
        def transactional
          ActiveRecord::Base.transaction do
            yield
          end
        end

      end

    end
  end
end
