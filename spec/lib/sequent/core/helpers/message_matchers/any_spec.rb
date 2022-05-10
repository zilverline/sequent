# frozen_string_literal: true

require 'spec_helper'
require_relative 'test_messages'

describe Sequent::Core::Helpers::MessageMatchers::Any do
  let(:matcher) { Sequent::Core::Helpers::MessageMatchers::Any.new(**opts) }

  describe '#matches_message?' do
    subject { matcher.matches_message?(message) }

    let(:message) { TestMessage.new(attrs) }
    let(:attrs) { {aggregate_id: 'x', sequence_number: 1} }

    context 'given no opts' do
      let(:opts) { {} }

      it 'returns true' do
        expect(subject).to be_truthy
      end
    end

    context 'given an except opt' do
      let(:opts) { {except: except} }

      context 'and it matches' do
        let(:except) { TestMessage }

        it 'returns false' do
          expect(subject).to be_falsey
        end
      end

      context 'and it does not match' do
        let(:except) { OtherTestMessage }

        it 'returns true' do
          expect(subject).to be_truthy
        end
      end
    end
  end

  describe '#matcher_description' do
    subject { matcher.matcher_description }

    context 'given no opts' do
      let(:opts) { {} }

      it 'only returns the matcher name' do
        expect(subject).to eq('any')
      end
    end

    context 'given an except opt' do
      let(:opts) { {except: TestMessage} }

      it 'returns the matcher name and except opt' do
        expect(subject).to eq('any(except: TestMessage)')
      end
    end
  end
end
