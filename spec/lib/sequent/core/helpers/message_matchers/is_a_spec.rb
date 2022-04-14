# frozen_string_literal: true

require 'spec_helper'
require_relative 'test_messages'

describe Sequent::Core::Helpers::MessageMatchers::IsA do
  let(:matcher) { Sequent::Core::Helpers::MessageMatchers::IsA.new(expected_class, **opts) }
  let(:opts) { {} }

  describe '#matches_message?' do
    subject { matcher.matches_message?(message) }

    let(:message) { TestMessage.new(attrs) }
    let(:attrs) { {aggregate_id: 'x', sequence_number: 1} }
    let(:expected_class) { TestMessage }

    context 'given a message that is of the expected class' do
      it 'returns true' do
        expect(subject).to be_truthy
      end
    end

    context 'given a message that is not of the expected class' do
      let(:expected_class) { OtherTestMessage }

      it 'returns false' do
        expect(subject).to be_falsey
      end
    end

    context 'given a message whose class is a sub-class of the expected class' do
      let(:message) { SubTestMessage.new(attrs) }

      it 'returns true' do
        expect(subject).to be_truthy
      end
    end

    context 'given a message whose class is a super class of the expected class' do
      let(:message) { SuperTestMessage.new(attrs) }

      it 'returns false' do
        expect(subject).to be_falsey
      end
    end

    context 'given a message that includes the expected class (read: module)' do
      let(:expected_class) { TestModule }
      let(:message) { TestMessage.new(attrs) }

      it 'returns true' do
        expect(subject).to be_truthy
      end

      context 'and the message class is excluded' do
        let(:opts) { {except: except} }

        context 'and except is a single value' do
          let(:except) { TestMessage }

          it 'returns false' do
            expect(subject).to be_falsey
          end

          context 'nil' do
            let(:except) { nil }

            it 'returns true' do
              expect(subject).to be_truthy
            end
          end
        end

        context 'and except is an array' do
          context 'and any matches' do
            let(:except) { [TestMessage, OtherTestMessage] }

            it 'returns false' do
              expect(subject).to be_falsey
            end
          end

          context 'and none matches' do
            let(:except) { [OtherTestMessage] }

            it 'returns true' do
              expect(subject).to be_truthy
            end
          end

          context 'and no entries' do
            let(:except) { [] }

            it 'returns true' do
              expect(subject).to be_truthy
            end
          end
        end
      end
    end
  end
end
