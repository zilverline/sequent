# frozen_string_literal: true

module Sequent
  module Core
    module Persistors
      class MissingCreatedAtError < ArgumentError; end

      ##
      # Fails when a record of +record_class+, which has a +created_at+ column, is created without a +created_at+.
      # The persistors would otherwise use the current time, so the record would get another +created_at+ (and
      # +updated_at+) when the events are replayed. Use the +created_at+ of the event instead.
      def self.ensure_created_at!(record_class, created_at)
        return unless record_class.column_names.include?('created_at')
        # A value that casts to nil, like an empty string, is no created_at either.
        return unless record_class.type_for_attribute('created_at').cast(created_at).nil?

        fail MissingCreatedAtError,
             "#{record_class} is created without a created_at, use the created_at of the event so it is the same " \
             'after a replay'
      end

      # Defines the methods that can be implemented by the specific +Persistors+
      #
      # See
      # - +ActiveRecordPersistor+
      # - +ReplayOptimizedPostgresPersistor+
      module Persistor
        # Updates the view state
        def update_record
          fail 'Method not supported in this persistor'
        end

        # Create a single record in the view state
        def create_record
          fail 'Method not supported in this persistor'
        end

        # Creates multiple records at once in the view state
        def create_records
          fail 'Method not supported in this persistor'
        end

        # Creates or updates a record in the view state.
        def create_or_update_record
          fail 'Method not supported in this persistor'
        end
        # Gets a record from the view state, fails if it not exists
        def get_record!
          fail 'Method not supported in this persistor'
        end

        # Gets a record from the view state, returns +nil+ if it not exists
        def get_record
          fail 'Method not supported in this persistor'
        end

        # Deletes all records given a where
        def delete_all_records
          fail 'Method not supported in this persistor'
        end

        # Updates all record given a where and an update clause
        def update_all_records
          fail 'Method not supported in this persistor'
        end

        # Decide for yourself what to do with the records
        # @deprecated
        def do_with_records
          fail 'Method not supported in this persistor'
        end

        # Decide for yourself what to do with a single record
        # @deprecated
        def do_with_record
          fail 'Method not supported in this persistor'
        end

        # Delete a single record
        # @deprecated
        def delete_record
          fail 'Method not supported in this persistor'
        end

        # Find records given a where
        def find_records
          fail 'Method not supported in this persistor'
        end

        # Returns the last record given a where
        def last_record
          fail 'Method not supported in this persistor'
        end

        # Hook to implement for instance the persistor batches statements
        def prepare
          fail 'Method not supported in this persistor'
        end

        # Hook to write the changes that the persistor batches, for instance after handling a batch of
        # events or replaying events.
        def flush
          fail 'Method not supported in this persistor'
        end

        # @deprecated Use +flush+ instead.
        def commit
          flush
        end
      end
    end
  end
end
