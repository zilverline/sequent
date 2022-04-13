# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::CommandRecord do
  let(:command) { Sequent::Core::Command.new(aggregate_id: 'abc') }

  subject { described_class.new }

  describe '#command' do
    before do
      subject.command = command
    end

    it 'returns the original command command' do
      expect(subject.command).to eq command
    end
  end
end
