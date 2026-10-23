# frozen_string_literal: true

require 'active_record'
require 'csv'
require_relative 'persistor'
require_relative 'record_store'

module Sequent
  module Core
    module Persistors
      #
      # The ReplayOptimizedPostgresPersistor is optimized for bulk loading records in a Postgres database.
      #
      # The records are loaded into the database using a single COPY statement per table.
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

        CHUNK_SIZE = 1024

        # @deprecated use RecordStore::InMemoryStruct
        InMemoryStruct = RecordStore::InMemoryStruct
        # @deprecated use RecordStore::Index
        Index = RecordStore::Index

        # @deprecated records are always loaded using COPY
        attr_accessor :insert_with_csv_size

        # +insert_with_csv_size+ is ignored, records are always loaded using COPY
        #
        # +indices+ Hash of indices to create in memory. Greatly speeds up the replaying.
        #   Key corresponds to the name of the 'Record'
        #   Values contains list of lists on which columns to index.
        #   E.g. [[:first_index_column], [:another_index, :with_two_columns]]
        def initialize(insert_with_csv_size = 50, indices = {}, default_indexed_columns = [:aggregate_id])
          @insert_with_csv_size = insert_with_csv_size
          @store = RecordStore.new(indices, default_indexed_columns)
        end

        ##
        # The records that are not committed yet, as a hash from record class to the set of records of that class.
        def record_store
          @store.records_by_class
        end

        def update_record(record_class, event, where_clause = {aggregate_id: event.aggregate_id}, options = {})
          record = get_record!(record_class, where_clause)
          record.updated_at = event.created_at if record.respond_to?(:updated_at=)
          yield record if block_given?
          @store.reindex(record_class, record)
          update_sequence_number = if options.key?(:update_sequence_number)
                                     options[:update_sequence_number]
                                   else
                                     record.respond_to?(:sequence_number=)
                                   end
          record.sequence_number = event.sequence_number if update_sequence_number
        end

        def create_record(record_class, values)
          record = @store.build(record_class, values)
          record.updated_at = values[:created_at] if record.respond_to?(:updated_at)

          yield record if block_given?

          @store.add(record_class, record)
        end

        def create_records(record_class, array_of_value_hashes)
          array_of_value_hashes.each { |values| create_record(record_class, values) }
        end

        def create_or_update_record(record_class, values, created_at = Time.now)
          record = get_record(record_class, values)
          record ||= create_record(record_class, values.merge(created_at: created_at))
          yield record if block_given?
          @store.reindex(record_class, record)
          record
        end

        def get_record!(record_class, where_clause)
          record = get_record(record_class, where_clause)
          unless record
            fail("record #{record_class} not found for #{where_clause}, store: #{record_store[record_class]}")
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
          @store.remove(record_class, record)
        end

        def update_all_records(record_class, where_clause, updates)
          find_records(record_class, where_clause).each do |record|
            updates.each_pair do |k, v|
              record[k] = v
            end
            @store.reindex(record_class, record)
          end
        end

        def do_with_records(record_class, where_clause)
          records = find_records(record_class, where_clause)
          records.each do |record|
            yield record
            @store.reindex(record_class, record)
          end
        end

        def do_with_record(record_class, where_clause)
          record = get_record!(record_class, where_clause)
          yield record
          @store.reindex(record_class, record)
        end

        def find_records(record_class, where_clause)
          @store.find(record_class, where_clause)
        end

        def last_record(record_class, where_clause)
          results = find_records(record_class, where_clause)
          results.empty? ? nil : results.last
        end

        def prepare
          # noop
        end

        def commit
          @store.each do |record_class, records|
            next if records.empty?

            copy_records(record_class, records)
          end
        ensure
          clear
        end

        def clear
          @store.clear
        end

        private

        def copy_records(record_class, records)
          column_names = record_class.column_names.reject { |name| name == 'id' }
          column_types = column_names.index_with { |column_name| record_class.type_for_attribute(column_name) }
          record_class.with_connection do |conn|
            csv = CSV.new(StringIO.new)
            records.each do |record|
              csv << column_types.map do |column_name, type|
                conn.type_cast(type.serialize(record[column_name]))
              end
            end

            copy_data = StringIO.new(csv.string)
            conn
              .raw_connection
              .copy_data("COPY #{record_class.table_name} (#{column_names.join(',')}) FROM STDIN WITH csv") do
                while (out = copy_data.read(CHUNK_SIZE))
                  conn.raw_connection.put_copy_data(out)
                end
              end
          end
        end
      end
    end
  end
end
