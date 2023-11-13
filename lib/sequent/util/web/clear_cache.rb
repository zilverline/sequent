# frozen_string_literal: true

module Sequent
  module Util
    module Web
      class ClearCache
        def initialize(app)
          @app = app
        end

        def call(env)
          @app.call(env)
        ensure
          Sequent.aggregate_repository.clear!
        end
      end
    end
  end
end
