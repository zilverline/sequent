# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::MessageMatchers::ArgumentSerializer do
  describe '.serialize_value' do
    subject { Sequent::Core::Helpers::MessageMatchers::ArgumentSerializer.serialize_value(value) }

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

    context 'given it responds to #matches_message?(message)' do
      let(:value) { Sequent::Core::Helpers::MessageMatchers::IsA.new(Object) }

      it 'returns the message matcher description' do
        expect(subject).to eq('is_a(Object)')
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
