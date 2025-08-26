# frozen_string_literal: true

require 'parallel'
require 'postgresql_cursor'

require_relative '../support/database'
require_relative '../sequent'
require_relative '../util/timer'
require_relative '../util/printer'
require_relative 'projectors'
require_relative 'grouper'

module Sequent
  module Migrations
    module EventReplayer
      include Sequent::Util::Timer
      include Sequent::Util::Printer

      attr_reader :logger

      def initialize
        @logger = Sequent.logger
      end

      def replay!(
        replay_persistor,
        projector_classes:,
        minimum_xact_id_inclusive: nil,
        maximum_xact_id_exclusive: nil,
        with_group: ->(_group, _index, &block) { block.call },
        replay_group_target_size: Sequent.configuration.replay_group_target_size,
        number_of_replay_processes: Sequent.configuration.number_of_replay_processes
      )
        event_types = projector_classes.flat_map { |p| p.message_mapping.keys }.uniq.map(&:name)
        event_type_ids = Internal::EventType.where(type: event_types).pluck(:id)

        estimated_event_count, groups = calculate_groups(
          replay_group_target_size:,
          number_of_replay_processes:,
          minimum_xact_id_inclusive:,
          maximum_xact_id_exclusive:,
          event_type_ids:,
        )

        with_sequent_config(replay_persistor, projector_classes) do
          logger.info "Start replaying an estimated #{estimated_event_count} events in #{groups.size} groups"

          time("#{estimated_event_count} events in #{groups.size} groups replayed") do
            disconnect!

            @connected = false
            # using `map_with_index` because https://github.com/grosser/parallel/issues/175
            result = Parallel.map_with_index(
              groups,
              in_processes: number_of_replay_processes,
            ) do |group, index|
              @connected ||= establish_connection
              with_group.call(group, index) do
                msg = <<~EOS.chomp
                  Group #{group} (#{index + 1}/#{groups.size}) replayed
                EOS
                time(msg) do
                  replay_events(
                    -> {
                      event_stream(group, event_type_ids, minimum_xact_id_inclusive, maximum_xact_id_exclusive)
                    },
                    replay_persistor,
                    &on_progress
                  )
                end
              end
              nil
            rescue StandardError => e
              logger.error "Replaying failed for group: #{group}"
              logger.error '+++++++++++++++ ERROR +++++++++++++++'
              recursively_print(e)
              raise Parallel::Kill # immediately kill all sub-processes
            end
            establish_connection
            fail if result.nil?
          end
        end
      end

      def with_sequent_config(replay_persistor, projector_classes, &block)
        old_config = Sequent.configuration

        config = Sequent.configuration.dup

        replay_projectors = projector_classes.map do |projector_class|
          projector_class.new(projector_class.replay_persistor || replay_persistor)
        end
        config.event_handlers = replay_projectors

        Sequent::Configuration.restore(config)

        block.call
      ensure
        Sequent::Configuration.restore(old_config)
      end

      def replay_events(
        get_events,
        replay_persistor,
        &on_progress
      )
        Sequent.configuration.event_store.replay_events_from_cursor(
          get_events:,
          event_publisher: Sequent::Core::EventPublisher.new,
          block_size: 1000,
          on_progress:,
        )

        replay_persistor.commit

        # Also commit all specific declared replay persistors on projectors.
        Sequent.configuration.event_handlers.select { |e| e.class.replay_persistor }.each(&:commit)
      end

      def on_progress
        ->(progress, done, ids) do
          Sequent::Core::EventStore::PRINT_PROGRESS[progress, done, ids] if progress > 0
        end
      end

      def event_stream(group, event_type_ids, minimum_xact_id_inclusive, maximum_xact_id_exclusive)
        fail ArgumentError, 'group is mandatory' if group.nil?

        event_stream = Internal::PartitionedEvent
          .joins('JOIN event_types ON events.event_type_id = event_types.id')
          .where(
            event_type_id: event_type_ids,
          )
        if group.begin
          event_stream = event_stream.where(
            '(events.partition_key, events.aggregate_id) >= (?, ?)',
            group.begin.partition_key,
            group.begin.aggregate_id,
          )
        end
        if group.end
          op = group.exclude_end? ? '<' : '<='
          event_stream = event_stream.where(
            "(events.partition_key, events.aggregate_id) #{op} (?, ?)",
            group.end.partition_key,
            group.end.aggregate_id,
          )
        end
        event_stream = xact_id_filter(event_stream, minimum_xact_id_inclusive, maximum_xact_id_exclusive)
        event_stream
          .order('events.partition_key', 'events.aggregate_id', 'events.sequence_number')
          .select('event_types.type AS event_type, enrich_event_json(events) AS event_json')
      end

      def xact_id_filter(events_query, minimum_xact_id_inclusive, maximum_xact_id_exclusive)
        if minimum_xact_id_inclusive && maximum_xact_id_exclusive
          events_query.where(
            'xact_id >= ? AND xact_id < ?',
            minimum_xact_id_inclusive,
            maximum_xact_id_exclusive,
          )
        elsif minimum_xact_id_inclusive
          events_query.where('xact_id >= ?', minimum_xact_id_inclusive)
        elsif maximum_xact_id_exclusive
          events_query.where('xact_id IS NULL OR xact_id < ?', maximum_xact_id_exclusive)
        else
          events_query
        end
      end

      ## shortcut methods
      def disconnect! = Sequent::Support::Database.disconnect!
      def establish_connection(...) = Sequent::Support::Database.establish_connection(...)

      private

      def calculate_groups(
        replay_group_target_size:,
        number_of_replay_processes:,
        minimum_xact_id_inclusive:,
        maximum_xact_id_exclusive:,
        event_type_ids:
      )
        partitions_query = Internal::PartitionedEvent
          .where(event_type_id: event_type_ids)
          .select('partition_key', 'aggregate_id')
        partitions_query = xact_id_filter(partitions_query, minimum_xact_id_inclusive, maximum_xact_id_exclusive)

        # Let PostgreSQL estimate the number of events matching the event types and xact id constraints.
        estimated_event_count = JSON.parse(
          ActiveRecord::Base.connection.select_value(
            "EXPLAIN (FORMAT JSON) #{partitions_query.to_sql}",
          ),
        ).dig(0, 'Plan', 'Plan Rows') || 0

        target_group_count = [10 * number_of_replay_processes, estimated_event_count / replay_group_target_size].max

        events_table_size = ActiveRecord::Base.connection.select_value(
          'SELECT sum(pg_relation_size(relid))::bigint FROM pg_partition_tree($1) AS t',
          'events table size',
          [Internal::PartitionedEvent.table_name],
        )

        if events_table_size > 10_000_000 && estimated_event_count > 100_000
          # If the table is larger than 10 MB, only scan a subset to avoid spending too much time
          # counting events. An alternative is to use the system time limit tablesample extension:
          # https://www.postgresql.org/docs/current/tsm-system-time.html
          #
          # Event store size            Estimated sampled data size
          # 10 MB                       10 MB
          # 100 MB                      12.5 MB
          # 1 GB                        15.6 MB
          # 10 GB                       19.5 MB
          # 100 GB                      24.4 MB
          # 1 TB                        30.5 MB
          percentage = 100 / (8**Math.log10(events_table_size / 10_000_000))
          partitions_query = partitions_query.joins("TABLESAMPLE SYSTEM (#{percentage})")
        end

        # Use the PostgreSQL `ntile` function to partition the events in similar sized groups:
        # https://www.postgresql.org/docs/current/functions-window.html
        boundaries = ActiveRecord::Base.connection.exec_query(<<~SQL, 'event groups', [target_group_count - 1])
          WITH source AS (#{partitions_query.to_sql}),
               buckets AS (
            SELECT ntile($1) OVER (ORDER BY partition_key, aggregate_id) AS bucket,
                   partition_key,
                   aggregate_id
              FROM source
          )
          SELECT DISTINCT ON (bucket) bucket, partition_key, aggregate_id
            FROM buckets
           ORDER BY bucket, partition_key, aggregate_id
        SQL

        endpoints = boundaries.map { |group| Grouper::GroupEndpoint.new(group['partition_key'], group['aggregate_id']) }
        groups = [nil, *endpoints, nil].each_cons(2).map { |lower, upper| lower...upper }

        [estimated_event_count, groups]
      end
    end
  end
end
