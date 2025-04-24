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

  it "'fails when passing in a record_class to the persistor that isn't managed by this projector" do
    MyOtherProjectorTable = Class.new

    MyProjectorTable = Class.new
    MyProjectorEvent = Class.new(Sequent::Core::Event)
    expect do
      Class
        .new(Sequent::Core::Projector) do
          self.skip_autoregister = true

          manages_tables MyProjectorTable

          on MyProjectorEvent do
            update_all_records(MyOtherProjectorTable, {}, {})
          end
        end
        .new
        .handle_message(MyProjectorEvent.new(aggregate_id: '1', sequence_number: 1))
    end.to raise_error(Sequent::Core::Projector::NotManagedByThisProjector)
  end
end
