# frozen_string_literal: true

require 'active_record'
require_relative 'persistor'
require_relative 'record_structs'
require_relative 'statements'

module Sequent
  module Core
    module Persistors
      #
      # Persistor that buffers the changes made by a projector and writes them to the database when +flush+ (or
      # +commit+) is called, combining statements where this cannot change the outcome.
      #
      # Projectors that update a record with an event per changed attribute execute a statement per event with the
      # +ActiveRecordPersistor+. With this persistor the updates of a record are combined into a single statement.
      #
      # Only the methods that write to the database without reading from it are supported: +create_record+,
      # +create_records+, +update_all_records+ and +delete_all_records+. All other methods fail, since the records they
      # read may have pending changes.
      #
      # Like the +ReplayOptimizedPostgresPersistor+, the created records are structs with all columns of the record
      # class, using the column defaults of the record class for the columns without a value, and +created_at+ as
      # +updated_at+. Like ActiveRecord, a nil in a column without a known default (like a serial primary key or a
      # default of +now()+) is inserted as +DEFAULT+, so the database uses its default. ActiveRecord does not know the
      # defaults of the columns of a view, so through a view a nil is the default of the table in any column.
      #
      # The statements are executed in the order in which they were made, except that:
      #
      # - Records created in the same table are inserted using a single multi-row insert.
      # - Updates of the same records (using an identical where clause) are combined into a single update.
      #
      # A statement is only moved before an earlier statement when the statements cannot affect each other. This is
      # decided using the column names only, so without comparing values: an update is moved before an earlier update
      # when neither one changes a column the other one uses. Statements for different tables are assumed not to
      # affect each other. This does not hold when, for example, a trigger on one table changes another table.
      #
      # Like +insert_all+ and +update_all+, the statements do not instantiate models, so no validations or callbacks
      # are executed.
      #
      # A BufferedPersistor is meant for a single batch of events: create a new one (and projector) for every batch, and
      # flush it after handling the events, inside the same transaction. The pending changes are lost when the buffer is
      # not flushed.
      #
      class BufferedPersistor
        include Persistor

        class UnsupportedError < StandardError; end

        def initialize
          @buffer = []
        end

        def create_record(record_class, values, &block)
          record = RecordStructs.create(record_class, values.symbolize_keys, &block)
          add(Statements::Insert.new(record_class, record))
          record
        end

        def create_records(record_class, array_of_value_hashes)
          array_of_value_hashes.each { |values| create_record(record_class, values) }
          nil
        end

        def update_all_records(record_class, where_clause, updates)
          add(Statements::Update.new(record_class, where_clause, updates))
          nil
        end

        def delete_all_records(record_class, where_clause)
          add(Statements::Delete.new(record_class, where_clause))
          nil
        end

        %i[
          update_record
          create_or_update_record
          get_record!
          get_record
          do_with_records
          do_with_record
          delete_record
          find_records
          last_record
          execute_sql
        ].each do |method|
          define_method(method) do |*, **|
            fail UnsupportedError, "#{method} is not supported, as the buffered changes are not visible to it"
          end
        end

        def prepare
          # noop
        end

        ##
        # Executes the buffered statements in the current transaction.
        def flush
          buffer.each(&:execute)
          clear
        end

        ##
        # Discards the buffered statements.
        def clear
          @buffer = []
        end

        ##
        # The number of buffered statements.
        def pending_statements
          buffer.size
        end

        private

        attr_reader :buffer

        def add(operation)
          buffer << operation unless merge_with_earlier(operation)
        end

        # Combines the +operation+ with an earlier operation when possible. Earlier operations are passed while the
        # +operation+ can be moved before them without changing the outcome.
        def merge_with_earlier(operation)
          buffer.reverse_each do |earlier|
            next unless earlier.table_name == operation.table_name
            return true if earlier.merge(operation)
            return false unless operation.independent_of?(earlier)
          end
          false
        end
      end
    end
  end
end
