# frozen_string_literal: true

require 'active_record'
require_relative 'persistor'
require_relative 'record_reading'
require_relative 'record_structs'
require_relative 'statements'

module Sequent
  module Core
    module Persistors
      #
      # Persistor that writes every change to the database right away, like the +ActiveRecordPersistor+, but keeps
      # records as structs created by +RecordStructs+, like the +ReplayOptimizedPostgresPersistor+, and writes and
      # reads them using +Statements+, which generates the SQL and has ActiveRecord prepare it, with the values as
      # binds, so they stay out of the SQL text. It creates records the same way as the
      # +ReplayOptimizedPostgresPersistor+: using the column defaults of the record class for the columns without a
      # value, +created_at+ as +updated_at+, and the database default for a nil in a column without a known default.
      #
      # Records are read as structs with all columns, without instantiating models, so no validations or callbacks
      # are executed. Like ActiveRecord:
      #
      # - +get_record+ and +last_record+ return the first and last record ordered by primary key.
      # - Creating a record sets its primary key and the other columns that the database computes.
      # - A record changed by a block is written using its primary key, for the changed columns only. Like with the
      #   other persistors, its +updated_at+ only changes when it is set.
      #
      class UnbufferedPersistor
        include Persistor
        include RecordReading

        def create_record(record_class, values, &block)
          record = RecordStructs.create(record_class, values.symbolize_keys, &block)
          returning = returning_columns(record_class, record)
          result = Statements::Insert.new(record_class, record).execute(returning: returning.presence || false)
          assign_returned_values(record_class, record, returning, result) if returning.present?
          record
        end

        def create_records(record_class, array_of_value_hashes)
          records = array_of_value_hashes.map { |values| RecordStructs.create(record_class, values.symbolize_keys) }
          Statements::Insert.new(record_class, *records).execute unless records.empty?
          nil
        end

        def delete_all_records(record_class, where_clause)
          Statements::Delete.new(record_class, where_clause).execute
        end

        def delete_record(record_class, record)
          Statements::Delete.new(record_class, primary_key_values(record_class, record.to_h)).execute
        end

        def update_all_records(record_class, where_clause, updates)
          Statements::Update.new(record_class, where_clause, updates).execute
        end

        def execute_sql(statement)
          Sequent::ApplicationRecord.connection.execute(statement)
        end

        def prepare
          # noop
        end

        def flush
          # noop
        end

        private

        # Like ActiveRecord, the primary key and the other columns that the database computes are returned when
        # inserting a record without a value for them, like the insert decides which columns get their default.
        def returning_columns(record_class, record)
          computed_columns = RecordStructs.record_class(record_class).computed_columns
          columns = [*Array(record_class.primary_key).map(&:to_sym), *computed_columns]
          columns.uniq.select do |column|
            record.respond_to?(column) &&
              Statements.without_value?(record_class.type_for_attribute(column.to_s), record[column])
          end
        end

        def assign_returned_values(record_class, record, columns, result)
          values = result.rows.first
          columns.each_with_index do |column, index|
            record[column] = record_class.type_for_attribute(column.to_s).deserialize(values[index])
          end
        end

        def select_records(record_class, where_clause, **)
          Statements::Select.new(record_class, where_clause, **).execute
        end

        def write_update(statement)
          statement.execute
        end
      end
    end
  end
end
