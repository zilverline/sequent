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
      # of an initial insert and then many updates and maybe a delete. With a normal Persistor (like ActiveRecordPersistor)
      # each action is executed to the database. This persitor creates an inmemory store first and finally flushes
      # the in memory store to the database. This can significantly reduces the amount of queries to the database.
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
      #       update_all_records InvoiceRecord, recipient_id: event.recipient.aggregate_id do |record|
      #         record.recipient_street = record.recipient.street
      #       end
      #     end
      #   end
      #
      # In this case it is wise to create an index on InvoiceRecord on the recipient_id like you would in the database.
      #
      # Example:
      #
      #   ReplayOptimizedPostgresPersistor.new(
      #     50,
      #     {InvoiceRecord => [[:recipient_id]]}
      #   )
      class ReplayOptimizedPostgresPersistor
        include Persistor

        attr_reader :record_store
        attr_accessor :insert_with_csv_size

        def self.struct_cache
          @struct_cache ||= {}
        end

        module InitStruct
          def set_values(values)
            values.each do |k, v|
              self[k] = v
            end
            self
          end
        end

        class Index
          def initialize(indexed_columns)
            @indexed_columns = Hash.new do |hash, record_class|
              if record_class.column_names.include? 'aggregate_id'
                hash[record_class] = [:aggregate_id]
              else
                hash[record_class] = []
              end
            end

            @indexed_columns.merge!(indexed_columns)

            @index = {}
            @reverse_index = {}
          end

          def add(record_class, record)
            return unless indexed?(record_class)

            get_keys(record_class, record).each do |key|
              @index[key.hash] = [] unless @index.has_key? key.hash
              @index[key.hash] << record

              @reverse_index[record.object_id.hash] = [] unless @reverse_index.has_key? record.object_id.hash
              @reverse_index[record.object_id.hash] << key.hash
            end
          end

          def remove(record_class, record)
            return unless indexed?(record_class)

            keys = @reverse_index.delete(record.object_id.hash) { [] }

            return unless keys.any?

            keys.each do |key|
              @index[key].delete(record)
              @index.delete(key) if @index[key].count == 0
            end
          end

          def update(record_class, record)
            remove(record_class, record)
            add(record_class, record)
          end

          def find(record_class, where_clause)
            key = [record_class.name]
            get_index(record_class, where_clause).each do |field|
              key << field
              key << where_clause[field]
            end
            @index[key.hash] || []
          end

          def clear
            @index = {}
            @reverse_index = {}
          end

          def use_index?(record_class, where_clause)
            @indexed_columns.has_key?(record_class) && @indexed_columns[record_class].any? { |indexed_where| where_clause.keys.size == indexed_where.size && (where_clause.keys - indexed_where).empty? }
          end

          private

          def indexed?(record_class)
            @indexed_columns.has_key?(record_class)
          end

          def get_keys(record_class, record)
            @indexed_columns[record_class].map do |index|
              arr = [record_class.name]
              index.each do |key|
                arr << key
                arr << record[key]
              end
              arr
            end
          end

          def get_index(record_class, where_clause)
            @indexed_columns[record_class].find { |indexed_where| where_clause.keys.size == indexed_where.size && (where_clause.keys - indexed_where).empty? }
          end
        end

        # +insert_with_csv_size+ number of records to insert in a single batch
        #
        # +indices+ Hash of indices to create in memory. Greatly speeds up the replaying.
        #   Key corresponds to the name of the 'Record'
        #   Values contains list of lists on which columns to index. E.g. [[:first_index_column], [:another_index, :with_to_columns]]
        def initialize(insert_with_csv_size = 50, indices = {})
          @insert_with_csv_size = insert_with_csv_size
          @record_store = Hash.new { |h, k| h[k] = Set.new }
          @record_index = Index.new(indices)
        end

        def update_record(record_class, event, where_clause = {aggregate_id: event.aggregate_id}, options = {}, &block)
          record = get_record!(record_class, where_clause)
          record.updated_at = event.created_at if record.respond_to?(:updated_at)
          yield record if block_given?
          @record_index.update(record_class, record)
          update_sequence_number = options.key?(:update_sequence_number) ?
                                     options[:update_sequence_number] :
                                     record.respond_to?(:sequence_number=)
          record.sequence_number = event.sequence_number if update_sequence_number
        end

        def create_record(record_class, values)
          column_names = record_class.column_names
          values = record_class.column_defaults.with_indifferent_access.merge(values)
          values.merge!(updated_at: values[:created_at]) if column_names.include?("updated_at")
          struct_class_name = "#{record_class.to_s}Struct"
          if self.class.struct_cache.has_key?(struct_class_name)
            struct_class = self.class.struct_cache[struct_class_name]
          else
            # We create a struct on the fly.
            # Since the replay happens in memory we implement the ==, eql? and hash methods
            # to point to the same object. A record is the same if and only if they point to
            # the same object. These methods are necessary since we use Set instead of [].
            class_def=<<-EOD
      #{struct_class_name} = Struct.new(*#{column_names.map(&:to_sym)})
              class #{struct_class_name}
                include InitStruct
                def ==(other)
                  self.equal?(other)
                end
                def hash
                  self.object_id.hash
                end
              end
            EOD
            eval("#{class_def}")
            struct_class = ReplayOptimizedPostgresPersistor.const_get(struct_class_name)
            self.class.struct_cache[struct_class_name] = struct_class
          end
          record = struct_class.new.set_values(values)

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
          unless record
            record = create_record(record_class, values.merge(created_at: created_at))
          end
          yield record if block_given?
          @record_index.update(record_class, record)
          record
        end

        def get_record!(record_class, where_clause)
          record = get_record(record_class, where_clause)
          raise("record #{record_class} not found for #{where_clause}, store: #{@record_store[record_class]}") unless record
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
              record[k.to_sym] = v
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
          if @record_index.use_index?(record_class, where_clause)
            @record_index.find(record_class, where_clause)
          else
            @record_store[record_class].select do |record|
              where_clause.all? do |k, v|
                expected_value = v.kind_of?(Symbol) ? v.to_s : v
                actual_value = record[k.to_sym]
                actual_value = actual_value.to_s if actual_value.kind_of? Symbol
                if expected_value.kind_of?(Array)
                  expected_value.include?(actual_value)
                else
                  actual_value == expected_value
                end
              end
            end
          end.dup
        end

        def last_record(record_class, where_clause)
          results = find_records(record_class, where_clause)
          results.empty? ? nil : results.last
        end

        def commit
          @record_store.each do |clazz, records|
            @column_cache ||= {}
            @column_cache[clazz.name] ||= clazz.columns.reduce({}) do |hash, column|
              hash.merge({ column.name => column })
            end
            if records.size > @insert_with_csv_size
              csv = CSV.new("")
              column_names = clazz.column_names.reject { |name| name == "id" }
              records.each do |record|
                csv << column_names.map do |column_name|
                  cast_value_to_column_type(clazz, column_name, record)
                end
              end

              buf = ''
              conn = Sequent::ApplicationRecord.connection.raw_connection
              copy_data = StringIO.new csv.string
              conn.transaction do
                conn.copy_data("COPY #{clazz.table_name} (#{column_names.join(",")}) FROM STDIN WITH csv") do
                  while copy_data.read(1024, buf)
                    conn.put_copy_data(buf)
                  end
                end
              end
            else
              clazz.unscoped do
                inserts = []
                column_names = clazz.column_names.reject { |name| name == "id" }
                prepared_values = (1..column_names.size).map { |i| "$#{i}" }.join(",")
                records.each do |record|
                  values = column_names.map do |column_name|
                    cast_value_to_column_type(clazz, column_name, record)
                  end
                  inserts << values
                end
                sql = %Q{insert into #{clazz.table_name} (#{column_names.join(",")}) values (#{prepared_values})}
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
          Sequent::ApplicationRecord.connection.type_cast(record[column_name.to_sym], @column_cache[clazz.name][column_name])
        end
      end
    end
  end
end
