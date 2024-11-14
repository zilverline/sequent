# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Projector do
  it 'fails when missing managed_tables' do
    class TestProjector1 < Sequent::Core::Projector
      self.skip_autoregister = true
    end
    expect do
      Sequent.configuration.event_handlers << TestProjector1.new
    end.to raise_error(/A Projector must manage at least one table/)
  end
end
