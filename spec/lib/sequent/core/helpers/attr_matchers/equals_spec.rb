# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::AttrMatchers::Equals do
  let(:matcher) { Sequent::Core::Helpers::AttrMatchers::Equals.new(expected_value) }
  let(:actual_value) { 'foo' }
  let(:expected_value) { 'foo' }

  describe '#matches_attr?' do
    subject { matcher.matches_attr?(actual_value) }

    context 'given the actual value is equal to the expected value' do
      let(:actual_value) { 'foo' }
      let(:expected_value) { 'foo' }

      it 'returns true' do
        expect(subject).to be_truthy
      end
    end

    context 'given the actual value is not equal to the expected value' do
      let(:actual_value) { 'foo' }
      let(:expected_value) { 'bar' }

      it 'returns false' do
        expect(subject).to be_falsey
      end
    end
  end

  describe '#matcher_description' do
    subject { matcher.matcher_description }

    it 'returns a description for the matcher' do
      expect(subject).to eq('eq("foo")')
    end
  end
end
