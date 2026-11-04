# frozen_string_literal: true

require 'concurrent/map'

module Sequent
  module Core
    module Persistors
      #
      # The records of the in-memory persistors are structs, so we implement the ==, eql? and hash methods to point to
      # the same object. A record is the same if and only if they point to the same object. These methods are
      # necessary since records are kept in sets.
      #
      # Also basing equality on object identity is more consistent with ActiveRecord, which is the implementation used
      # during normal (non-optimized) replay.
      #
      module InMemoryStruct
        def ==(other)
          equal?(other)
        end

        def eql?(other)
          equal?(other)
        end

        def hash
          object_id.hash
        end

        # Marks a computed +column+ as updated to nil, so it is not left out when the record is loaded.
        def updated!(column)
          (@updated_columns ||= Set.new) << column
        end

        def updated?(column)
          @updated_columns&.include?(column) || false
        end
      end

      #
      # Creates the records of the persistors that keep records as structs, like the +ReplayOptimizedPostgresPersistor+,
      # with all columns of their record class, the same way ActiveRecord creates records: using the column defaults of
      # the record class for the columns without a value, +created_at+ as +updated_at+, and the current time for the
      # timestamps without a value.
      #
      module RecordStructs
        # The struct class and columns of a record class:
        #
        # - +defaults+: the column defaults that ActiveRecord knows.
        # - +timestamp_columns+: the timestamps set when creating a record, when the record class records timestamps.
        # - +computed_columns+: the columns whose default the database computes, like a serial column.
        # - +default_columns+: the types of the columns without a default that ActiveRecord knows, whose type
        #   serializes nil to nil, so the database uses its default when they have no value.
        RecordClass = Data.define(
          :column_names,
          :struct,
          :defaults,
          :timestamp_columns,
          :computed_columns,
          :default_columns,
        )

        # The record classes, shared by all persistors, which may be created for every batch of events.
        RECORD_CLASSES = Concurrent::Map.new

        ##
        # Returns the struct class and columns of +record_class+. These are determined again when the columns of the
        # record class are reset (using +reset_column_information+), since ActiveRecord then determines new column
        # names.
        def self.record_class(record_class)
          column_names = record_class.column_names
          cached = RECORD_CLASSES[record_class]
          return cached if cached&.column_names.equal?(column_names)

          RECORD_CLASSES[record_class] = new_record_class(record_class, column_names)
        end

        ##
        # Creates a record of +record_class+ with the +values+ and yields it, like ActiveRecord creates a record.
        def self.create(record_class, values)
          columns = record_class(record_class)
          record = columns.struct.new(**values)
          # Defaults like arrays are shared by all records, so each record gets its own copy to change.
          columns.defaults.each do |column, default|
            record[column] = default.frozen? ? default : default.deep_dup unless values.include?(column)
          end
          record.updated_at = values[:created_at] if record.respond_to?(:updated_at=) && !values.include?(:updated_at)
          yield record if block_given?
          touch_timestamps(record_class, record, columns.timestamp_columns)
          record
        end

        # Sets the timestamps without a value to the current time, like ActiveRecord does when creating a record.
        def self.touch_timestamps(record_class, record, timestamp_columns)
          now = nil
          timestamp_columns.each do |column|
            record[column] ||= (now ||= record_class.current_time_from_proper_timezone)
          end
        end
        private_class_method :touch_timestamps

        def self.new_record_class(record_class, column_names)
          defaults = record_class.column_defaults.symbolize_keys.freeze
          timestamp_columns = record_class.record_timestamps ? record_class.all_timestamp_attributes_in_model : []
          default_columns = column_names.to_h { |name| [name.to_sym, record_class.type_for_attribute(name)] }
          default_columns.select! { |name, type| defaults[name].nil? && type.serialize(nil).nil? }
          RecordClass.new(
            column_names:,
            struct: Struct.new(*column_names.map(&:to_sym)) { include InMemoryStruct },
            defaults:,
            timestamp_columns: timestamp_columns.map(&:to_sym).freeze,
            computed_columns: record_class.columns.select(&:auto_populated?).map { |column| column.name.to_sym }.freeze,
            default_columns: default_columns.freeze,
          )
        end
        private_class_method :new_record_class
      end
    end
  end
end
