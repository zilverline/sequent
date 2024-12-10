# frozen_string_literal: true

module Sequent
  module Core
    module Helpers
      module PgsqlHelpers
        def call_procedure(connection, procedure, params)
          fail ArgumentError if procedure.blank?

          statement = "CALL #{quote_ident(procedure)}(#{bind_placeholders(params)})"
          connection.exec_update(statement, procedure, params)
        end

        def query_function(connection, function, params, columns: [])
          fail ArgumentError if function.blank?

          cols = columns.blank? ? '*' : columns.map { |c| PG::Connection.quote_ident(c) }.join(', ')
          query = "SELECT #{cols} FROM #{quote_ident(function)}(#{bind_placeholders(params)})"
          connection.exec_query(query, function, params)
        end

        private

        def bind_placeholders(params)
          (1..params.size).map { |n| "$#{n}" }.join(', ')
        end

        def quote_ident(...) = PG::Connection.quote_ident(...)
      end
    end
  end
end
