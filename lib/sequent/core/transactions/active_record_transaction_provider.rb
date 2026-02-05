# frozen_string_literal: true

module Sequent
  module Core
    module Transactions
      class ActiveRecordTransactionProvider
        attr_reader :requires_new

        ##
        # Configure if save points should be used to simulate nested transactions. This is only
        # useful in combination with the `ActiveRecord::Rollback` exception.
        #
        # Read: https://api.rubyonrails.org/classes/ActiveRecord/Rollback.html and
        # http://api.rubyonrails.org/classes/ActiveRecord/Transactions/ClassMethods.html
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
        # In this example, you might be surprised to find that `do.some.things` does not get rolled
        # back! This only happens with `ActiveRecord::Rollback`, since it is handled by the inner
        # transaction. All other exceptions are automatically propagated and will cause the parent
        # transaction to rollback.
        #
        # Note that using save points with PostgreSQL adds additional overhead and is rarely useful,
        # so our advice is to only use `ActiveRecord::Rollback` directly inside of an
        # `ActiveRecord::Base.transaction(requires_new: true) do ... end` block so it is clear what
        # the expected behavior is.
        def initialize(requires_new: false)
          @requires_new = requires_new
          warn <<~EOS if @requires_new
            [DEPRECATED] avoid using `requires_new: true` globally, use explicit `ActiveRecord::Base.transaction(requires_new: true)`
            blocks with `ActiveRecord::Rollback` instead if nested transactions are needed.
          EOS
        end

        def transaction(requires_new: @requires_new, &block)
          ActiveRecord::Base.transaction(requires_new:, &block)
        end

        # Deprecated alias
        alias transactional transaction

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
