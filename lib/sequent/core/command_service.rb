require_relative 'transactions/no_transactions'

module Sequent
  module Core

    class CommandServiceConfiguration
      attr_accessor :event_store,
                    :command_handler_classes,
                    :transaction_provider,
                    :filters

      def initialize
        @command_handler_classes = []
        @transaction_provider = Sequent::Core::Transactions::NoTransactions.new
        @filters = []
      end

    end

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

      class << self
        attr_accessor :configuration,
                      :instance
      end

      # Creates a new CommandService and overwrites all existing config.
      # The new CommandService can be retrieved via the +CommandService.instance+ method.
      #
      # If you don't want a singleton you can always instantiate it yourself using the +CommandService.new+.
      def self.configure
        self.configuration = CommandServiceConfiguration.new
        yield(configuration) if block_given?
        self.instance = CommandService.new(configuration)
      end

      # +DefaultCommandServiceConfiguration+ Configuration class for the CommandService containing:
      #
      #   +event_store+ The Sequent::Core::EventStore
      #   +command_handler_classes+ Array of BaseCommandHandler classes that need to handle commands
      #   +transaction_provider+ How to do transaction management. Defaults to Sequent::Core::Transactions::NoTransactions
      #   +filters+ List of filter that respond_to :execute(command). Can be useful to do extra checks (security and such).
      def initialize(configuration = CommandServiceConfiguration.new)
        @event_store = configuration.event_store
        @repository = AggregateRepository.new(configuration.event_store)
        @filters = configuration.filters
        @transaction_provider = configuration.transaction_provider
        @command_handlers = configuration.command_handler_classes.map { |handler| handler.new(@repository) }
      end

      # Executes the given commands in a single transactional block as implemented by the +transaction_provider+
      #
      # For each command:
      #
      # * All filters are executed. Any exception raised will rollback the transaction and propagate up
      # * If the command is valid all +command_handlers+ that +handles_message?+ is invoked
      # * The +repository+ commits the command and all uncommitted_events resulting from the command
      def execute_commands(*commands)
        begin
          @transaction_provider.transactional do
            commands.each do |command|
              @filters.each { |filter| filter.execute(command) }

              raise CommandNotValid.new(command) unless command.valid?
              parsed_command = command.parse_attrs_to_correct_types
              @command_handlers.select { |h| h.handles_message?(parsed_command) }.each { |h| h.handle_message parsed_command }
              @repository.commit(parsed_command)

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



