# frozen_string_literal: true

require 'active_record'
require_relative 'persistor'
require_relative 'record_structs'
require_relative 'statements'

module Sequent
  module Core
    module Persistors
      #
      # Persistor that writes every change to the database right away, like the +ActiveRecordPersistor+, but keeps
      # records as structs created by +RecordStructs+, like the +ReplayOptimizedPostgresPersistor+, and writes them
      # using +Statements+. It therefore creates records the same way: using the column defaults of the record class
      # for the columns without a value, +created_at+ as +updated_at+, and the database default for a nil in a column
      # without a known default.
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

        def update_record(record_class, event, where_clause = {aggregate_id: event.aggregate_id}, options = {})
          record = get_record(record_class, where_clause)
          unless record
            fail(<<~EOS)
              Record of class #{record_class} with where clause #{where_clause} not found while handling event #{event}
            EOS
          end

          save(record_class, record) do
            record.updated_at = event.created_at if record.respond_to?(:updated_at=)
            yield record if block_given?
            update_sequence_number = options.fetch(:update_sequence_number) { record.respond_to?(:sequence_number=) }
            record.sequence_number = event.sequence_number if update_sequence_number
          end
        end

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

        def create_or_update_record(record_class, values, created_at = Time.now, &block)
          record = get_record(record_class, values)
          return save(record_class, record) { yield record } if record

          values = values.merge(created_at:) if record_class.column_names.include?('created_at')
          create_record(record_class, values, &block)
        end

        def get_record!(record_class, where_clause)
          record = get_record(record_class, where_clause)
          return record if record

          fail ActiveRecord::RecordNotFound.new("Couldn't find #{record_class} with #{where_clause}", record_class.name)
        end

        def get_record(record_class, where_clause)
          first_record(record_class, where_clause, :asc)
        end

        def last_record(record_class, where_clause)
          first_record(record_class, where_clause, :desc)
        end

        def find_records(record_class, where_clause)
          select_records(record_class, record_class.unscoped.where(where_clause))
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

        def do_with_records(record_class, where_clause)
          find_records(record_class, where_clause).each do |record|
            save(record_class, record) { yield record }
          end
        end

        def do_with_record(record_class, where_clause)
          record = get_record!(record_class, where_clause)
          save(record_class, record) { yield record }
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

        def first_record(record_class, where_clause, direction)
          relation = record_class.unscoped.where(where_clause)
          primary_key = record_class.primary_key
          relation = relation.order(Array(primary_key).to_h { |column| [column, direction] }) if primary_key
          select_records(record_class, relation.limit(1)).first
        end

        def select_records(record_class, relation)
          columns = RecordStructs.record_class(record_class)
          relation.pluck(*columns.column_names).map do |values|
            columns.struct.new(*(columns.column_names.size == 1 ? [values] : values))
          end
        end

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

        # Writes the columns of the +record+ that the block changes, like ActiveRecord saves a record.
        def save(record_class, record)
          before = record.to_h.deep_dup
          yield
          changes = changed_columns(record_class, before, record)
          return record if changes.empty?

          Statements::Update.new(
            record_class,
            primary_key_values(record_class, before),
            changes.to_h { |column| [column, record[column]] },
          ).execute
          record
        end

        def changed_columns(record_class, before, record)
          # The columns are the keys, since a column named members would replace Struct#members.
          before.keys.reject do |column|
            record_class.type_for_attribute(column.to_s).cast(record[column]) == before[column]
          end
        end

        def primary_key_values(record_class, values)
          primary_key = record_class.primary_key or fail ActiveRecord::UnknownPrimaryKey, record_class
          Array(primary_key).to_h { |column| [column, values.fetch(column.to_sym)] }
        end
      end
    end
  end
end
