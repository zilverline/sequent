# frozen_string_literal: true

require 'active_record'
require_relative 'record_structs'

module Sequent
  module Core
    module Persistors
      #
      # The statements that the persistors that keep records as structs execute to write records, so these write the
      # same values. Like +insert_all+ and +update_all+, these do not instantiate models, so no validations or
      # callbacks are executed.
      #
      module Statements
        # The value that lets the database use the default of a column.
        DEFAULT = Arel.sql('DEFAULT')

        # Records created in the same table.
        class Insert
          attr_reader :record_class, :records

          def initialize(record_class, *records)
            @record_class = record_class
            @records = records
          end

          ##
          # Inserts the records, and returns the +ActiveRecord::Result+ with the values of the +returning+ columns.
          def execute(returning: false)
            default_columns = RecordStructs.record_class(record_class).default_columns
            rows = records.map do |record|
              record.to_h.to_h do |column, value|
                type = default_columns[column]
                [column, type && Statements.without_value?(type, value) ? DEFAULT : value]
              end
            end
            record_class.unscoped.insert_all!(rows, returning:)
          end
        end

        class Update
          attr_reader :record_class, :where_clause, :updates

          def initialize(record_class, where_clause, updates)
            @record_class = record_class
            @where_clause = where_clause
            @updates = updates
          end

          def execute
            record_class.unscoped.where(where_clause).update_all(updates)
          end
        end

        class Delete
          attr_reader :record_class, :where_clause

          def initialize(record_class, where_clause)
            @record_class = record_class
            @where_clause = where_clause
          end

          def execute
            record_class.unscoped.where(where_clause).delete_all
          end
        end

        # Whether the +value+ is nil after casting it to +type+, like an empty string in an integer column. Only strings
        # are cast, since values of other classes are not cast to nil.
        def self.without_value?(type, value)
          value.nil? || (value.is_a?(String) && type.serialize(value).nil?)
        end
      end
    end
  end
end
