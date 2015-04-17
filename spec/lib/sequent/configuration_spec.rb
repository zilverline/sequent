require 'spec_helper'

describe Sequent::Configuration do
  let(:instance) { described_class.instance }

  it 'configures a new aggregate store if the event store changes' do
    new_event_store = double
    Sequent.configuration.event_store = new_event_store
    expect(Sequent.configuration.aggregate_repository.instance_variable_get(:@event_store)).to eq new_event_store
  end

  describe '#all_event_handlers' do
    subject { instance.all_event_handlers }

    let!(:event_handler) { Class.new(Sequent::Core::BaseEventHandler) }

    let(:declared_event_handler) { Class.new }
    before { Sequent.configure { |c| c.event_handlers << declared_event_handler } }

    context 'auto_discovery = true (default)' do
      it { is_expected.to include event_handler }
      it { is_expected.to include declared_event_handler }
    end
    context 'auto_discovery = false' do
      before { Sequent.configure { |config| config.autodiscover_event_handlers = false } }
      it { is_expected.not_to include event_handler }
      it { is_expected.to include declared_event_handler }
    end
  end

  describe '#command_handlers' do
    subject { instance.all_command_handlers }

    let!(:command_handler) { Class.new(Sequent::Core::BaseCommandHandler) }

    let(:declared_command_handler) { Class.new }
    before { Sequent.configure { |c| c.command_handlers << declared_command_handler } }

    context 'auto_discovery = true (default)' do
      it { is_expected.to include command_handler }
      it { is_expected.to include declared_command_handler }
    end
    context 'auto_discovery = false' do
      before { Sequent.configure { |config| config.autodiscover_command_handlers = false } }
      it { is_expected.not_to include command_handler }
      it { is_expected.to include declared_command_handler }
    end
  end
end
