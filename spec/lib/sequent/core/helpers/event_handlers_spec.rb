# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Helpers::EventHandlers do
  def projector_class(&block)
    Class.new(Sequent::Projector) do
      self.skip_autoregister = true
      manages_no_tables
      class_eval(&block) if block
    end
  end

  let(:inline_projector) { projector_class }
  let(:bulk_projector) { projector_class { self.phase = :bulk } }
  let(:batch_projector) { projector_class { self.lifetime = :batch } }
  let(:workflow) { Class.new(Sequent::Workflow) { self.skip_autoregister = true } }

  describe '.lifetime' do
    it 'is singleton by default' do
      expect(described_class.lifetime(inline_projector)).to eq :singleton
      expect(described_class.lifetime(workflow)).to eq :singleton
    end

    it 'is batch by default in the bulk phase' do
      expect(described_class.lifetime(bulk_projector)).to eq :batch
    end

    it 'is the lifetime of the event handler class' do
      expect(described_class.lifetime(batch_projector)).to eq :batch
      singleton_bulk_projector = projector_class do
        self.phase = :bulk
        self.lifetime = :singleton
      end
      expect(described_class.lifetime(singleton_bulk_projector)).to eq :singleton
    end

    it 'fails for an unknown lifetime' do
      batch_projector.lifetime = :transaction

      expect { described_class.lifetime(batch_projector) }
        .to raise_error(ArgumentError, /lifetime :transaction of .* is not one of :singleton, :batch/)
    end
  end

  describe '.registration' do
    it 'is an instance for the singleton lifetime and the class for the batch lifetime' do
      expect(described_class.registration(inline_projector)).to be_a inline_projector
      expect(described_class.registration(bulk_projector)).to eq bulk_projector
    end
  end

  describe '.ensure_valid!' do
    it 'accepts singleton instances and batch classes' do
      expect { described_class.ensure_valid!([inline_projector.new, workflow.new, bulk_projector, batch_projector]) }
        .not_to raise_error
    end

    it 'fails for a registered singleton class' do
      expect { described_class.ensure_valid!([inline_projector]) }
        .to raise_error(ArgumentError, /registered as a class, so it must have the batch lifetime/)
    end

    it 'fails for a registered instance of a batch class' do
      expect { described_class.ensure_valid!([bulk_projector.new]) }
        .to raise_error(ArgumentError, /has the batch lifetime, so register the class/)
    end
  end

  describe 'autoregistration' do
    let!(:autoregistered_inline_projector) { Class.new(Sequent::Projector) { manages_no_tables } }
    let!(:autoregistered_bulk_projector) do
      Class.new(Sequent::Projector) do
        self.phase = :bulk
        manages_no_tables
      end
    end

    it 'registers an instance or the class depending on the lifetime' do
      Sequent.configure do |config|
        config.event_handlers = []
        config.enable_autoregistration = true
      end

      expect(Sequent.configuration.event_handlers.map(&:class)).to include(autoregistered_inline_projector)
      expect(Sequent.configuration.event_handlers).to include(autoregistered_bulk_projector)
    end
  end
end
