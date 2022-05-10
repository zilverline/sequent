# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::MessageMatchers::ArgumentCoercer do
  describe '.coerce_argument' do
    subject { Sequent::Core::Helpers::MessageMatchers::ArgumentCoercer.coerce_argument(arg) }

    class MyEvent < Sequent::Event; end
    module MyModule; end

    context 'given nil' do
      let(:arg) { nil }

      it 'fails' do
        expect { subject }.to raise_error(ArgumentError, 'Cannot coerce nil argument')
      end
    end

    context 'given a Class argument' do
      let(:arg) { MyEvent }

      it 'returns the argument wrapped in a MessageMatchers::ClassEquals' do
        expect(subject).to eq(Sequent::Core::Helpers::MessageMatchers::ClassEquals.new(arg))
      end
    end

    context 'given a module argument' do
      let(:arg) { MyModule }

      it 'returns the argument wrapped in a MessageMatchers::ClassEquals' do
        expect(subject).to eq(Sequent::Core::Helpers::MessageMatchers::ClassEquals.new(arg))
      end
    end

    context 'given the argument responds to :matches_message?' do
      let(:arg) { Sequent::Core::Helpers::MessageMatchers::IsA.new(MyModule) }

      it 'returns that argument' do
        expect(subject).to eq(arg)
      end
    end

    context 'given something else' do
      let(:arg) { Object.new }

      it 'fails' do
        expect { subject }.to raise_error(
          ArgumentError,
          "Can't coerce argument '#{arg}'; " \
          'must be either a Class, Module or message matcher (respond to :matches_message?)',
        )
      end
    end
  end
end
