require 'spec_helper'
require 'sequent/test'

describe Sequent::Test::CommandHandlerHelpers::FakeEventStore do
  class Command < Sequent::Core::BaseCommand; end

  class CarCreated < Sequent::Core::Event; end
  class CarUpdated < Sequent::Core::Event; end
  class Car < Sequent::Core::AggregateRoot
    on CarCreated do

    end
  end

  class BikeCreated < Sequent::Core::Event; end
  class Bike < Sequent::Core::AggregateRoot
    on BikeCreated do

    end
  end

  let(:car_stream) { Sequent::Core::EventStream.new(aggregate_type: Car, aggregate_id: car_stream_id) }
  let(:car_created) { CarCreated.new(aggregate_id: car_stream_id, sequence_number: car_sequence_number) }
  let(:car_updated) { CarCreated.new(aggregate_id: car_stream_id, sequence_number: car_updated_sequence_number) }
  let(:car_sequence_number) { 1 }
  let(:car_updated_sequence_number) { car_sequence_number + 1 }

  let(:bike_stream) { Sequent::Core::EventStream.new(aggregate_type: Bike, aggregate_id: bike_stream_id) }
  let(:bike_created) { BikeCreated.new(aggregate_id: bike_stream_id, sequence_number: bike_sequence_number) }
  let(:bike_sequence_number) { 1 }

  let(:event_store) { Sequent::Test::CommandHandlerHelpers::FakeEventStore.new(strict_mode: strict_mode) }
  let(:command) { Command.new }

  context 'lenient mode' do
    let(:strict_mode) { false }
    let(:car_stream_id) { Sequent.new_uuid }

    let(:car_updated_sequence_number) {car_sequence_number}

    it 'does not care about uniqueness of sequence_numbers' do
      event_store.commit_events(command, [[car_stream, [car_created, car_updated]]])
    end
  end

  context 'scrict mode' do
    let(:strict_mode) { true }
    let(:car_stream_id) { Sequent.new_uuid }
    let(:bike_stream_id) { car_stream_id }

    context 'within the given event_stream' do
      context 'unique event streams' do
        it 'fails when aggregate id and type are not unique' do
          expect { event_store.commit_events(command, [[car_stream, [car_created]], [bike_stream, [bike_created]]]) }.to raise_error ActiveRecord::RecordNotUnique
        end
      end

      context 'non unique events' do
        let(:car_updated_sequence_number) { 1 }
        it 'fails when aggregate id and sequence_number are not unique' do
          expect { event_store.commit_events(command, [[car_stream, [car_created, car_updated]]]) }.to raise_error ActiveRecord::RecordNotUnique
        end
      end

      context 'unique events' do
        let(:car_updated_sequence_number) { 2 }
        it 'stores when aggregate id and sequence_number are unique' do
          event_store.commit_events(command, [[car_stream, [car_created, car_updated]]])
        end
      end
    end

    context 'with and existing aggregate id and type' do

      context 'when aggregate id and type are not unique' do
        it 'fails' do
          event_store.given_events [car_created]
          expect { event_store.commit_events(command, [[bike_stream, [bike_created]]]) }.to raise_error ActiveRecord::RecordNotUnique
        end
      end

      context 'when aggregate id and type are unique' do
        let(:bike_stream_id) { Sequent.new_uuid }

        it 'succeeds' do
          event_store.given_events [car_created]
          event_store.commit_events(command, [[bike_stream, [bike_created]]])
        end

        it 'can store a new event of an existing aggregate' do
          event_store.given_events [car_created]
          event_store.commit_events(command, [[car_stream, [car_updated]]])
        end
      end

      context 'non unique events' do
        let(:car_updated_sequence_number) { 1 }
        it 'fails when aggregate id and sequence_number are not unique' do
          event_store.given_events [car_created]
          expect { event_store.commit_events(command, [[car_stream, [car_updated]]]) }.to raise_error ActiveRecord::RecordNotUnique
        end
      end
    end
  end
end
