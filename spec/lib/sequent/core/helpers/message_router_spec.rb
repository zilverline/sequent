# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::MessageRouter do
  let(:message_router) { Sequent::Core::Helpers::MessageRouter.new }
  let(:handler) { double('handler') }

  describe '#match_message' do
    subject { message_router.match_message(message) }

    class MyLeafEvent < Sequent::Event; end
    class MyOtherEvent < Sequent::Event; end

    let(:attrs) { {aggregate_id: 'x', sequence_number: 1} }

    context 'given no registered routes' do
      let(:message) { MyLeafEvent.new(attrs) }

      it 'returns an empty array' do
        expect(subject).to eq([])
      end
    end

    context 'given a registered route' do
      before do
        message_router.register_messages(MyLeafEvent, handler)
      end

      context 'and the message matches on class name' do
        let(:message) { MyLeafEvent.new(attrs) }

        it 'returns the registered handlers' do
          expect(subject).to eq([handler])
        end
      end

      context 'and the message does not match' do
        let(:message) { MyOtherEvent.new(attrs) }

        it 'returns an empty array' do
          expect(subject).to eq([])
        end
      end
    end
  end
end
