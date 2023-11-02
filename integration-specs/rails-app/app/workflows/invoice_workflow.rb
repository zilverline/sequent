# frozen_string_literal: true

class InvoiceWorkflow < Sequent::Workflow
  on Invoicing::Events::Created do |_event|
  end
end
