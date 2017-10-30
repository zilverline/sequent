require 'spec_helper'

class MockEvent < Sequent::Core::Event
  def initialize
    super(aggregate_id: 'foo', sequence_number: 1)
  end
end

describe Sequent::Core::RecordSessions::ReplayEventsSession do

  let(:session) { Sequent::Core::RecordSessions::ReplayEventsSession.new }
  let(:record_class) { Sequent::Core::EventRecord }
  let(:mock_event) { MockEvent.new }

  context '#get_record!' do
    it 'fails when no object is found' do
      expect { session.get_record!(record_class, {id: 1}) }.to raise_error(/record #{record_class} not found}*/)
    end
  end

  context '#update_record' do
    it 'fails when no object is found' do
      expect { session.update_record(record_class, mock_event, {id: 1}) }.to raise_error(/record #{record_class} not found}*/)
    end
  end

  context '#get_record' do
    it 'returns nil when no object is found' do
      expect(session.get_record(record_class, {id: 1})).to be_nil
    end
  end

  context '#find_records' do
    it 'returns empty array when no objects are found' do
      expect(session.find_records(record_class, {id: 1})).to be_empty
    end
  end

  context '#delete_all_records' do
    it 'does not fail when there is nothing to delete' do
      session.delete_all_records(record_class, {id: 1})
    end
  end

  context '#delete_record' do
    it 'does not fail when there is nothing to delete' do
      session.delete_record(record_class, record_class.new(id: 1))
    end
  end

  context '#update_all_records' do
    it 'does not fail when there is nothing to update' do
      session.update_all_records(record_class, {id: 1}, {sequence_number: 2})
    end
  end

  it 'can save multiple objects at once' do
    session.create_records(Sequent::Core::EventRecord, [{id: 1}, {id: 2}])
    object = session.get_record!(record_class, {id: 1})
    expect(object.id).to eq 1
    object = session.get_record!(record_class, {id: 2})
    expect(object.id).to eq 2
  end

  context 'with an object' do
    before :each do
      session.create_record(Sequent::Core::EventRecord, {id: 1})
    end

    context '#get_record!' do
      it 'returns the object' do
        object = session.get_record!(record_class, {id: 1})
        expect(object.id).to eq 1
      end

      context '#get_record' do
        it 'returns the object' do
          object = session.get_record(record_class, {id: 1})
          expect(object.id).to eq 1
        end
      end

      context '#find_records' do
        it 'returns the object' do
          objects = session.find_records(record_class, {id: 1})
          expect(objects).to have(1).item
          expect(objects.first.id).to eq 1
        end
      end

      context '#delete_all_records' do
        it 'deletes the object' do
          session.delete_all_records(record_class, {id: 1})

          objects = session.find_records(record_class, {id: 1})
          expect(objects).to be_empty
        end
      end

      context '#delete_record' do
        it 'deletes the object' do
          objects = session.find_records(record_class, {id: 1})
          session.delete_record(record_class, objects.first)

          expect(session.find_records(record_class, {id: 1})).to be_empty
        end
      end

      context '#update_all_records' do
        it 'updates the records' do
          session.update_all_records(record_class, {id: 1}, {sequence_number: 3})

          objects = session.find_records(record_class, {id: 1})
          expect(objects).to have(1).item
          expect(objects.first.id).to eq 1
          expect(objects.first.sequence_number).to eq 3
        end
      end
    end
  end

  context 'indices' do
    let(:aggregate_id) { Sequent.new_uuid }
    before :each do
      session.create_record(Sequent::Core::EventRecord, {id: 1, command_record_id: 2})
      session.create_record(Sequent::Core::EventRecord, {id: 1, sequence_number: 2})
      session.create_record(Sequent::Core::EventRecord, {aggregate_id: aggregate_id, id: 2})
    end

    let(:session) { Sequent::Core::RecordSessions::ReplayEventsSession.new(50, {
      Sequent::Core::EventRecord => [[:id, :command_record_id], [:id, :sequence_number]]
    }) }
    let(:records) { session.find_records(record_class, where_clause) }

    context '#find_records' do
      context 'with arbitrary where clause' do
        let(:where_clause) { {id: 1, command_record_id: 2} }
        it 'returns the correct number records' do
          expect(records).to have(1).item
        end

        it 'returns the correct record' do
          expect(records.first.id).to eq 1
          expect(records.first.command_record_id).to eq 2
          expect(records.first.sequence_number).to be_nil
        end
      end

      context 'on aggregate_id' do
        let(:where_clause) { {aggregate_id: aggregate_id} }

        it 'returns the correct number records' do
          expect(records).to have(1).item
        end

        it 'returns the correct record' do
          expect(records.first.aggregate_id).to eq aggregate_id
        end
      end
    end

    context '#delete_all_records' do
      it 'deletes the object based on single column' do
        expect(session.find_records(record_class, {id: 1})).to have(2).items

        session.delete_all_records(record_class, {id: 1})

        expect(session.find_records(record_class, {id: 1})).to be_empty
      end

      it 'deletes the object based on multiple columns' do
        expect(session.find_records(record_class, {id: 1, command_record_id: 2})).to have(1).item

        session.delete_all_records(record_class, {id: 1, command_record_id: 2})

        expect(session.find_records(record_class, {id: 1, command_record_id: 2})).to be_empty
        expect(session.find_records(record_class, {id: 1, sequence_number: 2})).to have(1).item
      end
    end

    context '#update_all_records' do
      it 'only updates the records adhering to the where clause' do
        session.update_all_records(record_class, {id: 1, sequence_number: 2}, {command_record_id: 10})

        object = session.get_record!(record_class, {id: 1, sequence_number: 2})
        expect(object.id).to eq 1
        expect(object.command_record_id).to eq 10
      end

      it 'can update an indexed column' do
        session.update_all_records(record_class, {id: 1, sequence_number: 2}, {sequence_number: 99})

        expect(session.get_record(record_class, {id: 1, sequence_number: 2})).to be_nil

        object = session.get_record!(record_class, {id: 1, sequence_number: 99})
        expect(object.id).to eq 1
        expect(object.sequence_number).to eq 99
      end
    end
  end
end
