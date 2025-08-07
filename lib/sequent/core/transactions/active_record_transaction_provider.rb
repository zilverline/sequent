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
          ActiveRecord::Base.transaction(requires_new: true, &block)
        end

        def after_commit(&block)
          ActiveRecord::Base.current_transaction.after_commit(&block)
        end

        def after_rollback(&block)
          ActiveRecord::Base.current_transaction.after_rollback(&block)
        end
      end
    end
  end
end
