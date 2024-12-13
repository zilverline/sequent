# frozen_string_literal: true

module Sequent
  module Migrations
    module Grouper
      GroupEndpoint = Data.define(:partition_key, :aggregate_id) do
        def <=>(other)
          return unless other.is_a?(self.class)

          [partition_key, aggregate_id] <=> [other.partition_key, other.aggregate_id]
        end

        include Comparable

        def to_s
          "(#{partition_key}, #{aggregate_id})"
        end
      end

      # Generate approximately equally sized groups based on the
      # events partition keys and the number of events per partition
      # key.  Each group is defined by a lower bound (partition-key,
      # aggregate-id) and upper bound (partition-key, aggregate-id)
      # (inclusive).
      #
      # For splitting a partition into equal sized groups the
      # assumption is made that aggregate-ids and their events are
      # equally distributed.
      def self.group_partitions(partitions, target_group_size)
        return [] unless partitions.present?

        partitions = partitions.sort.map do |key, count|
          PartitionData.new(key:, original_size: count, remaining_size: count, lower_bound: 0)
        end

        partition = partitions.shift
        current_start = GroupEndpoint.new(partition.key, LOWEST_UUID)
        current_size = 0

        result = []
        while partition.present?
          if current_size + partition.remaining_size < target_group_size
            current_size += partition.remaining_size
            if partitions.empty?
              result << (current_start..GroupEndpoint.new(partition.key, HIGHEST_UUID))
              break
            end
            partition = partitions.shift
          elsif current_size + partition.remaining_size == target_group_size
            result << (current_start..GroupEndpoint.new(partition.key, HIGHEST_UUID))

            partition = partitions.shift
            break unless partition

            current_start = GroupEndpoint.new(partition.key, LOWEST_UUID)
            current_size = 0
          else
            taken = target_group_size - current_size
            upper_bound = partition.lower_bound + (UUID_COUNT * taken / partition.original_size)

            result << (current_start..GroupEndpoint.new(partition.key, number_to_uuid(upper_bound - 1)))

            remaining_size = partition.remaining_size - taken
            partition = partition.with(remaining_size:, lower_bound: upper_bound)
            current_start = GroupEndpoint.new(partition.key, number_to_uuid(upper_bound))
            current_size = 0
          end
        end
        result
      end

      PartitionData = Data.define(:key, :original_size, :remaining_size, :lower_bound)

      def self.number_to_uuid(number)
        fail ArgumentError, number unless (0..UUID_COUNT - 1).include? number

        s = format('%032x', number)
        "#{s[0..7]}-#{s[8..11]}-#{s[12..15]}-#{s[16..19]}-#{s[20..]}"
      end

      def self.uuid_to_number(uuid)
        Integer(uuid.gsub('-', ''), 16)
      end

      UUID_COUNT = 2**128
      LOWEST_UUID = number_to_uuid(0)
      HIGHEST_UUID = number_to_uuid(UUID_COUNT - 1)
    end
  end
end
