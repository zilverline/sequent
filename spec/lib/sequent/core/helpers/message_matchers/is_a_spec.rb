# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::MessageMatchers::IsA do
  let(:matcher) { Sequent::Core::Helpers::MessageMatchers::IsA.new(expected_class: expected_class) }

  describe '#matches_message?' do
    subject { matcher.matches_message?(message) }

    module SomeModule; end
    class SomeSuperEvent < Sequent::Event; end
    class SomeEvent < SomeSuperEvent
      include SomeModule
    end
    class SomeSubEvent < SomeEvent; end
    class OtherEvent < Sequent::Event; end

    let(:message) { SomeEvent.new(attrs) }
    let(:attrs) { {aggregate_id: 'x', sequence_number: 1} }
    let(:expected_class) { SomeEvent }

    context 'given a message that is of the expected class' do
      it 'returns true' do
        expect(subject).to be_truthy
      end
    end

    context 'given a message that is not of the expected class' do
      let(:expected_class) { OtherEvent }

      it 'returns false' do
        expect(subject).to be_falsey
      end
    end

    context 'given a message whose class is a sub-class of the expected class' do
      let(:message) { SomeSubEvent.new(attrs) }

      it 'returns true' do
        expect(subject).to be_truthy
      end
    end

    context 'given a message whose class is a super class of the expected class' do
      let(:message) { SomeSuperEvent.new(attrs) }

      it 'returns false' do
        expect(subject).to be_falsey
      end
    end

    context 'given a message that includes the expected class (read: module)' do
      let(:expected_class) { SomeModule }
      let(:message) { SomeEvent.new(attrs) }

      it 'returns true' do
        expect(subject).to be_truthy
      end
    end
  end
end
