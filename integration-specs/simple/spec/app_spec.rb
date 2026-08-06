# frozen_string_literal: true

require 'spec_helper'

describe 'app' do
  context 'registering command handlers' do
    let(:command_handler_classes) { Sequent.configuration.command_handlers.map(&:class).sort_by(&:name) }

    it 'autoregisters command handlers' do
      expect(command_handler_classes).to eq [
        FirstCommandHandler,
        SecondCommandHandler,
        Sequent::Core::AggregateSnapshotter,
      ]
    end
  end

  context 'registering projectors and workflows' do
    let(:event_handler_classes) { Sequent.configuration.event_handlers.map(&:class).sort_by(&:name) }
    it 'autoregisters events handlers' do
      expect(event_handler_classes).to eq [
        FirstProjector,
        FirstWorkflow,
        ManualProjector,
        ManualWorkflow,
        SecondProjector,
      ]
    end
  end

  context 'registering aggregate observers' do
    let(:aggregate_observer_classes) { Sequent.configuration.aggregate_observers.map(&:class).sort_by(&:name) }
    it 'autoregisters' do
      expect(aggregate_observer_classes).to eq [
        FirstAggregateObserver,
        SecondAggregateObserver,
      ]
    end
  end

  context 'with a monkey patched Rails module' do
    before do
      module Rails; end
    end

    it 'can autoregister' do
      Sequent.configure do |config|
        config.enable_autoregistration = true
      end
    end
  end
end
