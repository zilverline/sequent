# frozen_string_literal: true

require_relative '../application_record'

module Sequent
  module Migrations
    module Sql
      def sql_file_to_statements(file_location)
        sql_string = File.read(file_location, encoding: 'bom|utf-8')
        sql_string = yield(sql_string) if block_given?
        sql_string.split(/;$/).reject { |statement| statement.remove("\n").blank? }
      end

      def exec_sql(sql)
        Sequent::ApplicationRecord.connection.execute(sql)
      end
    end
  end
end
