# frozen_string_literal: true

module Sequent
  module Core
    module Transactions
      class ReadOnlyActiveRecordTransactionProvider
        def initialize(transaction_provider)
          @transaction_provider = transaction_provider
        end

        def transaction(&block)
          register_call
          @transaction_provider.transaction(requires_new: true) do |transaction|
            Sequent::ApplicationRecord.connection.execute('SET TRANSACTION READ ONLY')
            block.call(transaction)
          end
        ensure
          deregister_call
          reset_stack_size if stack_size == 0
        end

        # Deprecated
        alias transactional transaction

        delegate :after_commit, :after_rollback, to: :@transaction_provider

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
