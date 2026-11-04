# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Event, 'times' do
  class TruncatedTimesValue < Sequent::Core::ValueObject
    attrs at: Time, name: String
  end

  class TruncatedTimesEvent < Sequent::Core::Event
    attrs at: Time,
          at_with_offset: DateTime,
          value: TruncatedTimesValue,
          values: array(TruncatedTimesValue),
          day: Date
  end

  let(:time) { Time.new(2026, 1, 2, 3, 4, 5.123456789r, '+01:00') }

  def event(**attributes) = TruncatedTimesEvent.new(aggregate_id: 'a', sequence_number: 1, **attributes)

  it 'truncates the times to the precision with which they are stored' do
    truncated = event(at: time, at_with_offset: DateTime.new(2026, 1, 2, 3, 4, 5.123456r, '+02:00'))

    expect(truncated.at.nsec).to eq 123_000_000
    expect(truncated.at.utc_offset).to eq 3600
    expect(truncated.at_with_offset.sec_fraction).to eq 123r / 1000
    expect(truncated.at_with_offset.offset).to eq 2r / 24
  end

  it 'keeps the values that do not change' do
    day = Date.new(2026, 1, 2)
    at = Time.new(2026, 1, 2, 3, 4, 5.123r, '+01:00')

    expect(event(at:, day:)).to have_attributes(at: be(at), day: be(day))
  end

  it 'truncates the times of value objects and arrays without changing those of the domain code' do
    value = TruncatedTimesValue.new(at: time, name: 'a')
    unchanged = TruncatedTimesValue.new(at: Time.new(2026, 1, 2, 3, 4, 5.123r, '+01:00'), name: 'b')

    truncated = event(value:, values: [unchanged, value])

    expect(truncated.value.at.nsec).to eq 123_000_000
    expect(truncated.values.map { |v| v.at.nsec }).to eq [123_000_000, 123_000_000]
    expect(truncated.values.first).to be unchanged
    expect(value.at.nsec).to eq 123_456_789
  end

  it 'gives a created_at in the time zone of ActiveRecord, truncated like the other times' do
    expect(event.created_at.utc_offset).to eq 0
    expect(event.created_at.nsec % 1_000_000).to eq 0
  end
end
