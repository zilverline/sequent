# frozen_string_literal: true

require 'active_record'
require_relative 'record_structs'

module Sequent
  module Core
    module Persistors
      #
      # The statements that the +BufferedPersistor+ and the +UnbufferedPersistor+ execute to write records, so both
      # write the same values. Like +insert_all+ and +update_all+, these do not instantiate models, so no validations
      # or callbacks are executed.
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

          def table_name = record_class.table_name

          def merge(later)
            return false unless later.is_a?(Insert) && later.record_class == record_class

            records.concat(later.records)
            true
          end

          # Inserts into the same table do not affect each other.
          def independent_of?(earlier) = earlier.is_a?(Insert)

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

        # Whether the +value+ is nil after casting it to +type+, like an empty string in an integer column. Only strings
        # are cast, since values of other classes are not cast to nil.
        def self.without_value?(type, value)
          value.nil? || (value.is_a?(String) && type.serialize(value).nil?)
        end
      end
    end
  end
end
