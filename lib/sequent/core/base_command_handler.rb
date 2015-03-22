require_relative 'helpers/self_applier'
require_relative 'helpers/uuid_helper'

module Sequent
  module Core
    class BaseCommandHandler
      include Sequent::Core::Helpers::SelfApplier,
              Sequent::Core::Helpers::UuidHelper

      def initialize(repository)
        @repository = repository
      end

      protected
      def do_with_aggregate(command, clazz, aggregate_id = nil)
        aggregate = @repository.load_aggregate(aggregate_id.nil? ? command.aggregate_id : aggregate_id, clazz)
        yield aggregate if block_given?
      end

      protected
      def repository
        @repository
      end
    end
  end
end
