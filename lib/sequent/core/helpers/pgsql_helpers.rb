# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module PgsqlHelpers
        def call_procedure(procedure, params)
          statement = "CALL #{procedure}(#{bind_placeholders(params)})"
          connection.exec_update(statement, procedure, params)
        end

        def query_function(function, params, columns = ['*'])
          query = "SELECT #{columns.join(', ')} FROM #{function}(#{bind_placeholders(params)})"
          connection.exec_query(query, function, params)
        end

        private

        def bind_placeholders(params)
          (1..params.size).map { |n| "$#{n}" }.join(', ')
        end
      end
    end
  end
end
