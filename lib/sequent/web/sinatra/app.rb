require 'sinatra'
module Sequent
  module Web
    module Sinatra
      # Allows for easy integration with Sinatra apps.
      # Provides:
      #
      #   +Sequent::Core::Helpers::UuidHelper+
      #   +FormHelpers+
      #   +SimpleCommandServiceHelpers+
      #
      # The +sequent_config_dir+ allows you to specify the directory containing the
      # 'initializers/sequent' file that initializes the +EventStore+ and +CommandService+ for your webapp.
      #
      # class MySinatraApp < Sinatra::Base
      #   set :sequent_config_dir, root
      #   register Sequent::Web::Sinatra::App
      # end
      module App
        def self.registered(app)
          app.helpers Sequent::Core::Helpers::UuidHelper
          app.helpers Sequent::Web::Sinatra::FormHelpers
          app.helpers Sequent::Web::Sinatra::SimpleCommandServiceHelpers

          app.before do
            require File.join(app.sequent_config_dir || app.root, 'initializers/sequent')
            @command_service = Sequent::Core::CommandService.instance
          end

        end
      end
    end
  end
end
Sinatra.register Sequent::Web::Sinatra::App
