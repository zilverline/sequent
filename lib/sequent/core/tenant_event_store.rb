##
# Multi-tenant event store that replays events grouped by a specific tenant.
#
module Sequent
  module Core
    class TenantEventStore < EventStore

      def replay_events_for(organization_id)
        replay_events do
          @event_record_class.connection.select_all(%Q{
SELECT events.event_type, events.event_json
  FROM #{quote_table_name @event_record_class.table_name} aggregates
       JOIN #{quote_table_name @event_record_class.table_name} events ON aggregates.aggregate_id = events.aggregate_id
 WHERE aggregates.organization_id = #{quote organization_id}
   AND aggregates.sequence_number = 1
   AND aggregates.event_type <> #{quote @snapshot_event_class.name}
   AND events.event_type <> #{quote @snapshot_event_class.name}
 ORDER BY events.id
})
        end
      end

    end

  end
end
