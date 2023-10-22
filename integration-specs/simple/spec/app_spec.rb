# frozen_string_literal: true

require 'spec_helper'

describe 'app' do
  context 'registering comand handlers' do
    let(:command_handler_classes) { Sequent.configuration.command_handlers.map(&:class).sort_by(&:name) }

    it 'autoregisters command handlers' do
      expect(command_handler_classes).to eq [FirstCommandHandler, SecondCommandHandler]
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
end
