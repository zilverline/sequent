# frozen_string_literal: true

require_relative 'sequent_oj'
require_relative 'helpers/pgsql_helpers'

module Sequent
  module Core
    module SnapshotStore
      include Helpers::PgsqlHelpers

      def store_snapshots(snapshots)
        json = Sequent::Core::Oj.dump(
          snapshots.map do |snapshot|
            {
              aggregate_id: snapshot.aggregate_id,
              snapshot_version: snapshot.snapshot_version,
              sequence_number: snapshot.sequence_number,
              created_at: snapshot.created_at,
              snapshot_type: snapshot.class.name,
              snapshot_json: snapshot,
            }
          end,
        )

        call_procedure(connection, 'store_snapshots', [json])
      end

      def load_latest_snapshot(aggregate_id)
        snapshot_hash = query_function(
          connection,
          'load_latest_snapshot',
          [aggregate_id, snapshot_version_by_type.to_json],
        ).first
        deserialize_event(snapshot_hash) unless snapshot_hash['aggregate_id'].nil?
      end

      # Deletes all snapshots for all aggregates
      def delete_all_snapshots
        call_procedure(connection, 'delete_all_snapshots', [Time.now])
      end

      def delete_lower_snapshot_versions
        connection.exec_update(<<~EOS, 'delete_lower_snapshot_versions', [snapshot_version_by_type.to_json])
          DELETE FROM aggregates_that_need_snapshots s
           WHERE snapshot_version < COALESCE(
                   (SELECT ($1::jsonb)->(type.type)
                      FROM aggregates
                      JOIN aggregate_types type ON aggregate_type_id = type.id
                     WHERE s.aggregate_id = aggregates.aggregate_id)::integer,
                   1
                 );
        EOS
      end

      def mark_aggregates_with_lower_snapshot_versions_for_snapshotting
        sql = <<~SQL
          INSERT INTO aggregates_that_need_snapshots (aggregate_id, snapshot_version, snapshot_sequence_number_high_water_mark, snapshot_outdated_at)
          SELECT source.aggregate_id,
                 ($1::jsonb->>(t.type))::integer,
                 MAX(snapshot_sequence_number_high_water_mark),
                 MIN(snapshot_outdated_at)
            FROM aggregates_that_need_snapshots source
            JOIN aggregates a ON source.aggregate_id = a.aggregate_id
            JOIN aggregate_types t ON a.aggregate_type_id = t.id
           WHERE source.snapshot_version < ($1::jsonb->>(t.type))::integer
           GROUP BY 1, 2
              ON CONFLICT DO NOTHING;
        SQL

        connection.exec_update(
          sql,
          'mark_aggregates_with_lower_snapshot_versions_for_snapshotting',
          [snapshot_version_by_type.to_json],
        )
      end

      # Deletes all snapshots for aggregate_id with a sequence_number lower than the specified sequence number.
      def delete_snapshots_before(aggregate_id, sequence_number)
        call_procedure(
          connection,
          'delete_snapshots_before',
          [aggregate_id, sequence_number, Time.now, snapshot_version_by_type.to_json],
        )
      end

      # Marks an aggregate for snapshotting. Marked aggregates will be
      # picked up by the background snapshotting task. Another way to
      # mark aggregates for snapshotting is to pass the
      # +EventStream#snapshot_outdated_at+ property to the
      # +#store_events+ method as is done automatically by the
      # +AggregateRepository+ based on the aggregate's
      # +snapshot_threshold+.
      def mark_aggregate_for_snapshotting(aggregate_id, snapshot_version:, snapshot_outdated_at: Time.now)
        sql = <<~EOS
          INSERT INTO aggregates_that_need_snapshots AS row (aggregate_id, snapshot_version, snapshot_outdated_at)
          VALUES ($1, $2, $3)
              ON CONFLICT (aggregate_id, snapshot_version) DO UPDATE
             SET snapshot_outdated_at = LEAST(row.snapshot_outdated_at, EXCLUDED.snapshot_outdated_at),
                 snapshot_scheduled_at = NULL
        EOS

        connection.exec_update(
          sql,
          'mark_aggregate_for_snapshotting',
          [aggregate_id, snapshot_version, snapshot_outdated_at],
        )
      end

      # Stops snapshotting the specified aggregate. Any existing
      # snapshots for this aggregate are also deleted.
      def clear_aggregate_for_snapshotting(aggregate_id)
        connection.exec_update(
          'DELETE FROM aggregates_that_need_snapshots WHERE aggregate_id = $1',
          'clear_aggregate_for_snapshotting',
          [aggregate_id],
        )
      end

      # Stops snapshotting all aggregates where the last event
      # occurred before the indicated timestamp. Any existing
      # snapshots for this aggregate are also deleted.
      def clear_aggregates_for_snapshotting_with_last_event_before(timestamp)
        connection.exec_update(<<~EOS, 'clear_aggregates_for_snapshotting_with_last_event_before', [timestamp])
          DELETE FROM aggregates_that_need_snapshots s
           WHERE NOT EXISTS (SELECT *
                               FROM aggregates a
                               JOIN events e ON (a.aggregate_id, a.events_partition_key) = (e.aggregate_id, e.partition_key)
                              WHERE a.aggregate_id = s.aggregate_id AND e.created_at >= $1)
        EOS
      end

      ##
      # Returns the ids of aggregates that need a new snapshot.
      #
      def aggregates_that_need_snapshots(last_aggregate_id, limit = 10)
        query_function(
          connection,
          'aggregates_that_need_snapshots',
          [last_aggregate_id, limit, snapshot_version_by_type.to_json],
          columns: ['aggregate_id'],
        )
          .pluck('aggregate_id')
      end

      def select_aggregates_for_snapshotting(limit:, reschedule_snapshots_scheduled_before: nil)
        query_function(
          connection,
          'select_aggregates_for_snapshotting',
          [limit, reschedule_snapshots_scheduled_before, Time.now, snapshot_version_by_type.to_json],
          columns: ['aggregate_id'],
        ).pluck('aggregate_id')
      end

      private

      def snapshot_version_by_type(clazz = AggregateRoot)
        fail 'subclass responsibility'
      end
    end
  end
end
