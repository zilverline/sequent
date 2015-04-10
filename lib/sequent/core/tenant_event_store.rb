##
# Multi-tenant event store that replays events grouped by a specific tenant.
#
module Sequent
  module Core
    class TenantEventStore < EventStore

      def replay_events_for(organization_id)
        replay_events do
          @record_class.connection.select_all(%Q{
SELECT event_type, event_json
  FROM #{@record_class.table_name}
 WHERE organization_id = '#{organization_id}'
   AND event_type <> '#{SnapshotEvent.name}'
 ORDER BY id
})
        end
      end

    end

  end
end
