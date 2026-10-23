# frozen_string_literal: true

require 'active_record'

module Sequent
  module Core
    module Persistors
      #
      # In-memory store of records, for persistors that collect records in memory before writing them to the database
      # in bulk.
      #
      # Records are represented by structs (one struct class per record class) instead of ActiveRecord models, which
      # makes them cheap to create and update. Records are found by a where clause, using single-column indexes to
      # speed up the lookup. By default all records are indexed by +aggregate_id+ if they have such a column.
      #
      class RecordStore
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

        # The records in this store, as a hash from record class to the set of records of that class.
        attr_reader :records_by_class

        # +indices+ Hash of indices to create in memory. Greatly speeds up finding records.
        #   Key corresponds to the name of the 'Record'
        #   Values contains list of lists on which columns to index.
        #   E.g. [[:first_index_column], [:another_index, :with_two_columns]]
        def initialize(indices = {}, default_indexed_columns = [:aggregate_id])
          @records_by_class = Hash.new { |h, k| h[k] = Set.new.compare_by_identity }
          @indexes = Hash.new do |h, k|
            h[k] = Index.new(default_indexed_columns.to_set & k.column_names.map(&:to_sym))
          end

          indices.each do |record_class, indexed_columns|
            columns = indexed_columns.flatten(1).to_set(&:to_sym) + default_indexed_columns
            @indexes[record_class] = Index.new(columns & record_class.column_names.map(&:to_sym))
          end

          @record_defaults = Hash.new do |h, record_class|
            h[record_class] = record_class.column_defaults.symbolize_keys
          end

          @struct_classes = Hash.new do |h, record_class|
            h[record_class] = Struct.new(*record_class.column_names.map(&:to_sym)) do
              include InMemoryStruct
            end
          end
        end

        ##
        # Builds a new record with the given +values+ and the column defaults for all other columns. The record is
        # not added to the store, use +add+ for that.
        def build(record_class, values)
          record = @struct_classes[record_class].new(**values)
          @record_defaults[record_class].each do |column, default|
            record[column] = default unless values.include? column
          end
          record
        end

        def add(record_class, record)
          @records_by_class[record_class] << record
          @indexes[record_class].add(record)
          record
        end

        def remove(record_class, record)
          @records_by_class[record_class].delete(record)
          @indexes[record_class].remove(record)
        end

        ##
        # Updates the indexes of a +record+ after it was changed.
        def reindex(record_class, record)
          @indexes[record_class].update(record)
        end

        def find(record_class, where_clause)
          where_clause = where_clause.symbolize_keys

          indexed_columns = @indexes[record_class].indexed_columns
          indexed_fields, non_indexed_fields = where_clause.partition { |field, _| indexed_columns.include? field }

          candidate_records = if indexed_fields.present?
                                @indexes[record_class].find(indexed_fields)
                              else
                                @records_by_class[record_class]
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

        ##
        # Yields each record class with its set of records.
        def each(&block)
          @records_by_class.each(&block)
        end

        ##
        # The total number of records in the store.
        def size
          @records_by_class.each_value.sum(&:size)
        end

        def clear
          @records_by_class.clear
          @indexes.each_value(&:clear)
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
