# frozen_string_literal: true

require 'active_record'
require 'concurrent/map'
require_relative 'record_structs'

module Sequent
  module Core
    module Persistors
      #
      # The statements that the persistors that keep records as structs execute to write and read records. These
      # generate their SQL, which is the same for every statement of the same shape, and execute it through ActiveRecord
      # as a prepared statement with the values as binds. Where clauses that cannot be written like that, like one with
      # a range, are left to ActiveRecord. Like +insert_all+ and +update_all+, these do not instantiate models, so no
      # validations or callbacks are executed.
      #
      module Statements
        # The most values PostgreSQL accepts as parameters of one statement.
        MAX_BIND_PARAMETERS = 65_535

        # The classes of values that are written to a column or compared with it as a bind. Other values, like a range
        # or an Arel node in a where clause, are left to ActiveRecord.
        SCALARS = [String, Symbol, Numeric, Date, Time, TrueClass, FalseClass].freeze

        # The generated SQL, so the same statement shape always has the same SQL text, which lets the database reuse
        # the prepared statement.
        SQL = Concurrent::Map.new

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
          # Columns without a value that the database can default are left out of the statement, so consecutive
          # records with different columns are inserted by separate statements, which keeps their order.
          def execute(returning: false)
            default_columns = RecordStructs.record_class(record_class).default_columns
            rows = records.map do |record|
              record.to_h.reject do |column, value|
                (type = default_columns[column]) && Statements.without_value?(type, value)
              end
            end
            result = nil
            rows.chunk_while { |row, next_row| row.keys == next_row.keys }.each do |group|
              columns = group.first.keys
              if group.size > 1 && Statements.unnestable?(record_class, columns)
                result = insert_unnest(columns, group, returning)
              else
                each_slice(group, columns) { |slice| result = insert_values(columns, slice, returning) }
              end
            end
            result
          end

          private

          def each_slice(rows, columns, &)
            return rows.each { |row| yield [row] } if columns.empty?

            rows.each_slice(MAX_BIND_PARAMETERS / columns.size, &)
          end

          def insert_values(columns, rows, returning)
            returning = returning ? Array(returning) : []
            sql = Statements.cached(:insert, record_class, columns, rows.size, returning) do
              Statements.insert_sql(record_class, columns, rows.size, returning)
            end
            binds = rows.flat_map { |row| columns.map { |column| Statements.bind(record_class, column, row[column]) } }
            Statements.execute(record_class, sql, binds, 'Insert', prepare: rows.size == 1)
          end

          def insert_unnest(columns, rows, returning)
            returning = returning ? Array(returning) : []
            sql = Statements.cached(:insert_unnest, record_class, columns, returning) do
              Statements.unnest_sql(record_class, columns, returning)
            end
            binds = columns.map do |column|
              Statements.unnest_bind(
                record_class,
                column,
                rows.map do |row|
                  row[column]
                end,
              )
            end
            Statements.execute(record_class, sql, binds, 'Insert')
          end
        end

        class Update
          attr_reader :record_class, :where_clause, :updates, :where_columns, :update_columns

          def initialize(record_class, where_clause, updates)
            @record_class = record_class
            @where_clause = where_clause
            @updates = updates

            return unless Statements.conditions(record_class, where_clause) && sql_updates?

            @where_clause = where_clause.stringify_keys
            @updates = updates.stringify_keys
            @where_columns = @where_clause.keys.to_set
            @update_columns = @updates.keys.to_set
            @combinable = !@where_columns.intersect?(@update_columns)
          end

          def table_name = record_class.table_name

          # Whether this update can be combined with other updates, or moved before them. This is only possible when
          # it is written as SQL with binds, and does not change a column of its own where clause. An update that is
          # left to ActiveRecord can use anything, so it stays where it is.
          def combinable? = @combinable || false

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
            conditions = Statements.conditions(record_class, where_clause)
            return record_class.unscoped.where(where_clause).update_all(updates) unless conditions && sql_updates?

            columns = updates.keys
            sql = Statements.cached(:update, record_class, columns, Statements.shape(conditions)) do
              sets = columns.each_with_index.map do |column, index|
                "#{Statements.quote(record_class, column)} = $#{index + 1}"
              end
              "UPDATE #{record_class.quoted_table_name} SET #{sets.join(', ')}" \
                "#{Statements.where_sql(record_class, conditions, columns.size)}"
            end
            binds = updates.map { |column, value| Statements.bind(record_class, column, value) }
            binds.concat(Statements.condition_binds(record_class, conditions))
            Statements.execute(record_class, sql, binds, 'Update').affected_rows
          end

          private

          def sql_updates?
            updates.is_a?(Hash) && updates.any? &&
              updates.all? do |column, value|
                record_class.columns_hash.key?(column.to_s) && !value.is_a?(Arel::Nodes::Node) &&
                  !value.is_a?(Arel::Attributes::Attribute) && !value.is_a?(Arel::Nodes::SqlLiteral)
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
            conditions = Statements.conditions(record_class, where_clause)
            return record_class.unscoped.where(where_clause).delete_all unless conditions

            sql = Statements.cached(:delete, record_class, Statements.shape(conditions)) do
              "DELETE FROM #{record_class.quoted_table_name}#{Statements.where_sql(record_class, conditions, 0)}"
            end
            Statements.execute(record_class, sql, Statements.condition_binds(record_class, conditions), 'Delete')
              .affected_rows
          end
        end

        # Reads the records that match the where clause, ordered by primary key in +direction+ when it is given, as
        # structs with all columns.
        class Select
          attr_reader :record_class, :where_clause, :direction, :limit

          def initialize(record_class, where_clause, direction: nil, limit: nil)
            @record_class = record_class
            @where_clause = where_clause
            @direction = direction
            @limit = limit
          end

          def execute
            columns = RecordStructs.record_class(record_class)
            conditions = Statements.conditions(record_class, where_clause)
            result = conditions ? select(columns, conditions) : relation_values(columns)
            result.map { |values| columns.struct.new(*values) }
          end

          private

          def select(columns, conditions)
            shape = Statements.shape(conditions)
            sql = Statements.cached(:select, record_class, columns.column_names, shape, direction, limit) do
              sql = "SELECT #{columns.column_names.map { |name| Statements.quote(record_class, name) }.join(', ')} " \
                    "FROM #{record_class.quoted_table_name}#{Statements.where_sql(record_class, conditions, 0)}"
              sql += " ORDER BY #{order_sql}" if order_sql
              sql += " LIMIT #{Integer(limit)}" if limit
              sql
            end
            result = Statements.execute(
              record_class,
              sql,
              Statements.condition_binds(record_class, conditions),
              'Load',
            )
            rows = result.cast_values(columns.column_names.map { |name| record_class.type_for_attribute(name) })
            columns.column_names.size == 1 ? rows.map { |value| [value] } : rows
          end

          def order_sql
            primary_key = record_class.primary_key
            return unless direction && primary_key

            Array(primary_key).map do |column|
              "#{Statements.quote(record_class, column)} #{direction.to_s.upcase}"
            end.join(', ')
          end

          def relation_values(columns)
            relation = record_class.unscoped.where(where_clause)
            primary_key = record_class.primary_key
            if direction && primary_key
              relation = relation.order(Array(primary_key).to_h { |column| [column, direction] })
            end
            relation = relation.limit(limit) if limit
            rows = relation.pluck(*columns.column_names)
            columns.column_names.size == 1 ? rows.map { |value| [value] } : rows
          end
        end

        # The conditions of a where clause that can be written as SQL with binds, as [column, value, kind]; nil
        # when ActiveRecord has to handle the where clause.
        def self.conditions(record_class, where_clause)
          return unless where_clause.is_a?(Hash)

          where_clause.map do |column, value|
            name = column.to_s
            return nil unless record_class.columns_hash.key?(name)

            kind = condition_kind(record_class.type_for_attribute(name), value) or return nil
            [name, value, kind]
          end
        end

        def self.condition_kind(type, value)
          case value
          when nil then :null
          when Array
            return if type.is_a?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array)
            return unless value.all? { |element| element.nil? || scalar?(element) }

            present = value.compact
            nil_included = present.size != value.size
            return nil_included ? :null : :none if present.empty?

            nil_included ? :any_or_null : :any
          else
            :eq if scalar?(value)
          end
        end

        def self.scalar?(value)
          SCALARS.any? { |scalar| value.is_a?(scalar) }
        end

        def self.shape(conditions)
          conditions.map { |name, _value, kind| [name, kind] }
        end

        def self.where_sql(record_class, conditions, offset)
          return '' if conditions.empty?

          index = offset
          sql = conditions.map do |name, _value, kind|
            column = quote(record_class, name)
            case kind
            when :null then "#{column} IS NULL"
            when :none then 'FALSE'
            when :eq then "#{column} = $#{index += 1}"
            when :any then "#{column} = ANY($#{index += 1})"
            when :any_or_null then "(#{column} = ANY($#{index += 1}) OR #{column} IS NULL)"
            end
          end
          " WHERE #{sql.join(' AND ')}"
        end

        def self.condition_binds(record_class, conditions)
          conditions.filter_map do |name, value, kind|
            case kind
            when :eq then bind(record_class, name, value)
            when :any, :any_or_null then array_bind(record_class, name, value.compact)
            end
          end
        end

        def self.insert_sql(record_class, columns, row_count, returning)
          sql = "INSERT INTO #{record_class.quoted_table_name}"
          if columns.empty?
            sql += ' DEFAULT VALUES'
          else
            index = 0
            rows = Array.new(row_count) { "(#{Array.new(columns.size) { "$#{index += 1}" }.join(', ')})" }
            sql += " (#{columns.map { |column| quote(record_class, column) }.join(', ')}) VALUES #{rows.join(', ')}"
          end
          sql += " RETURNING #{returning.map { |column| quote(record_class, column) }.join(', ')}" if returning.any?
          sql
        end

        # Whether rows with these columns can be inserted with +unnest+, which flattens multi-dimensional arrays, so
        # not when a column is an array itself.
        def self.unnestable?(record_class, columns)
          columns.none? do |column|
            record_class.type_for_attribute(column.to_s).is_a?(ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array)
          end
        end

        def self.unnest_sql(record_class, columns, returning)
          arrays = columns.each_with_index.map do |column, index|
            "$#{index + 1}::#{record_class.columns_hash.fetch(column.to_s).sql_type}[]"
          end
          sql = "INSERT INTO #{record_class.quoted_table_name} (#{columns.map do |name|
            quote(record_class, name)
          end.join(', ')}) " \
                "SELECT * FROM unnest(#{arrays.join(', ')})"
          sql += " RETURNING #{returning.map { |column| quote(record_class, column) }.join(', ')}" if returning.any?
          sql
        end

        # The bind with the +values+ of a column, one for every row. A JSON value that is an array would be read as
        # a dimension of the bind, so JSON values are serialized first and bound as text, which the cast in the SQL
        # reads as JSON.
        def self.unnest_bind(record_class, column, values)
          name = column.to_s
          type = record_class.type_for_attribute(name)
          return array_bind(record_class, name, values) unless %i[json jsonb].include?(type.type)

          texts = ActiveModel::Type::String.new
          array_type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array.new(texts)
          ActiveRecord::Relation::QueryAttribute.new(name, values.map { |value| type.serialize(value) }, array_type)
        end

        def self.quote(record_class, column)
          record_class.connection.quote_column_name(column)
        end

        def self.bind(record_class, column, value)
          name = column.to_s
          ActiveRecord::Relation::QueryAttribute.new(name, value, record_class.type_for_attribute(name))
        end

        def self.array_bind(record_class, column, values)
          name = column.to_s
          type = ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Array.new(record_class.type_for_attribute(name))
          ActiveRecord::Relation::QueryAttribute.new(name, values, type)
        end

        def self.cached(*key, &)
          SQL.compute_if_absent(key, &)
        end

        # Executes the +sql+ with the +binds+ through ActiveRecord, which prepares it when +prepare+ is true and
        # clears the query cache.
        def self.execute(record_class, sql, binds, name, prepare: true)
          log_name = "#{record_class.name || record_class.table_name} #{name}"
          record_class.connection.exec_query(sql, log_name, binds, prepare:)
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
