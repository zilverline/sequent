# frozen_string_literal: true

require 'active_record'
require_relative 'record_structs'
require_relative 'statements'

module Sequent
  module Core
    module Persistors
      #
      # The methods of the +UnbufferedPersistor+ and the +BufferedPersistor+ that read records as structs using
      # +Statements::Select+, and write the changes a caller makes to them as an +Update+ by primary key, for the
      # changed columns only. Including classes implement +create_record+, +select_records+, which reads the records,
      # and +write_update+, which receives the +Statements::Update+ for a changed record.
      #
      module RecordReading
        def update_record(record_class, event, where_clause = {aggregate_id: event.aggregate_id}, options = {})
          record = get_record(record_class, where_clause)
          unless record
            fail(<<~EOS)
              Record of class #{record_class} with where clause #{where_clause} not found while handling event #{event}
            EOS
          end

          save(record_class, record) do
            record.updated_at = event.created_at if record.respond_to?(:updated_at=)
            yield record if block_given?
            update_sequence_number = options.fetch(:update_sequence_number) { record.respond_to?(:sequence_number=) }
            record.sequence_number = event.sequence_number if update_sequence_number
          end
        end

        def create_or_update_record(record_class, values, created_at = nil, &block)
          record = get_record(record_class, values)
          return save(record_class, record) { yield record } if record

          values = values.merge(created_at:) if created_at && record_class.column_names.include?('created_at')
          create_record(record_class, values, &block)
        end

        def get_record!(record_class, where_clause)
          record = get_record(record_class, where_clause)
          return record if record

          fail ActiveRecord::RecordNotFound.new("Couldn't find #{record_class} with #{where_clause}", record_class.name)
        end

        def get_record(record_class, where_clause)
          first_record(record_class, where_clause, :asc)
        end

        def last_record(record_class, where_clause)
          first_record(record_class, where_clause, :desc)
        end

        def find_records(record_class, where_clause)
          select_records(record_class, where_clause)
        end

        def do_with_records(record_class, where_clause)
          find_records(record_class, where_clause).each do |record|
            save(record_class, record) { yield record }
          end
        end

        def do_with_record(record_class, where_clause)
          record = get_record!(record_class, where_clause)
          save(record_class, record) { yield record }
        end

        private

        def first_record(record_class, where_clause, direction)
          select_records(record_class, where_clause, direction:, limit: 1).first
        end

        # Writes the columns of the +record+ that the block changes, like ActiveRecord saves a record.
        def save(record_class, record)
          before = record.to_h.deep_dup
          yield
          changes = changed_columns(record_class, before, record)
          return record if changes.empty?

          write_update(
            Statements::Update.new(
              record_class,
              primary_key_values(record_class, before),
              changes.to_h { |column| [column, record[column]] },
            ),
          )
          record
        end

        def changed_columns(record_class, before, record)
          # The columns are the keys, since a column named members would replace Struct#members.
          before.keys.reject do |column|
            record_class.type_for_attribute(column.to_s).cast(record[column]) == before[column]
          end
        end

        def primary_key_values(record_class, values)
          primary_key = record_class.primary_key or fail ActiveRecord::UnknownPrimaryKey, record_class
          Array(primary_key).to_h { |column| [column, values.fetch(column.to_sym)] }
        end
      end
    end
  end
end
