# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Configuration do
  let(:instance) { described_class.instance }

  describe '#time_precision' do
    around do |example|
      precision = ActiveSupport::JSON::Encoding.time_precision
      example.run
    ensure
      ActiveSupport::JSON::Encoding.time_precision = precision
    end

    it 'is deprecated and reads the time precision of ActiveSupport' do
      ActiveSupport::JSON::Encoding.time_precision = 6

      expect { expect(instance.time_precision).to eq 6 }.to output(/DEPRECATED/).to_stderr
    end

    it 'is deprecated to set, which has no effect' do
      expect { instance.time_precision = 6 }.to output(/DEPRECATED.*no effect/).to_stderr
      expect(ActiveSupport::JSON::Encoding.time_precision).to eq 3
    end
  end

  context Sequent::Core::BaseCommandHandler do
    class SpecHandler < Sequent::Core::BaseCommandHandler
      # rubocop:disable-next Lint/UselessMethodDefinition
      def repository
        super
      end
    end
    let(:spec_handler) { SpecHandler.new }

    before :each do
      Sequent.configure do |config|
        config.command_handlers << spec_handler
      end
    end

    it 'adds the default repository to all command handlers' do
      expect(spec_handler.repository).to_not be_nil
      expect(spec_handler.repository).to eq Sequent.configuration.aggregate_repository
    end

    it 'notifies command handlers when event_store changes' do
      new_event_store = double
      Sequent.configuration.event_store = new_event_store
      expect(spec_handler.repository).to eq Sequent.configuration.aggregate_repository
    end
  end

  context 'autoregistering' do
    let!(:command_handler_class) { Class.new(Sequent::CommandHandler) }

    it 'registers all command handlers' do
      Sequent.configure do |config|
        config.command_handlers = []
        config.enable_autoregistration = true
      end
      expect(Sequent.configuration.command_handlers.map(&:class)).to include(command_handler_class)
    end

    context 'it ignores abstract classes' do
      let!(:base_command_handler_class) do
        Class.new(Sequent::CommandHandler) do
          self.abstract_class = true
        end
      end

      it 'does not include the base_command_handler_class' do
        Sequent.configure do |config|
          config.command_handlers = []
          config.enable_autoregistration = true
        end
        expect(Sequent.configuration.command_handlers.map(&:class)).to_not include(base_command_handler_class)
      end
    end

    context 'it fails when trying to register a command_handler twice' do
      let!(:command_handler_class) { Class.new(Sequent::CommandHandler) }
      it 'fails' do
        expect do
          Sequent.configure do |config|
            config.enable_autoregistration = true
            config.command_handlers = [command_handler_class.new]
          end
        end.to raise_error(/is registered 2 times. A CommandHandler can only be registered once/)
      end
    end

    context 'it fails when trying to register an event_handler twice' do
      let!(:event_handler_class) do
        Class.new(Sequent::Projector) { manages_no_tables }
      end
      it 'fails' do
        expect do
          Sequent.configure do |config|
            config.enable_autoregistration = true
            config.event_handlers = [event_handler_class.new]
          end
        end.to raise_error(/is registered 2 times. An EventHandler can only be registered once/)
      end
    end
  end
end
