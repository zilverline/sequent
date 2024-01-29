# frozen_string_literal: true

require 'set'
require 'active_record'
require 'csv'
require_relative './persistor'

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
          def set_values(values)
            values.each do |k, v|
              self[k] = v
            end
            self
          end
        end

        def struct_cache
          @struct_cache ||= Hash.new do |hash, record_class|
            struct_class = Struct.new(*record_class.column_names.map(&:to_sym))
            struct_class.include InMemoryStruct
            hash[record_class] = struct_class
          end
        end

        class Index
          def initialize(indexed_columns)
            @indexed_columns = Hash.new do |hash, record_class|
              hash[record_class] = default_indexes(record_class)
            end

            indexed_columns.each do |record_class, indexes|
              fields = indexes.flatten(1).map(&:to_sym).to_set
              @indexed_columns[record_class] = (fields + default_indexes(record_class))
            end

            @index = {}
            @reverse_index = {}.compare_by_identity
          end

          def add(record_class, record)
            return unless indexed?(record_class)

            keys = get_keys(record_class, record)
            keys.each do |key|
              @index[key] = Set.new.compare_by_identity unless @index.key? key
              @index[key] << record
            end

            @reverse_index[record] = keys
          end

          def remove(record_class, record)
            return unless indexed?(record_class)

            keys = @reverse_index.delete(record) { [] }

            return if keys.empty?

            keys.each do |key|
              @index[key].delete(record)
              @index.delete(key) if @index[key].empty?
            end
          end

          def update(record_class, record)
            remove(record_class, record)
            add(record_class, record)
          end

          def find(record_class, normalized_where_clause)
            indexes = get_indexes(record_class, normalized_where_clause)
            return nil unless indexes.present?

            record_sets = indexes.flat_map do |field|
              if !normalized_where_clause.include? field
                []
              else
                values = [normalized_where_clause[field]].flatten(1)
                values
                  .map { |value| @index[[record_class.name, field, Persistors.normalize_symbols(value)]] || Set.new }
                  .reduce(Set.new, &:union)
              end
            end
            record_sets.sort_by(&:size).reduce(&:intersection)
          end

          def clear
            @index.clear
            @reverse_index.clear
          end

          def use_index?(record_class, normalized_where_clause)
            indexed?(record_class) && get_indexes(record_class, normalized_where_clause).present?
          end

          private

          def indexed?(record_class)
            # Do not use `key?` here or similar, since the
            # `@indexed_columns#default_proc` automatically adds new
            # indexes as required.
            @indexed_columns[record_class].present?
          end

          def get_keys(record_class, record)
            @indexed_columns[record_class].map do |field|
              [record_class.name, field, Persistors.normalize_symbols(record[field])]
            end
          end

          def get_indexes(record_class, normalized_where_clause)
            @indexed_columns[record_class] & normalized_where_clause.keys
          end

          def default_indexes(record_class)
            Set[:aggregate_id] & record_class.column_names.map(&:to_sym).to_set
          end
        end

        # +insert_with_csv_size+ number of records to insert in a single batch
        #
        # +indices+ Hash of indices to create in memory. Greatly speeds up the replaying.
        #   Key corresponds to the name of the 'Record'
        #   Values contains list of lists on which columns to index.
        #   E.g. [[:first_index_column], [:another_index, :with_to_columns]]
        def initialize(insert_with_csv_size = 50, indices = {})
          @insert_with_csv_size = insert_with_csv_size
          @record_store = Hash.new { |h, k| h[k] = Set.new.compare_by_identity }
          @record_index = Index.new(indices)
        end

        def update_record(record_class, event, where_clause = {aggregate_id: event.aggregate_id}, options = {})
          record = get_record!(record_class, where_clause)
          record.updated_at = event.created_at if record.respond_to?(:updated_at)
          yield record if block_given?
          @record_index.update(record_class, record)
          update_sequence_number = if options.key?(:update_sequence_number)
                                     options[:update_sequence_number]
                                   else
                                     record.respond_to?(:sequence_number=)
                                   end
          record.sequence_number = event.sequence_number if update_sequence_number
        end

        def create_record(record_class, values)
          column_names = record_class.column_names
          values = record_class.column_defaults.with_indifferent_access.merge(values)
          values.merge!(updated_at: values[:created_at]) if column_names.include?('updated_at')
          record = struct_cache[record_class].new.set_values(values)

          yield record if block_given?

          @record_store[record_class] << record
          @record_index.add(record_class, record)

          record
        end

        def create_records(record_class, array_of_value_hashes)
          array_of_value_hashes.each { |values| create_record(record_class, values) }
        end

        def create_or_update_record(record_class, values, created_at = Time.now)
          record = get_record(record_class, values)
          record ||= create_record(record_class, values.merge(created_at: created_at))
          yield record if block_given?
          @record_index.update(record_class, record)
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
          @record_index.remove(record_class, record)
        end

        def update_all_records(record_class, where_clause, updates)
          find_records(record_class, where_clause).each do |record|
            updates.each_pair do |k, v|
              record[k] = v
            end
            @record_index.update(record_class, record)
          end
        end

        def do_with_records(record_class, where_clause)
          records = find_records(record_class, where_clause)
          records.each do |record|
            yield record
            @record_index.update(record_class, record)
          end
        end

        def do_with_record(record_class, where_clause)
          record = get_record!(record_class, where_clause)
          yield record
          @record_index.update(record_class, record)
        end

        def find_records(record_class, where_clause)
          normalized_where_clause = where_clause.symbolize_keys
          candidate_records = @record_index.find(record_class, normalized_where_clause) || @record_store[record_class]
          candidate_records.select do |record|
            normalized_where_clause.all? do |k, v|
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
          @record_index.clear
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
