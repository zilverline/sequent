# frozen_string_literal: true

require 'active_record'
require_relative 'persistor'

module Sequent
  module Core
    module Persistors
      #
      # The ReplayOptimizedPostgresPersistor is optimized for bulk loading records in a Postgres database.
      #
      # The records are loaded into the database using a single COPY statement per table. The values are encoded
      # for the COPY by the C encoders of the pg gem when they already have the Ruby class of their column type, and
      # are serialized by ActiveRecord otherwise.
      #
      # A column without a value whose default the database computes, like a serial column or a default of +now()+,
      # is left out of the COPY, so the database computes its value. When only some records have a value for such a
      # column, the records are loaded using a COPY per set of columns. All other columns without a value are loaded
      # as NULL.
      #
      # Rebuilding the view state (or projection) of an aggregate typically consists
      # of an initial insert and then many updates and maybe a delete.
      # With a normal Persistor (like ActiveRecordPersistor) each action is executed to the database.
      # This persistor creates an in-memory store first and finally flushes
      # the in-memory store to the database. This can significantly reduce the amount of queries to the database.
      # E.g. 1 insert, 6 updates is only a single insert using this Persistor.
      #
      # After lot of experimenting this turned out to be the fastest way to to bulk inserts in the database.
      #
      # It is highly recommended to create +indices+ on the in memory +record_store+ to speed up the processing.
      # By default all records are indexed by +aggregate_id+ if they have such a property.
      #
      # Example:
      #
      #   class InvoiceProjector < Sequent::Core::Projector
      #     on RecipientMovedEvent do |event|
      #       update_all_records(
      #         InvoiceRecord,
      #         { aggregate_id: event.aggregate_id, recipient_id: event.recipient.aggregate_id },
      #         { recipient_street: event.recipient.street },
      #       end
      #     end
      #   end
      #
      # In this case it is wise to create an index on InvoiceRecord on the aggregate_id and recipient_id
      # attributes like you would in the database. Note that previous versions of this class supported
      # multi-column indexes. These are now split into multiple single-column indexes and the results of
      # each index is combined using set-intersection. This reduces the amount of memory used and makes
      # it possible to use an index in more cases (whenever an indexed attribute is present in the where
      # clause the index will be used, so not all attributes need to be present).
      #
      # Example:
      #
      #   ReplayOptimizedPostgresPersistor.new(
      #     50,
      #     {InvoiceRecord => [:aggregate_id, :recipient_id]}
      #   )
      class ReplayOptimizedPostgresPersistor
        include Persistor

        # @deprecated no longer used
        CHUNK_SIZE = 1024

        attr_reader :record_store
        # @deprecated records are always loaded using COPY
        attr_accessor :insert_with_csv_size

        # We create a struct on the fly to represent an in-memory record.
        #
        # Since the replay happens in memory we implement the ==, eql? and hash methods
        # to point to the same object. A record is the same if and only if they point to
        # the same object. These methods are necessary since we use Set instead of [].
        #
        # Also basing equality on object identity is more consistent with ActiveRecord,
        # which is the implementation used during normal (non-optimized) replay.
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

          # Marks a computed +column+ as updated, so it is not left out of the COPY when it was updated to nil.
          def updated!(column)
            (@updated_columns ||= Set.new) << column
          end

          def updated?(column)
            @updated_columns&.include?(column) || false
          end
        end

        def struct_cache
          @struct_cache ||= Hash.new do |hash, record_class|
            struct_class = Struct.new(*record_class.column_names.map(&:to_sym)) do
              include InMemoryStruct
            end
            hash[record_class] = struct_class
          end
        end

        class Index
          attr_reader :indexed_columns

          def initialize(indexed_columns)
            @indexed_columns = indexed_columns.to_set
            @indexes = @indexed_columns.to_h do |field|
              [field, {}]
            end
            @reverse_indexes = @indexed_columns.to_h do |field|
              [field, {}.compare_by_identity]
            end
          end

          def add(record)
            @indexes.each do |field, index|
              key = Persistors.normalize_symbols(record[field]).freeze
              records = index[key] || (index[key] = Set.new.compare_by_identity)
              records << record
              @reverse_indexes[field][record] = key
            end
          end

          def remove(record)
            @indexes.each do |field, index|
              key = @reverse_indexes[field].delete(record)
              remaining = index[key]&.delete(record)
              index.delete(key) if remaining && remaining.empty?
            end
          end

          def update(record)
            remove(record)
            add(record)
          end

          def find(normalized_where_clause)
            record_sets = normalized_where_clause.map do |(field, expected_value)|
              if expected_value.is_a?(Array)
                expected_value.reduce(Set.new.compare_by_identity) do |memo, value|
                  key = Persistors.normalize_symbols(value)
                  memo.merge(@indexes[field][key] || [])
                end
              else
                key = Persistors.normalize_symbols(expected_value)
                @indexes[field][key] || Set.new.compare_by_identity
              end
            end

            smallest, *rest = record_sets.sort_by(&:size)
            return smallest.to_a if smallest.empty? || rest.empty?

            smallest.select do |record|
              rest.all? { |x| x.include? record }
            end
          end

          def clear
            @indexed_columns.each do |field|
              @indexes[field].clear
              @reverse_indexes[field].clear
            end
          end

          def use_index?(normalized_where_clause)
            get_indexes(normalized_where_clause).present?
          end

          private

          def get_indexes(normalized_where_clause)
            @indexed_columns & normalized_where_clause.keys
          end
        end

        # +insert_with_csv_size+ is ignored, records are always loaded using COPY
        #
        # +indices+ Hash of indices to create in memory. Greatly speeds up the replaying.
        #   Key corresponds to the name of the 'Record'
        #   Values contains list of lists on which columns to index.
        #   E.g. [[:first_index_column], [:another_index, :with_two_columns]]
        def initialize(insert_with_csv_size = 50, indices = {}, default_indexed_columns = [:aggregate_id])
          @insert_with_csv_size = insert_with_csv_size
          @record_store = Hash.new { |h, k| h[k] = Set.new.compare_by_identity }
          @record_index = Hash.new do |h, k|
            h[k] = Index.new(default_indexed_columns.to_set & k.column_names.map(&:to_sym))
          end

          indices.each do |record_class, indexed_columns|
            columns = indexed_columns.flatten(1).to_set(&:to_sym) + default_indexed_columns
            @record_index[record_class] = Index.new(columns & record_class.column_names.map(&:to_sym))
          end

          @record_defaults = Hash.new do |h, record_class|
            h[record_class] = record_class.column_defaults.symbolize_keys
          end
          @timestamp_columns = Hash.new do |h, record_class|
            h[record_class] =
              record_class.record_timestamps ? record_class.all_timestamp_attributes_in_model.map(&:to_sym) : []
          end
          @computed_columns = Hash.new do |h, record_class|
            h[record_class] = record_class.columns.select(&:auto_populated?).map { |column| column.name.to_sym }
          end
        end

        def update_record(record_class, event, where_clause = {aggregate_id: event.aggregate_id}, options = {})
          record = get_record!(record_class, where_clause)
          record.updated_at = event.created_at if record.respond_to?(:updated_at=)
          track_updated_columns(record_class, record) { yield record } if block_given?
          @record_index[record_class].update(record)
          update_sequence_number = if options.key?(:update_sequence_number)
                                     options[:update_sequence_number]
                                   else
                                     record.respond_to?(:sequence_number=)
                                   end
          record.sequence_number = event.sequence_number if update_sequence_number
        end

        def create_record(record_class, values)
          record = struct_cache[record_class].new(**values)
          @record_defaults[record_class].each do |column, default|
            record[column] = default unless values.include? column
          end
          record.updated_at = values[:created_at] if record.respond_to?(:updated_at) && !values.include?(:updated_at)

          yield record if block_given?
          touch_timestamps(record_class, record)

          @record_store[record_class] << record
          @record_index[record_class].add(record)

          record
        end

        def create_records(record_class, array_of_value_hashes)
          array_of_value_hashes.each { |values| create_record(record_class, values) }
        end

        def create_or_update_record(record_class, values, created_at = Time.now)
          record = get_record(record_class, values)
          if record
            track_updated_columns(record_class, record) { yield record } if block_given?
          else
            record = create_record(record_class, values.merge(created_at: created_at))
            yield record if block_given?
          end
          @record_index[record_class].update(record)
          record
        end

        def get_record!(record_class, where_clause)
          record = get_record(record_class, where_clause)
          unless record
            fail("record #{record_class} not found for #{where_clause}, store: #{@record_store[record_class]}")
          end

          record
        end

        def get_record(record_class, where_clause)
          results = find_records(record_class, where_clause)
          results.empty? ? nil : results.first
        end

        def delete_all_records(record_class, where_clause)
          find_records(record_class, where_clause).each do |record|
            delete_record(record_class, record)
          end
        end

        def delete_record(record_class, record)
          @record_store[record_class].delete(record)
          @record_index[record_class].remove(record)
        end

        def update_all_records(record_class, where_clause, updates)
          find_records(record_class, where_clause).each do |record|
            updates.each_pair do |k, v|
              record[k] = v
              record.updated!(k.to_sym) if @computed_columns[record_class].include?(k.to_sym)
            end
            @record_index[record_class].update(record)
          end
        end

        def do_with_records(record_class, where_clause)
          records = find_records(record_class, where_clause)
          records.each do |record|
            track_updated_columns(record_class, record) { yield record }
            @record_index[record_class].update(record)
          end
        end

        def do_with_record(record_class, where_clause)
          record = get_record!(record_class, where_clause)
          track_updated_columns(record_class, record) { yield record }
          @record_index[record_class].update(record)
        end

        def find_records(record_class, where_clause)
          where_clause = where_clause.symbolize_keys

          indexed_columns = @record_index[record_class].indexed_columns
          indexed_fields, non_indexed_fields = where_clause.partition { |field, _| indexed_columns.include? field }

          candidate_records = if indexed_fields.present?
                                @record_index[record_class].find(indexed_fields)
                              else
                                @record_store[record_class]
                              end

          return candidate_records.to_a if non_indexed_fields.empty?

          candidate_records.select do |record|
            non_indexed_fields.all? do |k, v|
              expected_value = Persistors.normalize_symbols(v)
              actual_value = Persistors.normalize_symbols(record[k])
              if expected_value.is_a?(Array)
                expected_value.include?(actual_value)
              else
                actual_value == expected_value
              end
            end
          end
        end

        def last_record(record_class, where_clause)
          results = find_records(record_class, where_clause)
          results.empty? ? nil : results.last
        end

        def prepare
          # noop
        end

        def commit
          @record_store.each do |record_class, records|
            next if records.empty?

            copy_records(record_class, records)
          end
        ensure
          clear
        end

        def clear
          @record_store.clear
          @record_index.each_value(&:clear)
        end

        private

        # Sets the timestamps without a value to the current time, like ActiveRecord does when creating a record.
        def touch_timestamps(record_class, record)
          now = nil
          @timestamp_columns[record_class].each do |column|
            record[column] ||= (now ||= record_class.current_time_from_proper_timezone)
          end
        end

        # Marks the computed columns of the +record+ that the block changes as updated. Like ActiveRecord, a column set
        # to the value it already had (like nil to nil) is not changed.
        def track_updated_columns(record_class, record)
          computed_columns = @computed_columns[record_class]
          return yield if computed_columns.empty?

          before = computed_columns.map { |column| record[column] }
          yield
          computed_columns.each_with_index do |column, index|
            record.updated!(column) unless before[index].equal?(record[column])
          end
        end

        # A column of a COPY, with the encoder for its values. Values for which +native+ returns true, and nil when
        # the column has +native+, are encoded by the encoder as is, all other values are serialized by ActiveRecord
        # first. A +computed+ column has a default that the database computes.
        CopyColumn = Data.define(:name, :position, :type, :encoder, :native, :computed)

        def copy_records(record_class, records)
          columns = copy_columns(record_class)
          computed_columns = columns.select(&:computed)
          # Leaves out the computed columns without a value, so the database computes them, like ActiveRecord does when
          # creating a record. A computed column updated to nil is NULL, like when ActiveRecord updates a record.
          records
            .group_by do |record|
              computed_columns.select do |column|
                record[column.position].nil? && !record.updated?(column.name.to_sym)
              end
            end
            .each do |omitted_columns, same_columns_records|
              copy(record_class, columns - omitted_columns, same_columns_records)
            end
        end

        def copy(record_class, columns, records)
          record_class.with_connection do |conn|
            raw_connection = conn.raw_connection
            encoder = PG::TextEncoder::CopyRow.new(type_map: PG::TypeMapByColumn.new(columns.map(&:encoder)))
            quoted_column_names = columns.map { |column| conn.quote_column_name(column.name) }
            copy = "COPY #{record_class.quoted_table_name} (#{quoted_column_names.join(',')}) FROM STDIN"

            raw_connection.copy_data(copy, encoder) do
              records.each do |record|
                values = record.to_a
                raw_connection.put_copy_data(
                  columns.map do |column|
                    value = values[column.position]
                    if column.native && (value.nil? || column.native.call(value))
                      value
                    else
                      conn.type_cast(column.type.serialize(value))
                    end
                  end,
                )
              end
            end
          end
        end

        def copy_columns(record_class)
          record_class.column_names.each_with_index.map do |name, position|
            type = record_class.type_for_attribute(name)
            encoder, native = copy_encoder(type)
            computed = record_class.columns_hash[name].auto_populated?
            CopyColumn.new(name:, position:, type:, encoder:, native:, computed:)
          end
        end

        # Returns the encoder for the values of a column of +type+, and a lambda that returns whether a value can be
        # encoded as is. This is only the case for values that have the Ruby class the encoder expects, and that
        # ActiveRecord would not change. So for example floats are not encoded as is in a numeric column, since
        # ActiveRecord converts them using its own precision, decimals only when they do not have more decimals than
        # the column, since ActiveRecord rounds them using the rounding mode of BigDecimal, and times only when they
        # do not have more fractional digits than the column, since ActiveRecord truncates them while the database
        # rounds them. Values of all other types, like json and arrays, are always serialized by ActiveRecord, which
        # also ensures that types decorating these types (like enums) are serialized like ActiveRecord does.
        #
        # The values serialized by ActiveRecord are integers for integer columns, and strings for all other columns,
        # which the encoders send as is.
        def copy_encoder(type)
          oid = ActiveRecord::ConnectionAdapters::PostgreSQL::OID
          case type.class.name
          when ActiveModel::Type::Integer.name
            [PG::TextEncoder::Integer.new, ->(value) { value.is_a?(::Integer) }]
          when oid::Decimal.name
            scale = type.scale
            [
              PG::TextEncoder::Numeric.new,
              ->(value) {
                value.is_a?(::Integer) || (value.is_a?(::BigDecimal) && (scale.nil? || value.scale <= scale))
              },
            ]
          when oid::Date.name
            [PG::TextEncoder::Date.new, ->(value) { value.instance_of?(::Date) }]
          when oid::Timestamp.name
            return [PG::TextEncoder::String.new, nil] unless ActiveRecord.default_timezone == :utc

            truncated_digits = 10**(9 - (type.precision || 6))
            [
              PG::TextEncoder::TimestampUtc.new,
              ->(value) {
                value.instance_of?(::Time) && (value.nsec % truncated_digits).zero?
              },
            ]
          when ActiveModel::Type::Boolean.name
            [PG::TextEncoder::Boolean.new, ->(value) { [true, false].include?(value) }]
          when ActiveModel::Type::String.name
            [PG::TextEncoder::String.new, ->(value) { value.is_a?(::String) }]
          when oid::Uuid.name
            [
              PG::TextEncoder::String.new,
              ->(value) {
                value.is_a?(::String) && oid::Uuid::ACCEPTABLE_UUID.match?(value)
              },
            ]
          else
            [PG::TextEncoder::String.new, nil]
          end
        end
      end

      # Normalizes symbol values to strings (by using its name) while
      # preserving all other values. This allows symbol/string
      # indifferent comparisons.
      def self.normalize_symbols(value)
        value.is_a?(Symbol) ? value.name : value
      end
    end
  end
end
