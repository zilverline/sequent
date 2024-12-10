# frozen_string_literal: true

require './db/migrations'

Sequent.configure do |config|
  config.migrations_class_name = 'Migrations'
  config.enable_autoregistration = true
end
