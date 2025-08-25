# frozen_string_literal: true

require 'spec_helper'
require 'prop_check'
require 'sequent/migrations/grouper'

describe Sequent::Migrations::Grouper do
  G = PropCheck::Generators

  EP = ->(partition_key, aggregate_id) { Sequent::Migrations::Grouper::GroupEndpoint.new(partition_key, aggregate_id) }
  NEXT_UUID = ->(uuid) {
    Sequent::Migrations::Grouper.number_to_uuid(
      (Sequent::Migrations::Grouper.uuid_to_number(uuid) + 1) % Sequent::Migrations::Grouper::UUID_COUNT,
    )
  }

  let(:subject) { Sequent::Migrations::Grouper }
  let(:partitions) do
    {a: 200, b: 600, c: 200}
  end

  it 'groups partitions into a sorted list covering all partitions without gaps' do
    PropCheck.forall(
      G.hash(G.alphanumeric_string, G.positive_integer),
      G.positive_integer,
    ) do |partitions, group_target_size|
      next unless partitions.present?

      groups = subject.group_partitions(partitions, group_target_size)

      # The groups must cover all partitions
      expect(groups.first.begin).to be_nil
      expect(groups.last.end).to be_nil

      groups.each do |group|
        # begin must be before end for each group
        expect(group).to be_exclude_end
        expect(group.end).to be > group.begin unless group == groups.first || group == groups.last
      end
      groups.each_cons(2).each do |prev_group, next_group|
        # exclusive end of previous group must be equal begin of next group (consecutive groups)
        expect(prev_group.end).to eq(next_group.begin)
      end
    end
  end

  it 'creates a single group when all partitions fit' do
    expect(subject.group_partitions(partitions, 1000))
      .to eq([nil...nil])
  end

  it 'creates multiple groups from a single large partition' do
    expect(subject.group_partitions({a: 100}, 40))
      .to eq(
        [
          nil...EP[:a, '66666666-6666-6666-6666-666666666666'],
          EP[:a, '66666666-6666-6666-6666-666666666666']...EP[:a, 'cccccccc-cccc-cccc-cccc-cccccccccccc'],
          EP[:a, 'cccccccc-cccc-cccc-cccc-cccccccccccc']...nil,
        ],
      )
  end

  context 'splits groups assuming an uniform distribution' do
    it 'splits group in half' do
      expect(subject.group_partitions(partitions, 500))
        .to eq(
          [
            nil...EP[:b, '80000000-0000-0000-0000-000000000000'],
            EP[:b, '80000000-0000-0000-0000-000000000000']...nil,
          ],
        )
    end

    it 'splits group in three unequal parts' do
      expect(subject.group_partitions(partitions, 400))
        .to eq(
          [
            nil...EP[:b, '55555555-5555-5555-5555-555555555555'],
            EP[:b, '55555555-5555-5555-5555-555555555555']...EP[:c, '00000000-0000-0000-0000-000000000000'],
            EP[:c, '00000000-0000-0000-0000-000000000000']...nil,
          ],
        )
    end

    it 'splits group in three equal parts' do
      expect(subject.group_partitions({a: 200, b: 500, c: 200}, 300))
        .to eq(
          [
            nil...EP[:b, '33333333-3333-3333-3333-333333333333'],
            EP[:b, '33333333-3333-3333-3333-333333333333']...EP[:b, 'cccccccc-cccc-cccc-cccc-cccccccccccc'],
            EP[:b, 'cccccccc-cccc-cccc-cccc-cccccccccccc']...nil,
          ],
        )
    end

    it 'splits group in many equal parts' do
      expect(subject.group_partitions({a: 200, b: 500, c: 200}, 300))
        .to eq(
          [
            nil...EP[:b, '33333333-3333-3333-3333-333333333333'],
            EP[:b, '33333333-3333-3333-3333-333333333333']...EP[:b, 'cccccccc-cccc-cccc-cccc-cccccccccccc'],
            EP[:b, 'cccccccc-cccc-cccc-cccc-cccccccccccc']...nil,
          ],
        )
    end
  end
end
