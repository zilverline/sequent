# frozen_string_literal: true

require_relative 'helpers/copyable'
require_relative 'helpers/attribute_support'
require_relative 'helpers/uuid_helper'
require_relative 'helpers/equal_support'
require_relative 'helpers/param_support'
require_relative 'helpers/mergable'

module Sequent
  module Core
    #
    # Base class for all Command's.
    #
    # Commands form the API of your domain. They are
    # simple data objects with descriptive names
    # of what they want to achieve. E.g. `SendInvoice`.
    #
    # BaseCommand uses `ActiveModel::Validations` for
    # validations
    class BaseCommand
      include Sequent::Core::Helpers::Mergable
      include Sequent::Core::Helpers::ParamSupport
      include Sequent::Core::Helpers::EqualSupport
      include Sequent::Core::Helpers::UuidHelper
      include Sequent::Core::Helpers::AttributeSupport
      include Sequent::Core::Helpers::Copyable
      include ActiveModel::Validations
      include ActiveModel::Validations::Callbacks
      include Sequent::Core::Helpers::TypeConversionSupport
      extend ActiveSupport::DescendantsTracker

      attrs created_at: Time

      define_model_callbacks :initialize, only: :after

      def initialize(args = {})
        update_all_attributes args
        @created_at = Time.now

        _run_initialize_callbacks
      end
    end

    module UpdateSequenceNumber
      extend ActiveSupport::Concern
      included do
        attrs sequence_number: Integer
        validates_presence_of :sequence_number
        validates_numericality_of :sequence_number,
                                  only_integer: true,
                                  allow_nil: true,
                                  allow_blank: true,
                                  greater_than: 0
      end
    end

    #
    # Utility class containing all subclasses of BaseCommand.
    #
    class Commands
      class << self
        def commands
          Sequent::Core::BaseCommand.descendants
        end

        def all
          commands
        end

        def find(command_name)
          commands.find { |c| c.name == command_name }
        end
      end
    end

    # Most commonly used Command
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
        fail ArgumentError, 'Missing aggregate_id' if args[:aggregate_id].nil?

        super
      end
    end

    class UpdateCommand < Command
      include UpdateSequenceNumber
    end
  end
end
