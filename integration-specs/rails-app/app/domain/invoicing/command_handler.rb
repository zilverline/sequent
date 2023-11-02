# frozen_string_literal: true

module Invoicing
  class CommandHandler < Sequent::CommandHandler
    on Commands::Create do |command|
      repository.add_aggregate(Invoice.new(command))
    end
  end
end
