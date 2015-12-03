require 'spec_helper'

describe Sequent::Core::Oj do
  describe 'BigDecimal support' do
    it 'serializes BigDecimal to a string' do
      bigdecimal = BigDecimal("0.543")
      expect(described_class.strict_load(described_class.dump(bigdecimal))).to eq "0.543"
    end
  end
end
