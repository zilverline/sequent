# frozen_string_literal: true

require 'spec_helper'

class LifetimeRecord < Sequent::ApplicationRecord; end

class LifetimeRecordAdded < Sequent::Core::Event
  attrs name: String
end

class LifetimeRecordRenamed < Sequent::Core::Event
  attrs name: String
end

class LifetimeUnhandledEvent < Sequent::Core::Event; end

class LifetimeProjector < Sequent::Core::Projector
  self.lifetime = :batch
  manages_tables LifetimeRecord

  class << self
    attr_accessor :instances
  end

  def initialize(...)
    super
    self.class.instances << self
  end

  def default_persistor = Sequent::Core::Persistors::BufferedPersistor.new

  on LifetimeRecordAdded do |event|
    create_record(LifetimeRecord, aggregate_id: event.aggregate_id, name: event.name)
  end

  on LifetimeRecordRenamed do |event|
    update_all_records(LifetimeRecord, {aggregate_id: event.aggregate_id}, {name: event.name})
  end
end

class LifetimeWorkflow < Sequent::Core::Workflow
  class << self
    attr_accessor :names
  end

  on LifetimeRecordRenamed do |event|
    fail 'renamed to fail' if event.name == 'fail'

    self.class.names << LifetimeRecord.where(aggregate_id: event.aggregate_id).pluck(:name).sole
  end
end

describe Sequent::Core::Helpers::EventHandlers do
  let(:aggregate_id) { Sequent.new_uuid }
  let(:publisher) { Sequent::Core::EventPublisher.new }

  before do
    exec_sql(<<~SQL)
      DROP TABLE IF EXISTS lifetime_records;
      CREATE TABLE lifetime_records (aggregate_id uuid NOT NULL, name character varying NOT NULL);
    SQL
    LifetimeRecord.reset_column_information
    LifetimeProjector.instances = []
    LifetimeWorkflow.names = []
    Sequent.configuration.event_handlers = [LifetimeProjector]
  end

  after { exec_sql('DROP TABLE IF EXISTS lifetime_records') }

  def event(event_class, sequence_number, **attributes)
    event_class.new(aggregate_id:, sequence_number:, **attributes)
  end

  def statements(pattern)
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      statements << payload[:sql] if payload[:sql].match?(pattern)
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  context 'with the batch lifetime' do
    it 'creates an instance for every batch of events' do
      publisher.publish_events([event(LifetimeRecordAdded, 1, name: 'a')])
      publisher.publish_events([event(LifetimeRecordRenamed, 2, name: 'b')])

      expect(LifetimeProjector.instances.size).to eq 2
      expect(LifetimeProjector.instances.uniq.size).to eq 2
    end

    it 'does not create an instance for events it does not handle' do
      publisher.publish_events([event(LifetimeUnhandledEvent, 1)])

      expect(LifetimeProjector.instances).to be_empty
    end

    it 'flushes the changes of the projectors after the batch, combining their statements' do
      events = [
        event(LifetimeRecordAdded, 1, name: 'a'),
        event(LifetimeRecordRenamed, 2, name: 'b'),
        event(LifetimeRecordRenamed, 3, name: 'c'),
      ]

      updates = statements(/\AUPDATE/) { publisher.publish_events(events) }

      expect(LifetimeRecord.pluck(:name)).to eq ['c']
      expect(updates.size).to eq 1
    end

    it 'flushes the changes of the projectors before another event handler handles an event' do
      Sequent.configuration.event_handlers = [LifetimeProjector, LifetimeWorkflow.new]

      publisher.publish_events(
        [
          event(LifetimeRecordAdded, 1, name: 'a'),
          event(LifetimeRecordRenamed, 2, name: 'b'),
          event(LifetimeRecordRenamed, 3, name: 'c'),
        ],
      )

      expect(LifetimeWorkflow.names).to eq %w[b c]
    end

    it 'discards the changes of a batch that fails' do
      Sequent.configuration.event_handlers = [LifetimeProjector, LifetimeWorkflow.new]

      expect do
        publisher.publish_events(
          [event(LifetimeRecordAdded, 1, name: 'a'), event(LifetimeRecordRenamed, 2, name: 'fail')],
        )
      end.to raise_error(Sequent::Core::EventPublisher::PublishEventError)
      LifetimeRecord.delete_all
      publisher.publish_events([event(LifetimeRecordAdded, 3, name: 'b')])

      expect(LifetimeRecord.pluck(:name)).to eq ['b']
    end

    it 'skips inactive projectors with the ActiveProjectorsEventPublisher' do
      Sequent::Core::ProjectorState.delete_all
      Sequent::Core::Projectors.register_replaying_projectors!([LifetimeProjector])

      Sequent.configuration.transaction_provider.transaction do
        Sequent::Core::ActiveProjectorsEventPublisher.new.publish_events([event(LifetimeRecordAdded, 1, name: 'a')])
      end

      expect(LifetimeProjector.instances).to be_empty
      expect(LifetimeRecord.count).to eq 0
    ensure
      Sequent::Core::ProjectorState.delete_all
    end
  end

  describe '.ensure_valid!' do
    let(:singleton_projector) do
      Class.new(Sequent::Projector) do
        self.skip_autoregister = true
        manages_no_tables
      end
    end
    let(:batch_projector) do
      Class.new(Sequent::Projector) do
        self.skip_autoregister = true
        self.lifetime = :batch
        manages_no_tables
      end
    end

    it 'accepts singleton instances and batch classes' do
      expect { described_class.ensure_valid!([singleton_projector.new, batch_projector]) }.not_to raise_error
    end

    it 'fails for a registered singleton class' do
      expect { described_class.ensure_valid!([singleton_projector]) }
        .to raise_error(ArgumentError, /registered as a class, so it must have the batch lifetime/)
    end

    it 'fails for a registered instance of a batch class' do
      expect { described_class.ensure_valid!([batch_projector.new]) }
        .to raise_error(ArgumentError, /has the batch lifetime, so register the class/)
    end

    it 'fails for a registered projector instance with a BufferedPersistor' do
      projector = singleton_projector.new(Sequent::Core::Persistors::BufferedPersistor.new)

      expect { described_class.ensure_valid!([projector]) }
        .to raise_error(ArgumentError, /uses a BufferedPersistor/)
    end

    it 'fails for an unknown lifetime' do
      batch_projector.lifetime = :transaction

      expect { described_class.ensure_valid!([batch_projector]) }
        .to raise_error(ArgumentError, /lifetime :transaction of .* is not one of :singleton, :batch/)
    end
  end
end
