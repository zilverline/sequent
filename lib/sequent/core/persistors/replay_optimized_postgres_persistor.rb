# frozen_string_literal: true

require 'active_record'
require 'csv'
require_relative 'persistor'

module Sequent
  module Core
    module Persistors
      #
      # The ReplayOptimizedPostgresPersistor is optimized for bulk loading records in a Postgres database.
      #
      # Depending on the amount of records it uses CSV import, otherwise statements are batched
      # using normal sql.
      #
      # Rebuilding the view state (or projection) of an aggregate typically consists
      # of an initial insert and then many updates and maybe a delete.
      # With a normal Persistor (like ActiveRecordPersistor) each action is executed to the database.
      # This persistor creates an in-memory store first and finally flushes
      # the in-memory store to the database. This can significantly reduce the amount of queries to the database.
      # E.g. 1 insert, 6 updates is only a single insert using this Persistor.
      #
      # After lot of experimenting this turned out to be the fastest way to to bulk inserts in the database.
      # You can tweak the amount of records in the CSV via +insert_with_csv_size+ before
      # it flushes to the database to gain (or loose) speed.
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
        CHUNK_SIZE = 1024

        attr_reader :record_store
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
        end

        def struct_cache
          @struct_cache ||= Hash.new do |hash, record_class|
            struct_class = Struct.new(*record_class.column_names.map(&:to_sym), keyword_init: true) do
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
            @indexes.map do |field, index|
              key = Persistors.normalize_symbols(record[field]).freeze
              records = index[key] || (index[key] = Set.new.compare_by_identity)
              records << record
              @reverse_indexes[field][record] = key
            end
          end

          def remove(record)
            @indexes.map do |field, index|
              key = @reverse_indexes[field].delete(record)
              remaining = index[key]&.delete(record)
              index.delete(key) if remaining&.empty?
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

        # +insert_with_csv_size+ number of records to insert in a single batch
        #
        # +indices+ Hash of indices to create in memory. Greatly speeds up the replaying.
        #   Key corresponds to the name of the 'Record'
        #   Values contains list of lists on which columns to index.
        #   E.g. [[:first_index_column], [:another_index, :with_to_columns]]
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
        end

        def update_record(record_class, event, where_clause = {aggregate_id: event.aggregate_id}, options = {})
          record = get_record!(record_class, where_clause)
          record.updated_at = event.created_at if record.respond_to?(:updated_at=)
          yield record if block_given?
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
          record.updated_at = values[:created_at] if record.respond_to?(:updated_at)

          yield record if block_given?

          @record_store[record_class] << record
          @record_index[record_class].add(record)

          record
        end

        def create_records(record_class, array_of_value_hashes)
          array_of_value_hashes.each { |values| create_record(record_class, values) }
        end

        def create_or_update_record(record_class, values, created_at = Time.now)
          record = get_record(record_class, values)
          record ||= create_record(record_class, values.merge(created_at: created_at))
          yield record if block_given?
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
            end
            @record_index[record_class].update(record)
          end
        end

        def do_with_records(record_class, where_clause)
          records = find_records(record_class, where_clause)
          records.each do |record|
            yield record
            @record_index[record_class].update(record)
          end
        end

        def do_with_record(record_class, where_clause)
          record = get_record!(record_class, where_clause)
          yield record
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
          @record_store.each do |clazz, records|
            @column_cache ||= {}
            @column_cache[clazz.name] ||= clazz.columns.reduce({}) do |hash, column|
              hash.merge({column.name => column})
            end
            if records.size > @insert_with_csv_size
              csv = CSV.new(StringIO.new)
              column_names = clazz.column_names.reject { |name| name == 'id' }
              records.each do |record|
                csv << column_names.map do |column_name|
                  cast_value_to_column_type(clazz, column_name, record)
                end
              end

              conn = Sequent::ApplicationRecord.connection.raw_connection
              copy_data = StringIO.new(csv.string)
              conn.transaction do
                conn.copy_data("COPY #{clazz.table_name} (#{column_names.join(',')}) FROM STDIN WITH csv") do
                  while (out = copy_data.read(CHUNK_SIZE))
                    conn.put_copy_data(out)
                  end
                end
              end
            else
              clazz.unscoped do
                inserts = []
                column_names = clazz.column_names.reject { |name| name == 'id' }
                prepared_values = (1..column_names.size).map { |i| "$#{i}" }.join(',')
                records.each do |record|
                  values = column_names.map do |column_name|
                    cast_value_to_column_type(clazz, column_name, record)
                  end
                  inserts << values
                end
                sql = %{insert into #{clazz.table_name} (#{column_names.join(',')}) values (#{prepared_values})}
                inserts.each do |insert|
                  clazz.connection.raw_connection.async_exec(sql, insert)
                end
              end
            end
          end
        ensure
          clear
        end

        def clear
          @record_store.clear
          @record_index.each_value(&:clear)
        end

        private

        def cast_value_to_column_type(clazz, column_name, record)
          uncasted_value = ActiveModel::Attribute.from_database(
            column_name,
            record[column_name],
            Sequent::ApplicationRecord.connection.lookup_cast_type_from_column(@column_cache[clazz.name][column_name]),
          ).value_for_database
          Sequent::ApplicationRecord.connection.type_cast(uncasted_value)
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
