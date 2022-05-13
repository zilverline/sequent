# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::MessageHandlerOptionRegistry do
  let(:option_registry) { Sequent::Core::Helpers::MessageHandlerOptionRegistry.new }
  let(:name) { :my_option }
  let(:handler) { -> {} }

  describe '#register_option' do
    subject { option_registry.register_option(name, handler) }

    context 'given no option is registered with the given name' do
      it 'registers the option' do
        expect { subject }
          .to change { option_registry.entries }
          .from({})
          .to(name => handler)
      end
    end

    context 'given an option is registered with the given name' do
      before do
        option_registry.register_option(name, handler)
      end

      it 'fails' do
        expect { subject }.to raise_error(ArgumentError, "Option with name '#{name}' already registered")
      end
    end
  end

  describe '#call_option' do
    let(:context) { self }

    context 'given an option is registered with the given name' do
      context 'and no argument is passed' do
        let(:args) { [] }

        it 'calls the registered handler without arguments' do
          expect do |b|
            option_registry.register_option(name, b)
            option_registry.call_option(context, name, *args)
          end.to yield_with_no_args
        end
      end

      context 'and a single argument is passed' do
        let(:args) { ['arg'] }

        it 'calls the registered handler with a single argument' do
          expect do |b|
            option_registry.register_option(name, b)
            option_registry.call_option(context, name, *args)
          end.to yield_with_args(*args)
        end
      end

      context 'and multiple arguments are passed' do
        let(:args) { [1, 2] }

        it 'calls the registered handler with all of the arguments' do
          expect do |b|
            option_registry.register_option(name, b)
            option_registry.call_option(context, name, *args)
          end.to yield_with_args(*args)
        end
      end
    end

    context 'given registered options at all' do
      let(:args) { [] }

      it 'fails' do
        expect { option_registry.call_option(context, name, *args) }
          .to raise_error(ArgumentError, "Unsupported option: '#{name}'; no registered options")
      end
    end

    context 'given no option is registered with the given name' do
      let(:args) { [] }

      before do
        option_registry.register_option(:other_option, handler)
      end

      it 'fails' do
        expect { option_registry.call_option(context, name, *args) }
          .to raise_error(ArgumentError, "Unsupported option: '#{name}'; registered options: other_option")
      end
    end
  end
end
