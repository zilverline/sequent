# frozen_string_literal: true

module Sequent
  module Core
    module Transactions
      class ActiveRecordTransactionProvider
        def transactional(&block)
          Sequent::ApplicationRecord.transaction(requires_new: true, &block)
          after_commit_queue.pop.call until after_commit_queue.empty?
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
