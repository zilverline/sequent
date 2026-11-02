# frozen_string_literal: true

require 'spec_helper'

class GuardedProjectionRecord < Sequent::ApplicationRecord
  include Sequent::Core::ProjectionRecord
end

class UnguardedRecord < Sequent::ApplicationRecord; end

class GuardedRecordAdded < Sequent::Core::Event
  attrs name: String
end

class AddGuardedRecord < Sequent::Core::Command
  attrs name: String
end

class WriteGuardedRecordDirectly < Sequent::Core::Command; end

class GuardedRecordAggregate < Sequent::Core::AggregateRoot
  def initialize(id, name)
    super(id)
    apply GuardedRecordAdded, name:
  end
end

class GuardedRecordCommandHandler < Sequent::Core::BaseCommandHandler
  on AddGuardedRecord do |command|
    repository.add_aggregate(GuardedRecordAggregate.new(command.aggregate_id, command.name))
  end

  on WriteGuardedRecordDirectly do |command|
    GuardedProjectionRecord.create!(aggregate_id: command.aggregate_id, name: 'direct')
  end
end

class GuardedRecordProjector < Sequent::Core::Projector
  self.skip_autoregister = true
  manages_tables GuardedProjectionRecord

  on GuardedRecordAdded do |event|
    create_record(GuardedProjectionRecord, aggregate_id: event.aggregate_id, name: event.name)
  end
end

class GuardedRecordWorkflow < Sequent::Core::Workflow
  self.skip_autoregister = true

  on GuardedRecordAdded do |event|
    if event.name == 'workflow'
      GuardedProjectionRecord.where(aggregate_id: event.aggregate_id).update_all(name: 'workflow')
    end
  end
end

describe Sequent::Core::ProjectionWrites do
  let(:aggregate_id) { Sequent.new_uuid }

  before do
    exec_sql(<<~SQL)
      DROP TABLE IF EXISTS guarded_projection_records, unguarded_records;
      CREATE TABLE guarded_projection_records (id bigserial PRIMARY KEY, aggregate_id uuid, name character varying);
      CREATE TABLE unguarded_records (id bigserial PRIMARY KEY, name character varying);
    SQL
    GuardedProjectionRecord.reset_column_information
    UnguardedRecord.reset_column_information
  end

  after { exec_sql('DROP TABLE IF EXISTS guarded_projection_records, unguarded_records') }

  describe 'the state' do
    it 'forbids writing by default' do
      expect(described_class).not_to be_allowed
    end

    it 'allows writing in a block, except where it is forbidden again or a projector writes' do
      described_class.allow do
        expect(described_class).to be_allowed
        described_class.forbid do
          expect(described_class).not_to be_allowed
          described_class.during_projection { expect(described_class).to be_allowed }
          expect(described_class).not_to be_allowed
        end
        expect(described_class).to be_allowed
      end
      expect(described_class).not_to be_allowed
    end

    it 'restores the state when the block fails' do
      expect { described_class.allow { fail 'failed' } }.to raise_error('failed')

      expect(described_class).not_to be_allowed
    end
  end

  describe Sequent::Core::ProjectionRecord do
    it 'cannot save, update or destroy records unless allowed' do
      expect { GuardedProjectionRecord.create!(name: 'a') }.to raise_error(ActiveRecord::ReadOnlyRecord)

      record = Sequent::Core::ProjectionWrites.allow { GuardedProjectionRecord.create!(name: 'a') }

      expect { record.update!(name: 'b') }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect { record.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
      expect(GuardedProjectionRecord.pluck(:name)).to eq ['a']
    end

    it 'cannot write records without instantiating them unless allowed' do
      forbidden = Sequent::Core::ProjectionWrites::ForbiddenError
      expect { GuardedProjectionRecord.insert_all!([{name: 'a'}]) }.to raise_error(forbidden, /GuardedProjectionRecord/)
      expect { GuardedProjectionRecord.upsert_all([{id: 1, name: 'a'}]) }.to raise_error(forbidden)
      expect { GuardedProjectionRecord.where(name: 'a').update_all(name: 'b') }.to raise_error(forbidden)
      expect { GuardedProjectionRecord.delete_all }.to raise_error(forbidden)

      Sequent::Core::ProjectionWrites.allow { GuardedProjectionRecord.insert_all!([{name: 'a'}]) }

      expect(GuardedProjectionRecord.pluck(:name)).to eq ['a']
    end

    it 'cannot delete records unless allowed' do
      forbidden = Sequent::Core::ProjectionWrites::ForbiddenError
      record = Sequent::Core::ProjectionWrites.allow { GuardedProjectionRecord.create!(name: 'a') }

      expect { record.delete }.to raise_error(forbidden, /GuardedProjectionRecord/)
      expect { GuardedProjectionRecord.delete(record.id) }.to raise_error(forbidden)
      expect(GuardedProjectionRecord.count).to eq 1

      Sequent::Core::ProjectionWrites.during_projection { record.delete }

      expect(GuardedProjectionRecord.count).to eq 0
    end

    it 'does not guard other records' do
      UnguardedRecord.create!(name: 'a')
      UnguardedRecord.insert_all!([{name: 'b'}])
      UnguardedRecord.where(name: 'a').update_all(name: 'c')

      expect(UnguardedRecord.order(:name).pluck(:name)).to eq %w[b c]
    end
  end

  describe '.ensure_no_write_callbacks!' do
    def projection_record_class(&block)
      Class.new(Sequent::ApplicationRecord) do
        self.table_name = 'guarded_projection_records'
        include Sequent::Core::ProjectionRecord

        class_eval(&block) if block
      end
    end

    def write_callbacks(&block) = Sequent::Core::ProjectionRecord.write_callbacks(projection_record_class(&block))

    it 'accepts a record class without callbacks, with associations and callbacks that run when reading' do
      record_class = projection_record_class do
        has_many :others, class_name: 'GuardedProjectionRecord', foreign_key: :aggregate_id, primary_key: :aggregate_id
        has_one :other, class_name: 'GuardedProjectionRecord', foreign_key: :aggregate_id, primary_key: :aggregate_id
        after_find { nil }
        after_initialize { nil }
      end

      expect { Sequent::Core::ProjectionRecord.ensure_no_write_callbacks!(record_class) }.not_to raise_error
    end

    it 'describes the callbacks that run when writing and the validations' do
      expect(write_callbacks { before_save :normalize_name }).to eq ['before_save normalize_name']
      expect(write_callbacks { after_commit { nil } }).to eq ['after_commit (block)']
      expect(write_callbacks { validates :name, presence: true })
        .to eq ['ActiveRecord::Validations::PresenceValidator name']
      expect(write_callbacks { belongs_to :parent, class_name: 'GuardedProjectionRecord', optional: false }).to eq [
        'ActiveRecord::Validations::PresenceValidator parent',
      ]
    end

    it 'fails a projector that manages a record class with such callbacks' do
      record_class = projection_record_class { before_save :normalize_name }

      expect do
        Class.new(Sequent::Core::Projector) { manages_tables record_class }
      end.to raise_error(Sequent::Core::ProjectionRecord::WriteCallbacksError, /before_save normalize_name/)
    end

    it 'does not check record classes that are not projection records' do
      record_class = Class.new(Sequent::ApplicationRecord) do
        self.table_name = 'unguarded_records'
        before_save :normalize_name
      end

      expect { Class.new(Sequent::Core::Projector) { manages_tables record_class } }.not_to raise_error
    end
  end

  context 'with a projector' do
    let(:projector) { GuardedRecordProjector.new }

    it 'writes the records of its projection' do
      projector.create_record(GuardedProjectionRecord, aggregate_id:, name: 'a')
      projector.update_all_records(GuardedProjectionRecord, {aggregate_id:}, {name: 'b'})
      projector.update_record(GuardedProjectionRecord, GuardedRecordAdded.new(aggregate_id:, sequence_number: 1)) do |r|
        r.name = 'c'
      end

      expect(GuardedProjectionRecord.pluck(:name)).to eq ['c']

      projector.delete_all_records(GuardedProjectionRecord, aggregate_id:)

      expect(GuardedProjectionRecord.count).to eq 0
    end
  end

  context 'when executing commands' do
    before do
      Sequent.configuration.command_handlers << GuardedRecordCommandHandler.new
      Sequent.configuration.event_handlers << GuardedRecordProjector.new << GuardedRecordWorkflow.new
    end

    around { |example| described_class.allow { example.run } }

    it 'lets the projectors write the records of their projections' do
      Sequent.command_service.execute_commands AddGuardedRecord.new(aggregate_id:, name: 'a')

      expect(GuardedProjectionRecord.pluck(:name)).to eq ['a']
    end

    it 'does not let a command handler write the records of a projection' do
      expect do
        Sequent.command_service.execute_commands WriteGuardedRecordDirectly.new(aggregate_id:)
      end.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it 'does not let a workflow write the records of a projection' do
      expect do
        Sequent.command_service.execute_commands AddGuardedRecord.new(aggregate_id:, name: 'workflow')
      end.to raise_error(Sequent::Core::EventPublisher::PublishEventError) { |error|
        expect(error.cause).to be_a Sequent::Core::ProjectionWrites::ForbiddenError
      }
    end

    it 'allows writing again after executing the commands' do
      Sequent.command_service.execute_commands AddGuardedRecord.new(aggregate_id:, name: 'a')

      expect(described_class).to be_allowed
      GuardedProjectionRecord.update_all(name: 'b')
    end
  end
end
