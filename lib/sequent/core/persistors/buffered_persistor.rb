# frozen_string_literal: true

require 'active_record'
require 'concurrent/map'
require_relative 'persistor'
require_relative 'replay_optimized_postgres_persistor'

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

        # The value that lets the database use the default of a column.
        DEFAULT = Arel.sql('DEFAULT')

        # Records created in the same table.
        class Insert
          attr_reader :record_class, :records

          def initialize(record_class, record)
            @record_class = record_class
            @records = [record]
          end

          def table_name = record_class.table_name

          def merge(later)
            return false unless later.is_a?(Insert) && later.record_class == record_class

            records.concat(later.records)
            true
          end

          # Inserts into the same table do not affect each other.
          def independent_of?(earlier) = earlier.is_a?(Insert)

          def execute
            default_columns = BufferedPersistor.record_columns(record_class).default_columns
            rows = records.map do |record|
              record.to_h.to_h do |column, value|
                type = default_columns[column]
                [column, type && BufferedPersistor.without_value?(type, value) ? DEFAULT : value]
              end
            end
            record_class.unscoped.insert_all!(rows, returning: false)
          end
        end

        class Update
          attr_reader :record_class, :where_clause, :updates, :where_columns, :update_columns

          def initialize(record_class, where_clause, updates)
            @record_class = record_class
            @where_clause = where_clause
            @updates = updates

            return unless simple_hash?(where_clause) && simple_hash?(updates)

            @where_clause = where_clause.stringify_keys
            @updates = updates.stringify_keys
            @where_columns = @where_clause.keys.to_set
            @update_columns = @updates.keys.to_set
            @combinable = !@where_columns.intersect?(@update_columns)
          end

          def table_name = record_class.table_name

          # Whether this update can be combined with other updates, or moved before them. This is only possible when
          # the where clause and updates only use columns, and the update does not change the records it applies to.
          def combinable? = @combinable

          def merge(later)
            return false unless combinable? && later.is_a?(Update) && later.combinable?
            return false unless later.record_class == record_class && later.where_clause == where_clause

            @updates = updates.merge(later.updates)
            @update_columns = @updates.keys.to_set
            true
          end

          def independent_of?(earlier)
            return false unless combinable? && earlier.is_a?(Update) && earlier.combinable?

            !update_columns.intersect?(earlier.update_columns) &&
              !update_columns.intersect?(earlier.where_columns) &&
              !earlier.update_columns.intersect?(where_columns)
          end

          def execute
            record_class.unscoped.where(where_clause).update_all(updates)
          end

          private

          def simple_hash?(hash)
            hash.is_a?(Hash) && hash.all? do |column, value|
              record_class.column_names.include?(column.to_s) && !value.is_a?(Hash)
            end
          end
        end

        class Delete
          attr_reader :record_class, :where_clause

          def initialize(record_class, where_clause)
            @record_class = record_class
            @where_clause = where_clause
          end

          def table_name = record_class.table_name

          def merge(_later) = false

          # Deletes do not affect each other.
          def independent_of?(earlier) = earlier.is_a?(Delete)

          def execute
            record_class.unscoped.where(where_clause).delete_all
          end
        end

        # The struct classes and defaults of the record classes, shared by all BufferedPersistors since a
        # BufferedPersistor is created for every batch of events.
        # The struct class, column defaults, the types of the columns inserted as +DEFAULT+ without a value and the
        # timestamp columns set when creating a record of a record class.
        RecordColumns = Data.define(:column_names, :struct, :defaults, :default_columns, :timestamp_columns)

        # The record columns of the record classes, shared by all BufferedPersistors since a BufferedPersistor is
        # created for every batch of events.
        RECORD_COLUMNS = Concurrent::Map.new

        # Returns the record columns of +record_class+. These are determined again when the columns of the record class
        # are reset (using +reset_column_information+), since ActiveRecord then determines new column names.
        def self.record_columns(record_class)
          column_names = record_class.column_names
          record_columns = RECORD_COLUMNS[record_class]
          return record_columns if record_columns&.column_names.equal?(column_names)

          RECORD_COLUMNS[record_class] = new_record_columns(record_class, column_names)
        end

        # A nil in a column without a known default is inserted as +DEFAULT+, unless the type of the column serializes
        # nil to another value, like a column normalized when nil.
        # Whether the +value+ is nil after casting it to +type+, like an empty string in an integer column. Only strings
        # are cast, since values of other classes are not cast to nil.
        def self.without_value?(type, value)
          value.nil? || (value.is_a?(String) && type.serialize(value).nil?)
        end

        def self.new_record_columns(record_class, column_names)
          defaults = record_class.column_defaults.symbolize_keys.freeze
          default_columns = column_names.to_h { |name| [name.to_sym, record_class.type_for_attribute(name)] }
          default_columns.select! { |name, type| defaults[name].nil? && type.serialize(nil).nil? }
          RecordColumns.new(
            column_names:,
            struct: Struct.new(*column_names.map(&:to_sym)) do
              include ReplayOptimizedPostgresPersistor::InMemoryStruct
            end,
            defaults:,
            default_columns: default_columns.freeze,
            timestamp_columns:
              record_class.record_timestamps ? record_class.all_timestamp_attributes_in_model.map(&:to_sym) : [],
          )
        end
        private_class_method :new_record_columns

        def initialize
          @buffer = []
        end

        def create_record(record_class, values)
          values = values.symbolize_keys
          record_columns = BufferedPersistor.record_columns(record_class)
          record = record_columns.struct.new(**record_columns.defaults, **values)
          record.updated_at = values[:created_at] if record.respond_to?(:updated_at) && !values.include?(:updated_at)
          yield record if block_given?
          touch_timestamps(record_class, record, record_columns.timestamp_columns)

          add(Insert.new(record_class, record))
          record
        end

        def create_records(record_class, array_of_value_hashes)
          array_of_value_hashes.each { |values| create_record(record_class, values) }
          nil
        end

        def update_all_records(record_class, where_clause, updates)
          add(Update.new(record_class, where_clause, updates))
          nil
        end

        def delete_all_records(record_class, where_clause)
          add(Delete.new(record_class, where_clause))
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

        # Sets the timestamps without a value to the current time, like ActiveRecord does when creating a record.
        def touch_timestamps(record_class, record, timestamp_columns)
          now = nil
          timestamp_columns.each do |column|
            record[column] ||= (now ||= record_class.current_time_from_proper_timezone)
          end
        end

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
