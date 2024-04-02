# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/sequent/migrations/grouper'

describe Sequent::Migrations::Grouper do
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

  def ensure_invariants(groups)
    groups.each do |group|
      # begin must be before end for each group
      expect(group.exclude_end?).to be_falsey
      expect(group.begin).to be <= group.end
    end
    groups.each_cons(2).each do |prev_group, next_group|
      # end of previous group must be before begin of next group
      expect(prev_group.end).to be < next_group.begin
      if prev_group.end.partition_key == next_group.begin.partition_key
        expect(NEXT_UUID[prev_group.end.aggregate_id]).to eq(next_group.begin.aggregate_id)
      else
        expect(prev_group.end.aggregate_id).to eq(Sequent::Migrations::Grouper::HIGHEST_UUID)
        expect(next_group.begin.aggregate_id).to eq(Sequent::Migrations::Grouper::LOWEST_UUID)
      end
    end
  end

  it 'creates a single group when all partitions fit' do
    expect(subject.group_partitions(partitions, 1000, 1))
      .to eq([EP[:a, subject::LOWEST_UUID]..EP[:c, subject::HIGHEST_UUID]])
  end

  it 'creates multiple groups from a single large partition' do
    expect(subject.group_partitions({a: 100}, 40, 1))
      .to eq(
        [
          EP[:a, subject::LOWEST_UUID]..EP[:a, '66666666-6666-6666-6666-666666666665'],
          EP[:a, '66666666-6666-6666-6666-666666666666']..EP[:a, 'cccccccc-cccc-cccc-cccc-cccccccccccb'],
          EP[:a, 'cccccccc-cccc-cccc-cccc-cccccccccccc']..EP[:a, subject::HIGHEST_UUID],
        ],
      )
    ensure_invariants(subject.group_partitions({a: 100}, 40, 1))
  end

  context 'splits groups assuming an uniform distribution' do
    it 'splits group in half' do
      expect(subject.group_partitions(partitions, 500, 1))
        .to eq(
          [
            EP[:a, subject::LOWEST_UUID]..EP[:b, '7fffffff-ffff-ffff-ffff-ffffffffffff'],
            EP[:b, '80000000-0000-0000-0000-000000000000']..EP[:c, subject::HIGHEST_UUID],
          ],
        )
    end

    it 'splits group in three unequal parts' do
      expect(subject.group_partitions(partitions, 400, 1))
        .to eq(
          [
            EP[:a, subject::LOWEST_UUID]..EP[:b, '55555555-5555-5555-5555-555555555554'],
            EP[:b, '55555555-5555-5555-5555-555555555555']..EP[:b, 'ffffffff-ffff-ffff-ffff-ffffffffffff'],
            EP[:c, '00000000-0000-0000-0000-000000000000']..EP[:c, subject::HIGHEST_UUID],
          ],
        )
    end

    it 'splits group in three equal parts' do
      expect(subject.group_partitions({a: 200, b: 500, c: 200}, 300, 1))
        .to eq(
          [
            EP[:a, subject::LOWEST_UUID]..EP[:b, '33333333-3333-3333-3333-333333333332'],
            EP[:b, '33333333-3333-3333-3333-333333333333']..EP[:b, 'cccccccc-cccc-cccc-cccc-cccccccccccb'],
            EP[:b, 'cccccccc-cccc-cccc-cccc-cccccccccccc']..EP[:c, subject::HIGHEST_UUID],
          ],
        )
    end

    it 'splits group in many equal parts' do
      expect(subject.group_partitions({a: 200, b: 500, c: 200}, 300, 1))
        .to eq(
          [
            EP[:a, subject::LOWEST_UUID]..EP[:b, '33333333-3333-3333-3333-333333333332'],
            EP[:b, '33333333-3333-3333-3333-333333333333']..EP[:b, 'cccccccc-cccc-cccc-cccc-cccccccccccb'],
            EP[:b, 'cccccccc-cccc-cccc-cccc-cccccccccccc']..EP[:c, subject::HIGHEST_UUID],
          ],
        )
    end
  end
end
