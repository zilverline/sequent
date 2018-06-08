Sequent.configure do |config|
  config.command_handlers = [
    AccountCommandHandler.new
  ]

  config.event_handlers = [
    AccountProjector.new
  ]
end
