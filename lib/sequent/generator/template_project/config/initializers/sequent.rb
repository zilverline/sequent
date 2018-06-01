Sequent.configure do |config|
  config.command_handlers = [
    AccountCommandHandler
  ]

  config.event_handlers = [
    AccountProjector.new
  ]
end
