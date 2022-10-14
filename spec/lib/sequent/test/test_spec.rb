# frozen_string_literal: true

require 'spec_helper'
require 'sequent/test/workflow_helpers'

RSpec.configure do |config|
  config.include Sequent::Test::CommandHandlerHelpers
  config.include Sequent::Test::WorkflowHelpers, workflows: true
end

describe 'Test Helpers' do
  after do
    # assert that sequent configuration is correctly reset after tagged group
    expect(Sequent.command_service.class).to_not eq(Sequent::Test::WorkflowHelpers::FakeCommandService)
  end

  let(:spec) { double }

  it 'fails then trying to include without WorkflowHelpers without metadata argument workflows' do
    allow(spec).to receive(:metadata).and_return({})

    expect do
      Sequent::Test::WorkflowHelpers.included(spec)
    end.to raise_error(/Missing metadata argument `workflows: true` when including Sequent::Test::WorkflowHelpers/)
  end

  context Sequent::Test::WorkflowHelpers, workflows: true do
    it 'uses the FakeCommandService in specs tagged with workflows' do
      expect(Sequent.command_service.class).to eq(Sequent::Test::WorkflowHelpers::FakeCommandService)
    end
  end

  context Sequent::Test::CommandHandlerHelpers do
    it 'does not conflict with Sequent::Test::WorkflowHelpers' do
      expect(Sequent.command_service.class).to eq(Sequent::Core::CommandService)
    end
  end
end
