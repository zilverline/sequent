require_relative 'helpers/copyable'
require_relative 'helpers/attribute_support'
require_relative 'helpers/uuid_helper'
require_relative 'helpers/equal_support'
require_relative 'helpers/param_support'
require_relative 'helpers/mergable'

module Sequent
  module Core
    # Base command
    class BaseCommand
      include ActiveModel::Validations,
              Sequent::Core::Helpers::Copyable,
              Sequent::Core::Helpers::AttributeSupport,
              Sequent::Core::Helpers::UuidHelper,
              Sequent::Core::Helpers::EqualSupport,
              Sequent::Core::Helpers::ParamSupport,
              Sequent::Core::Helpers::Mergable
      include ActiveModel::Validations::Callbacks
      include Sequent::Core::Helpers::TypeConversionSupport

      attrs created_at: DateTime

      def initialize(args = {})
        update_all_attributes args
        @created_at = DateTime.now
      end

      def self.inherited(subclass)
        Commands << subclass
      end
    end

    module UpdateSequenceNumber
      extend ActiveSupport::Concern
      included do
        attrs sequence_number: Integer
        validates_presence_of :sequence_number
        validates_numericality_of :sequence_number, only_integer: true, allow_nil: true, allow_blank: true, greater_than: 0
      end
    end

    class Commands
      class << self
        def commands
          @commands ||= []
        end

        def all
          commands
        end

        def <<(command)
          commands << command
        end

        def find(command_name)
          commands.find { |c| c.name == command_name }
        end
      end
    end

    # Most commonly used command
    # Command can be instantiated just by using:
    #
    #   Command.new(aggregate_id: "1", user_id: "joe")
    #
    # But the Sequent::Core::Helpers::ParamSupport also enables Commands
    # to be created from a params hash (like the one from Sinatra) as follows:
    #
    #   command = Command.from_params(params)
    #
    class Command < BaseCommand
      attrs aggregate_id: String, user_id: String, event_aggregate_id: String, event_sequence_number: Integer

      def initialize(args = {})
        raise ArgumentError, "Missing aggregate_id" if args[:aggregate_id].nil?
        super
      end
    end

    class UpdateCommand < Command
      include UpdateSequenceNumber
    end
  end
end
