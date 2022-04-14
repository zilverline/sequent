# frozen_string_literal: true

require 'spec_helper'
require_relative 'test_messages'

describe Sequent::Core::Helpers::MessageMatchers::Any do
  let(:matcher) { Sequent::Core::Helpers::MessageMatchers::Any.new }

  describe '#matches_message?' do
    subject { matcher.matches_message?(message) }

    let(:message) { TestMessage.new(attrs) }
    let(:attrs) { {aggregate_id: 'x', sequence_number: 1} }

    it 'returns true' do
      expect(subject).to be_truthy
    end
  end
end
