# frozen_string_literal: true

module Sequent
  module Core
    module Transactions
      ##
      # Always require a new transaction.
      #
      # Read:
      # http://api.rubyonrails.org/classes/ActiveRecord/Transactions/ClassMethods.html
      #
      # Without this change, there is a potential bug:
      #
      # ```ruby
      # ActiveRecord::Base.transaction do
      #   Sequent.configuration.command_service.execute_commands command
      # end
      #
      # on Command do
      #   do.some.things
      #   fail ActiveRecord::Rollback
      # end
      # ```
      #
      # In this example, you might be surprised to find that `do.some.things`
      # does not get rolled back! This is because AR doesn't automatically make
      # a "savepoint" for us when we call `.transaction` in a nested manner. In
      # order to enable this behaviour, we have to call `.transaction` like
      # this: `.transaction(requires_new: true)`.
      #
      class ActiveRecordTransactionProvider
        def transactional(&block)
          result = Sequent::ApplicationRecord.transaction(requires_new: true, &block)
          after_commit_queue.pop.call until after_commit_queue.empty?
          result
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
