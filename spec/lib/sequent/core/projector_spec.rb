require 'spec_helper'

describe Sequent::Core::Projector do
  it 'fails when missing managed_tables' do
    class TestProjector1 < Sequent::Core::Projector

    end
    expect {
      Sequent.configuration.event_handlers << TestProjector1.new
    }.to raise_error /A Projector must manage at least one table/
  end
end
