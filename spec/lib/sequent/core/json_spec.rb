# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Json do
  class JsonSpecEvent < Sequent::Core::Event
    attrs at: Time, times: array(Time), data: Hash, amount: BigDecimal
  end

  let(:time) { Time.utc(2026, 1, 2, 3, 4, 5.123456r) }

  def dump_and_load(event)
    JsonSpecEvent.deserialize_from_json(described_class.strict_load(described_class.dump(event)))
  end

  it 'serializes BigDecimal to a string' do
    bigdecimal = BigDecimal('0.543')
    expect(described_class.strict_load(described_class.dump(bigdecimal))).to eq '0.543'
  end

  it 'loads a BigDecimal attribute without losing precision' do
    amount = BigDecimal('12345678901234567890.123456789')
    event = JsonSpecEvent.new(aggregate_id: 'a', sequence_number: 1, amount:)

    expect(dump_and_load(event).amount).to eq amount
  end

  it 'loads numbers as Integer or Float' do
    expect(described_class.strict_load('{"i":1,"f":0.30000000000000004}')).to eq('i' => 1, 'f' => 0.30000000000000004)
  end

  it 'serializes times using the time precision of Sequent' do
    Sequent.configuration.time_precision = 6
    event = JsonSpecEvent.new(aggregate_id: 'a', sequence_number: 1, at: time, times: [time], data: {'at' => time})

    json = described_class.strict_load(described_class.dump(event))

    expect(json.values_at('at', 'times', 'data')).to eq [
      '2026-01-02T03:04:05.123456Z',
      ['2026-01-02T03:04:05.123456Z'],
      {'at' => '2026-01-02T03:04:05.123456Z'},
    ]
    expect(dump_and_load(event).at).to eq time
  end
end

describe Sequent::Core::Oj do
  before { described_class.instance_variable_set(:@warned_deprecated, nil) }

  it 'is deprecated, warns once, and uses Sequent::Core::Json' do
    expect do
      expect(described_class.strict_load(described_class.dump(BigDecimal('0.543')))).to eq '0.543'
    end.to output(/DEPRECATED.*Sequent::Core::Json/).to_stderr
    expect { described_class.dump(1) }.not_to output.to_stderr
  end
end
