require 'active_record'
require_relative './persistor'

module Sequent
  module Core
    module Persistors

      #
      # The ActiveRecordPersistor uses ActiveRecord to update the projection
      #
      # This is the default persistor in Sequent, but when your event store
      # is growing it is not the best choice as persistor while rebuilding
      # a projection when migrating to a new version of that projection.
      #
      # Please see the +ReplayOptimizedPostgresPersistor+ as alternative
      # for migrating projections to a new version.
      class ActiveRecordPersistor
        include Persistor

        def update_record(record_class, event, where_clause = {aggregate_id: event.aggregate_id}, options = {}, &block)
          record = record_class.unscoped.where(where_clause).first
          raise("Record of class #{record_class} with where clause #{where_clause} not found while handling event #{event}") unless record
          record.updated_at = event.created_at if record.respond_to?(:updated_at)
          yield record if block_given?
          update_sequence_number = options.key?(:update_sequence_number) ?
                                     options[:update_sequence_number] :
                                     record.respond_to?(:sequence_number=)
          record.sequence_number = event.sequence_number if update_sequence_number
          record.save!
        end

        def create_record(record_class, values)
          record = new_record(record_class, values)
          yield record if block_given?
          record.save!
          record
        end

        def create_records(record_class, array_of_value_hashes)
          table = record_class.arel_table

          query = array_of_value_hashes.map do |values|
            insert_manager = new_insert_manager
            insert_manager.into(table)
            insert_manager.insert(values.map do |key, value|
              convert_to_values(key, table, value)
            end)
            insert_manager.to_sql
          end.join(";")

          execute_sql(query)
        end

        def create_or_update_record(record_class, values, created_at = Time.now)
          record = get_record(record_class, values)
          unless record
            record = new_record(record_class, values)
            record.created_at = created_at if record.respond_to?(:created_at)
          end
          yield record
          record.save!
          record
        end

        def get_record!(record_class, where_clause)
          record_class.unscoped.where(where_clause).first!
        end

        def get_record(record_class, where_clause)
          record_class.unscoped.where(where_clause).first
        end

        def delete_all_records(record_class, where_clause)
          record_class.unscoped.where(where_clause).delete_all
        end

        def delete_record(_, record)
          record.destroy
        end

        def update_all_records(record_class, where_clause, updates)
          record_class.unscoped.where(where_clause).update_all(updates)
        end

        def do_with_records(record_class, where_clause)
          record_class.unscoped.where(where_clause).each do |record|
            yield record
            record.save!
          end
        end

        def do_with_record(record_class, where_clause)
          record = record_class.unscoped.where(where_clause).first!
          yield record
          record.save!
        end

        def find_records(record_class, where_clause)
          record_class.unscoped.where(where_clause)
        end

        def last_record(record_class, where_clause)
          record_class.unscoped.where(where_clause).last
        end

        def execute_sql(statement)
          Sequent::ApplicationRecord.connection.execute(statement)
        end

        def commit
          # noop
        end

        private

        def new_record(record_class, values)
          record_class.unscoped.new(values)
        end

        def new_insert_manager
          Arel::InsertManager.new
        end

        def convert_to_values(key, table, value)
          [table[key], table.type_cast_for_database(key, value)]
        end
      end
    end
  end
end
