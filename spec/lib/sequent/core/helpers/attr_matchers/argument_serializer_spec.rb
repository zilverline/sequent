# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::AttrMatchers::ArgumentSerializer do
  describe '.serialize_value' do
    subject { Sequent::Core::Helpers::AttrMatchers::ArgumentSerializer.serialize_value(value) }

    context 'given nil' do
      let(:value) { nil }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end

    context 'given a String' do
      let(:value) { 'something' }

      it 'returns a quoted value' do
        expect(subject).to eq('"something"')
      end
    end

    context 'given it responds to #matches_attr?(expected_value)' do
      let(:value) { Sequent::Core::Helpers::AttrMatchers::GreaterThanEquals.new(100) }

      it 'returns the attr matcher description' do
        expect(subject).to eq('gte(100)')
      end
    end

    context 'given something else' do
      let(:value) { 100 }

      it 'returns the value' do
        expect(subject).to eq(100)
      end
    end
  end
end
