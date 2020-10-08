module Sequent
  module Core
    module Transactions

      class ActiveRecordTransactionProvider
        def transactional
          Sequent::ApplicationRecord.transaction(requires_new: true) do
            yield
          end
          while(!after_commit_queue.empty?) do
            after_commit_queue.pop.call
          end
        ensure
          clear_after_commit_queue
        end

        def after_commit(&block)
          after_commit_queue << block
        end

        private

        def after_commit_queue
          Thread.current[:after_commit_queue] ||= Queue.new
        end

        def clear_after_commit_queue
          after_commit_queue.clear
        end
      end

    end
  end
end
