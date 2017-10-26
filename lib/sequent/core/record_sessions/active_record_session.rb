require 'active_record'

module Sequent
  module Core
    module RecordSessions
      #
      # Session objects are used to update view state
      #
      # The ActiveRecordSession object can be used when you use ActiveRecord as view state store.
      #
      class ActiveRecordSession

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

        def execute(statement)
          ActiveRecord::Base.connection.execute(statement)
        end

        def create_record(record_class, values)
          record = new_record(record_class, values)
          yield record if block_given?
          record.save!
          record
        end

        def create_records(record_class, array_of_value_hashes)
          table = Arel::Table.new(record_class.table_name)

          query = array_of_value_hashes.map do |values|
            insert_manager = Arel::InsertManager.new(ActiveRecord::Base)
            insert_manager.into(table)
            insert_manager.insert(values.map do |key, value|
              [table[key], value]
            end)
            insert_manager.to_sql
          end.join(";")

          execute(query)
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

        private

        def new_record(record_class, values)
          record_class.unscoped.new(values)
        end

      end

    end
  end
end
