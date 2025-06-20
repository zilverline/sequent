# frozen_string_literal: true

require 'spec_helper'

describe Sequent::Core::Projector do
  MyProjectorTable = Class.new
  MyProjectorEvent = Class.new(Sequent::Core::Event)

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

  context 'projector activation' do
    def set_lock_timeout = ActiveRecord::Base.connection.execute("SET lock_timeout TO '10ms'")
    def update_projector_states = Sequent::Core::Projectors.register_active_projectors!([Sequent::Core::Projector], 1)
    def read_projector_states = Sequent::Core::Projectors.projector_states

    before do
      Sequent.configuration.enable_projector_states = true
      Sequent.activate_current_configuration!
    end
    after do
      Sequent.configuration.enable_projector_states = false
    end

    it 'waits for project state updates before reading' do
      reader_lock_attempted = Queue.new
      writer_locked = Queue.new
      writer = Thread.new do
        ActiveRecord::Base.transaction do
          update_projector_states
          writer_locked << 'locked states for reading'

          reader_lock_attempted.deq
        end
      end

      reader = Thread.new do
        ActiveRecord::Base.transaction do
          writer_locked.deq
          set_lock_timeout
          read_projector_states
          false
        rescue ActiveRecord::LockWaitTimeout
          true
        end
      end

      expect(reader.join(0.5).value).to be(true)
    ensure
      reader_lock_attempted << 'reader finished'
      writer.join(0.5).value
    end

    it 'waits for readers to when updating the projector states table' do
      writer_lock_attempted = Queue.new
      reader_locked = Queue.new
      reader = Thread.new do
        ActiveRecord::Base.transaction do
          read_projector_states
          reader_locked << 'locked states for reading'

          writer_lock_attempted.deq
        end
      end

      writer = Thread.new do
        ActiveRecord::Base.transaction do
          reader_locked.deq
          set_lock_timeout
          update_projector_states
        rescue ActiveRecord::LockWaitTimeout
          true
        end
      end

      expect(writer.join(0.5).value).to be(true)
    ensure
      writer_lock_attempted << 'writer finished'
      reader.join(0.5).value
    end
  end

  context 'forward methods' do
    let(:persistor) { double('persistor') }
    let(:record) { double('record') }
    let(:event) { MyProjectorEvent.new(aggregate_id: '1', sequence_number: 1) }
    let(:projector) do
      Class.new(Sequent::Core::Projector) do
        self.skip_autoregister = true
        manages_tables MyProjectorTable
      end.new(persistor)
    end
    context '#update_record' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:update_record).with(MyProjectorTable, event, {aggregate_id: '2'})
        projector.update_record(MyProjectorTable, event, {aggregate_id: '2'})

        expect(persistor).to receive(:update_record).with(
          MyProjectorTable,
          event,
          {aggregate_id: '2'},
          {update_sequence_number: false},
        )
        projector.update_record(MyProjectorTable, event, {aggregate_id: '2'}, {update_sequence_number: false})

        expect(persistor).to receive(:update_record).with(
          MyProjectorTable,
          event,
          {aggregate_id: '2'},
        ).and_yield(record)
        projector.update_record(MyProjectorTable, event, {aggregate_id: '2'}) do |record|
          expect(record).to eq record
        end
      end
    end
    context '#create_record' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:create_record).with(MyProjectorTable, {aggregate_id: '1'})
        projector.create_record(MyProjectorTable, {aggregate_id: '1'})

        expect(persistor).to receive(:create_record).with(MyProjectorTable, {aggregate_id: '1'}).and_yield(record)
        projector.create_record(MyProjectorTable, {aggregate_id: '1'}) do |record|
          expect(record).to eq record
        end
      end
    end
    context '#create_records' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:create_records).with(MyProjectorTable, [{aggregate_id: '1'}])
        projector.create_records(MyProjectorTable, [{aggregate_id: '1'}])
      end
    end
    context '#create_or_update_record' do
      let(:time) { Time.now }
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:create_or_update_record).with(MyProjectorTable, {aggregate_id: '1'}, time)
        projector.create_or_update_record(MyProjectorTable, {aggregate_id: '1'}, time)

        expect(persistor)
          .to receive(:create_or_update_record).with(MyProjectorTable, {aggregate_id: '1'}).and_yield(record)
        projector.create_or_update_record(MyProjectorTable, {aggregate_id: '1'}) do |record|
          expect(record).to eq record
        end
      end
    end
    context '#get_record!' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:get_record!).with(MyProjectorTable, {aggregate_id: '1'})
        projector.get_record!(MyProjectorTable, {aggregate_id: '1'})
      end
    end
    context '#get_record' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:get_record).with(MyProjectorTable, {aggregate_id: '1'})
        projector.get_record(MyProjectorTable, {aggregate_id: '1'})
      end
    end
    context '#delete_all_records' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:delete_all_records).with(MyProjectorTable, {aggregate_id: '1'})
        projector.delete_all_records(MyProjectorTable, {aggregate_id: '1'})
      end
    end
    context '#update_all_records' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:update_all_records).with(MyProjectorTable, {aggregate_id: '1'}, {name: 'bar'})
        projector.update_all_records(MyProjectorTable, {aggregate_id: '1'}, {name: 'bar'})
      end
    end
    context '#do_with_records' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:do_with_records).with(MyProjectorTable, {aggregate_id: '1'}).and_yield(record)
        projector.do_with_records(MyProjectorTable, {aggregate_id: '1'}) do |record|
          expect(record).to eq record
        end
      end
    end
    context '#do_with_record' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:do_with_record).with(MyProjectorTable, {aggregate_id: '1'}).and_yield(record)
        projector.do_with_record(MyProjectorTable, {aggregate_id: '1'}) do |record|
          expect(record).to eq record
        end
      end
    end
    context '#delete_record' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:delete_record).with(MyProjectorTable, record)

        projector.delete_record(MyProjectorTable, record)
      end
    end
    context '#find_records' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:find_records).with(MyProjectorTable, {name: 'foo'}).and_return([record])

        expect(projector.find_records(MyProjectorTable, {name: 'foo'})).to eq [record]
      end
    end
    context '#last_record' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:last_record).with(MyProjectorTable, {name: 'foo'}).and_return(record)

        expect(projector.last_record(MyProjectorTable, {name: 'foo'})).to eq record
      end
    end
    context '#commit' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:commit)

        projector.commit
      end
    end
    context '#execute_sql' do
      it 'forwards correctly to the persistor' do
        expect(persistor).to receive(:execute_sql).with('SELECT * FROM my_projector_table')

        projector.execute_sql('SELECT * FROM my_projector_table')
      end
    end
  end
end
