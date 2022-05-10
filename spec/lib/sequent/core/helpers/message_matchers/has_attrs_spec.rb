# frozen_string_literal: true

require 'spec_helper'
require_relative 'test_messages'

describe Sequent::Core::Helpers::MessageMatchers::HasAttrs do
  let(:matcher) { Sequent::Core::Helpers::MessageMatchers::HasAttrs.new(message_matcher, expected_attrs) }
  let(:message) { TestMessage.new(attrs) }
  let(:attrs) { {aggregate_id: 'x', sequence_number: 1} }
  let(:message_matcher) { TestMessage }
  let(:expected_attrs) { {aggregate_id: 'x', sequence_number: 1} }

  describe '#matches_message?' do
    subject { matcher.matches_message?(message) }

    context 'given the message matcher argument is a class' do
      context 'and the class matches' do
        let(:message_matcher) { TestMessage }

        context 'and the message matches all of the expected attrs' do
          it 'returns true' do
            expect(subject).to be_truthy
          end

          context 'and an expected value is a message matcher' do
            let(:expected_attrs) do
              {
                aggregate_id: 'x',
                sequence_number: Sequent::Core::Helpers::AttrMatchers::GreaterThanEquals.new(0),
              }
            end

            it 'evaluates and returns true' do
              expect(subject).to be_truthy
            end
          end
        end

        context 'and the message matches some of the expected attrs' do
          let(:attrs) { {aggregate_id: 'x', sequence_number: 2} }

          it 'returns false' do
            expect(subject).to be_falsey
          end

          context 'and an expected value is a message matcher' do
            let(:expected_attrs) do
              {
                aggregate_id: 'x',
                sequence_number: Sequent::Core::Helpers::AttrMatchers::GreaterThanEquals.new(3),
              }
            end

            it 'evaluates and returns false' do
              expect(subject).to be_falsey
            end
          end
        end

        context 'and the message matches none of the expected attrs' do
          let(:attrs) { {aggregate_id: 'y', sequence_number: 2} }

          it 'returns false' do
            expect(subject).to be_falsey
          end
        end
      end

      context 'and the class does not match' do
        let(:message_matcher) { OtherTestMessage }

        it 'returns false' do
          expect(subject).to be_falsey
        end
      end
    end

    context 'given the message matcher argument responds to matches_message?' do
      context 'and the matcher matches' do
        let(:message_matcher) { Sequent::Core::Helpers::MessageMatchers::IsA.new(TestModule) }

        it 'returns true' do
          expect(subject).to be_truthy
        end
      end

      context 'and the matcher does not match' do
        let(:message_matcher) { Sequent::Core::Helpers::MessageMatchers::IsA.new(TestModule, except: TestMessage) }

        it 'returns false' do
          expect(subject).to be_falsey
        end
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
      expect(subject).to eq(%[has_attrs(TestMessage, aggregate_id: "x", sequence_number: 1)])
    end
  end
end
