# frozen_string_literal: true

require 'spec_helper'
require_relative 'test_messages'

describe Sequent::Core::Helpers::MessageMatchers::HasAttrs do
  let(:matcher) { Sequent::Core::Helpers::MessageMatchers::HasAttrs.new(expected_attrs) }
  let(:message) { TestMessage.new(attrs) }
  let(:attrs) { {aggregate_id: 'x', sequence_number: 1} }
  let(:expected_attrs) { {aggregate_id: 'x', sequence_number: 1} }

  describe '#matches_message?' do
    subject { matcher.matches_message?(message) }

    context 'given the message matches all of the expected attrs' do
      it 'returns true' do
        expect(subject).to be_truthy
      end
    end

    context 'given the message matches some of the expected attrs' do
      let(:attrs) { {aggregate_id: 'x', sequence_number: 2} }

      it 'returns false' do
        expect(subject).to be_falsey
      end
    end

    context 'given the message matches none of the expected attrs' do
      let(:attrs) { {aggregate_id: 'y', sequence_number: 2} }

      it 'returns false' do
        expect(subject).to be_falsey
      end
    end

    context 'given no expected attrs' do
      context 'empty hash' do
        let(:expected_attrs) { {} }

        it 'fails' do
          expect { subject }.to raise_error(ArgumentError, 'Missing required expected attrs')
        end
      end

      context 'nil' do
        let(:expected_attrs) { nil }

        it 'fails' do
          expect { subject }.to raise_error(ArgumentError, 'Missing required expected attrs')
        end
      end
    end
  end

  describe '#matcher_description' do
    subject { matcher.matcher_description }

    it 'returns a description for the matcher including all expected attrs' do
      expect(subject).to eq(%[has_attrs(aggregate_id: 'x', sequence_number: 1)])
    end
  end
end
