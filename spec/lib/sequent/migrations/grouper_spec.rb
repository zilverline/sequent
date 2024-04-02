# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../lib/sequent/migrations/grouper'

describe Sequent::Migrations::Grouper do
  let(:subject) { Sequent::Migrations::Grouper }
  let(:partitions) do
    {a: 200, b: 600, c: 200}
  end

  def ensure_invariants(groups)
    groups.each do |range|
      # start must be <= to end_inclusive for each group
      expect(range.begin <=> range.end).to be <= 0
    end
    groups.each_cons(2).each do |prev_group, next_group|
      # end of previous group must be < start of next group
      expect(prev_group.end <=> next_group.end).to be < 0
    end
  end
  
  it 'creates a single group when all partitions fit' do
    expect(subject.group_partitions(partitions, 1000, 1))
      .to eq([[:a, subject::LOWEST_UUID] .. [:c, subject::HIGHEST_UUID]])
end

  it 'creates multiple groups from a single large partition' do
    expect(subject.group_partitions({a: 100}, 40, 1))
      .to eq(
        [
          [:a, subject::LOWEST_UUID] .. [:a, '66666666-6666-6666-6666-666666666665'],
          [:a, '66666666-6666-6666-6666-666666666666'] .. [:a, 'cccccccc-cccc-cccc-cccc-cccccccccccb'],
          [:a, 'cccccccc-cccc-cccc-cccc-cccccccccccc'] .. [:a, subject::HIGHEST_UUID],
        ],
      )
    ensure_invariants(subject.group_partitions({a: 100}, 40, 1))
  end

  context 'splits groups assuming an uniform distribution' do
    it 'splits group in half' do
      expect(subject.group_partitions(partitions, 500, 1))
        .to eq(
          [
            [:a, subject::LOWEST_UUID] .. [:b, '7fffffff-ffff-ffff-ffff-ffffffffffff'],
            [:b, '80000000-0000-0000-0000-000000000000'] .. [:c, subject::HIGHEST_UUID],
          ],
        )
    end

    it 'splits group in three unequal parts' do
      expect(subject.group_partitions(partitions, 400, 1))
        .to eq(
          [
            [:a, subject::LOWEST_UUID] .. [:b, '55555555-5555-5555-5555-555555555554'],
            [:b, '55555555-5555-5555-5555-555555555555'] .. [:b, 'ffffffff-ffff-ffff-ffff-ffffffffffff'],
            [:c, '00000000-0000-0000-0000-000000000000'] .. [:c, subject::HIGHEST_UUID],
          ],
        )
    end

    it 'splits group in three equal parts' do
      expect(subject.group_partitions({a: 200, b: 500, c: 200}, 300, 1))
        .to eq(
          [
            [:a, subject::LOWEST_UUID] .. [:b, '33333333-3333-3333-3333-333333333332'],
            [:b, '33333333-3333-3333-3333-333333333333'] .. [:b, 'cccccccc-cccc-cccc-cccc-cccccccccccb'],
            [:b, 'cccccccc-cccc-cccc-cccc-cccccccccccc'] .. [:c, subject::HIGHEST_UUID],
          ],
        )
    end

    it 'splits group in many equal parts' do
      expect(subject.group_partitions({a: 200, b: 500, c: 200}, 300, 1))
        .to eq(
          [
            [:a, subject::LOWEST_UUID] .. [:b, '33333333-3333-3333-3333-333333333332'],
            [:b, '33333333-3333-3333-3333-333333333333'] .. [:b, 'cccccccc-cccc-cccc-cccc-cccccccccccb'],
            [:b, 'cccccccc-cccc-cccc-cccc-cccccccccccc'] .. [:c, subject::HIGHEST_UUID],
          ],
        )
    end
  end
end
