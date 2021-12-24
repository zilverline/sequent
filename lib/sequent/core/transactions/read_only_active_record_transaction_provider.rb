# frozen_string_literal: true

module Sequent
  module Core
    module Transactions
      class ReadOnlyActiveRecordTransactionProvider
        def initialize(transaction_provider)
          @transaction_provider = transaction_provider
        end

        def transactional(&block)
          register_call
          @transaction_provider.transactional do
            Sequent::ApplicationRecord.connection.execute('SET TRANSACTION READ ONLY')
            block.call
          rescue ActiveRecord::StatementInvalid
            @skip_set_transaction = true
            raise
          ensure
            deregister_call
            reset_stack_size if stack_size == 0
          end
        end

        private

        def stack_size
          Thread.current[:read_only_active_record_transaction_provider_calls]
        end

        def register_call
          Thread.current[:read_only_active_record_transaction_provider_calls] ||= 0
          Thread.current[:read_only_active_record_transaction_provider_calls] += 1
        end

        def deregister_call
          Thread.current[:read_only_active_record_transaction_provider_calls] -= 1
        end

        def reset_stack_size
          Thread.current[:read_only_active_record_transaction_provider_calls] = nil
        end
      end
    end
  end
end
