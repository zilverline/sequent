# frozen_string_literal: true

require 'sequent'

Sequent.configure do |config|
  config.enable_autoregistration = true
  config.event_handlers = [
    ManualProjector.new,
    ManualWorkflow.new,
  ]
end
