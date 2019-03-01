module Sequent
  module Core
    module Transactions

      class ActiveRecordTransactionProvider
        def transactional
          ActiveRecord::Base.transaction(requires_new: true) do
            yield
          end
        end

        def after_commit
          ActiveRecord::Base.after_commit do
            yield
          end
        end
      end

    end
  end
end
