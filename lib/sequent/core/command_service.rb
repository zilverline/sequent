require_relative 'transactions/no_transactions'

module Sequent
  module Core

    class CommandService

      def initialize(event_store, command_handler_classes, transaction_provider = Sequent::Core::Transactions::NoTransactions.new, filters=[])
        @event_store = event_store
        @repository = AggregateRepository.new(event_store)
        @filters = filters
        @transaction_provider = transaction_provider
        @command_handlers = command_handler_classes.map { |handler| handler.new(@repository) }
      end

      def execute_commands(*commands)
        begin
          @transaction_provider.transactional do
            commands.each do |command|
              @filters.each { |filter| filter.execute(command) }

              if command.valid?
                @command_handlers.each do |command_handler|
                  command_handler.handle_message command if command_handler.handles_message? command
                end
              end

              @repository.commit(command)
              raise CommandNotValid.new(command) unless command.validation_errors.empty?
            end
          end
        ensure
          @repository.clear
        end

      end

      def remove_event_handler(clazz)
        @event_store.remove_event_handler(clazz)
      end

    end

    class CommandNotValid < ArgumentError

      def initialize(command)
        @command = command
        msg = @command.respond_to?(:aggregate_id) ? " #{@command.aggregate_id}" : ""
        super "Invalid command #{@command.class.to_s}#{msg}, errors: #{@command.validation_errors}"
      end

      def errors(prefix = nil)
        @command.validation_errors(prefix)
      end

      def errors_with_command_prefix
        errors(@command.class.to_s.underscore)
      end
    end

  end
end



