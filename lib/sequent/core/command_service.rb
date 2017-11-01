require_relative 'transactions/no_transactions'

module Sequent
  module Core
    #
    # Single point in the application where subclasses of Sequent::Core::BaseCommand
    # are executed. This will initiate the entire flow of:
    #
    # * Validate command
    # * Call correct Sequent::Core::BaseCommandHandler
    # * CommandHandler decides which Sequent::Core::AggregateRoot (s) to call
    # * Events are stored in the Sequent::Core::EventStore
    # * Unit of Work is cleared
    #
    class CommandService
      # Executes the given commands in a single transactional block as implemented by the +transaction_provider+
      #
      # For each command:
      #
      # * All filters are executed. Any exception raised will rollback the transaction and propagate up
      # * If the command is valid all +command_handlers+ that +handles_message?+ is invoked
      # * The +repository+ commits the command and all uncommitted_events resulting from the command
      def execute_commands(*commands)
        commands.each { |command| command_queue.push(command) }
        process_commands
      end

      def remove_event_handler(clazz)
        event_store.remove_event_handler(clazz)
      end

      private

      def process_commands
        Sequent::Util.skip_if_already_processing(:command_service_process_commands) do
          begin
            transaction_provider.transactional do
              while(!command_queue.empty?) do
                process_command(command_queue.pop)
              end
            end
          ensure
            command_queue.clear
            repository.clear
          end
        end
      end

      def process_command(command)
        filters.each { |filter| filter.execute(command) }

        raise CommandNotValid.new(command) unless command.valid?
        parsed_command = command.parse_attrs_to_correct_types
        command_handlers.select { |h| h.class.handles_message?(parsed_command) }.each { |h| h.handle_message parsed_command }
        repository.commit(parsed_command)
      end

      def command_queue
        Thread.current[:command_service_commands] ||= Queue.new
      end

      def event_store
        Sequent.configuration.event_store
      end

      def repository
        Sequent.configuration.aggregate_repository
      end

      def filters
        Sequent.configuration.command_filters
      end

      def transaction_provider
        Sequent.configuration.transaction_provider
      end

      def command_handlers
        Sequent.configuration.command_handlers
      end
    end

    # Raised when BaseCommand.valid? returns false
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
