##
# Multi-tenant event store that replays events grouped by a specific tenant.
#
module Sequent
  module Core
    class TenantEventStore < EventStore

      ## TODO remove this method since created_organizations is Freemle specific
      def self.all_organization_ids(record_class = Sequent::Core::EventRecord)
        record_class.created_organizations.pluck(:aggregate_id)
      end

      def replay_events_for(organization_id)
        replay_events do
          aggregate_ids = @record_class.connection.select_all("select distinct aggregate_id from #{@record_class.table_name} where organization_id = '#{organization_id}'").map { |hash| hash["aggregate_id"] }
          @record_class.connection.select_all("select id, event_type, event_json from #{@record_class.table_name} where aggregate_id in (#{aggregate_ids.map { |id| %Q{'#{id}'} }.join(",")}) order by id")
        end
      end

    end

  end
end
