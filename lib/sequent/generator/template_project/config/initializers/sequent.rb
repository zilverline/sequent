Sequent.configure do |config|
  config.migrations_class_name = 'Migrations'

  config.command_handlers = [
    AccountCommandHandler.new
  ]

  config.event_handlers = [
    AccountProjector.new
  ]
end
