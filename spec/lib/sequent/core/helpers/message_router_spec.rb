# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::MessageRouter do
  let(:message_router) { Sequent::Core::Helpers::MessageRouter.new }

  let(:handler) { double('handler') }
  let(:other_handler) { double('other handler') }

  describe '#match_message' do
    subject { message_router.match_message(message) }

    class MyMessage < Sequent::Event; end
    class MyOtherMessage < Sequent::Event; end

    let(:attrs) { {aggregate_id: 'x', sequence_number: 1} }

    context 'given no registered message classes' do
      let(:message) { MyMessage.new(attrs) }

      it 'returns an empty set' do
        expect(subject).to eq(Set.new)
      end
    end

    context 'given a registered message class' do
      before do
        message_router.register_messages(MyMessage, handler)
      end

      context 'and the message matches on class name' do
        let(:message) { MyMessage.new(attrs) }

        it 'returns the registered handlers' do
          expect(subject).to eq(Set[handler])
        end

        context 'and the message class is registered multiple times' do
          before do
            message_router.register_messages(MyMessage, other_handler)
          end

          context 'and the handlers are different' do
            it 'returns all registered handlers' do
              expect(subject).to eq(Set[handler, other_handler])
            end
          end

          context 'and the handlers are equal' do
            let(:other_handler) { handler }

            it 'returns unique handlers' do
              expect(subject).to eq(Set[handler])
            end
          end
        end
      end

      context 'and the message does not match' do
        let(:message) { MyOtherMessage.new(attrs) }

        it 'returns an empty set' do
          expect(subject).to eq(Set.new)
        end
      end
    end
  end
end
