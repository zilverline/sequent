module Sequent
  module Core
    class Snapshots
      def initialize
      end

      def aggregates_that_need_snapshots(events_since_last_snapshot: 20, limit: 10, last_aggregate_id: nil)
        query = %Q{
SELECT aggregate_id
  FROM event_records events
 WHERE aggregate_id > '#{last_aggregate_id}'
 GROUP BY aggregate_id
HAVING MAX(sequence_number) - (COALESCE((SELECT MAX(sequence_number)
                                           FROM event_records snapshots
                                          WHERE event_type = 'Sequent::Core::SnapshotEvent'
                                            AND snapshots.aggregate_id = events.aggregate_id), 0)) > #{events_since_last_snapshot}
 ORDER BY aggregate_id
 LIMIT #{limit};
}
        @record_class.connection.select_all(query).to_a
      end
    end
  end
end
