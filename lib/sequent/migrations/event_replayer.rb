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
        with_group: ->(_group, _index, &block) { block.call }
      )
        event_types = projector_classes.flat_map { |p| p.message_mapping.keys }.uniq.map(&:name)
        group_target_size = Sequent.configuration.replay_group_target_size
        event_type_ids = Internal::EventType.where(type: event_types).pluck(:id)

        partitions_query = Internal::PartitionedEvent.where(event_type_id: event_type_ids)
        partitions_query = xact_id_filter(partitions_query, minimum_xact_id_inclusive, maximum_xact_id_exclusive)

        partitions = partitions_query.group(:partition_key).order(:partition_key).count
        event_count = partitions.values.sum

        groups = Sequent::Migrations::Grouper.group_partitions(partitions, group_target_size)

        if groups.empty?
          groups = [nil..nil]
        else
          groups.prepend(nil..groups.first.begin)
          groups.append(groups.last.end..nil)
        end

        with_sequent_config(replay_persistor, projector_classes) do
          logger.info "Start replaying #{event_count} events in #{groups.size} groups"

          time("#{event_count} events in #{groups.size} groups replayed") do
            disconnect!

            @connected = false
            # using `map_with_index` because https://github.com/grosser/parallel/issues/175
            result = Parallel.map_with_index(
              groups,
              in_processes: Sequent.configuration.number_of_replay_processes,
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
        if group.begin && group.end
          event_stream = event_stream.where(
            '(events.partition_key, events.aggregate_id) BETWEEN (?, ?) AND (?, ?)',
            group.begin.partition_key,
            group.begin.aggregate_id,
            group.end.partition_key,
            group.end.aggregate_id,
          )
        elsif group.end
          event_stream = event_stream.where(
            '(events.partition_key, events.aggregate_id) < (?, ?)',
            group.end.partition_key,
            group.end.aggregate_id,
          )
        elsif group.begin
          event_stream = event_stream.where(
            '(events.partition_key, events.aggregate_id) > (?, ?)',
            group.begin.partition_key,
            group.begin.aggregate_id,
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
    end
  end
end
