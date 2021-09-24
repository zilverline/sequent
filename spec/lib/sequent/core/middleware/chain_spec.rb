require 'spec_helper'

describe Sequent::Core::Middleware::Chain do
  let(:chain) { Sequent::Core::Middleware::Chain.new }

  describe '#add' do
    subject(:add_middleware) { chain.add(middleware) }

    let(:middleware) { double('middleware') }

    it 'adds the given middleware to the chain' do
      expect { add_middleware }.to change { chain.entries }.from([]).to([middleware])
    end
  end

  describe '#invoke' do
    subject(:invoke_chain) { chain.invoke(command, &invoker) }

    let(:invoker) { -> {} }
    let(:command) { double('command') }

    context 'given an added middleware' do
      let(:middleware) { double('middleware') }

      before do
        chain.add(middleware)
      end

      it 'calls that middleware with the given command as argument' do
        expect(middleware).to receive(:call).ordered.with(command).and_yield
        expect(invoker).to receive(:call).ordered

        invoke_chain
      end
    end

    context 'given multiple added middleware' do
      let(:middleware_1) { double('middleware 1') }
      let(:middleware_2) { double('middleware 2') }

      before do
        chain.add(middleware_1)
        chain.add(middleware_2)
      end

      it 'calls the middleware nested in the order they were added' do
        expect(middleware_1).to receive(:call).ordered.with(command).and_yield
        expect(middleware_2).to receive(:call).ordered.with(command).and_yield
        expect(invoker).to receive(:call).ordered

        invoke_chain
      end
    end
  end
end
