# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::AttrMatchers::GreaterThanEquals do
  let(:matcher) { Sequent::Core::Helpers::AttrMatchers::GreaterThanEquals.new(expected_value) }
  let(:actual_value) { 1 }
  let(:expected_value) { 1 }

  describe '#matches_attr?' do
    subject { matcher.matches_attr?(actual_value) }

    context 'given the actual value is less than the expected value' do
      let(:actual_value) { 1 }
      let(:expected_value) { 2 }

      it 'returns false' do
        expect(subject).to be_falsey
      end
    end

    context 'given the actual value is equal to the expected value' do
      let(:actual_value) { 1 }
      let(:expected_value) { 1 }

      it 'returns true' do
        expect(subject).to be_truthy
      end
    end

    context 'given the actual value is greater than the expected value' do
      let(:actual_value) { 2 }
      let(:expected_value) { 1 }

      it 'returns true' do
        expect(subject).to be_truthy
      end
    end
  end

  describe '#to_s' do
    subject { matcher.to_s }

    it 'returns a description for the matcher' do
      expect(subject).to eq('gte(1)')
    end
  end
end
