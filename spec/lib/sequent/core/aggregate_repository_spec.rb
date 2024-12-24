# frozen_string_literal: true

require 'spec_helper'

require 'securerandom'

describe Sequent::Core::AggregateRepository do
  context 'Aggregate repository unit tests' do
    class DummyAggregate < Sequent::Core::AggregateRoot
      attr_reader :loaded_events
      attr_writer :uncommitted_events

      def load_from_history(stream, events)
        super
        @event_stream = stream
        @loaded_events = events
      end
    end

    class DummyAggregate2 < Sequent::Core::AggregateRoot
      attr_reader :loaded_events
      attr_writer :uncommitted_events

      def load_from_history(stream, events)
        super
        @event_stream = stream
        @loaded_events = events
      end
    end

    before do
      Sequent.configuration.event_store = event_store
      repository.clear
    end
    after do
      repository.clear
    end

    let(:event_store) { double }
    let(:repository) { Sequent.configuration.aggregate_repository }
    let(:aggregate) { DummyAggregate.new(Sequent.new_uuid) }
    let(:events) do
      [Sequent::Core::Event.new(aggregate_id: aggregate.id, sequence_number: 1)]
    end

    it 'should track added aggregates by id' do
      allow(event_store).to receive(:load_events_for_aggregates).with([]).and_return([]).once

      repository.add_aggregate aggregate
      expect(repository.load_aggregate(aggregate.id, DummyAggregate)).to be(aggregate)
    end

    it 'should load an aggregate from the event store' do
      allow(event_store).to receive(:load_events_for_aggregates).with([:id]).and_return(
        [
          [
            aggregate.event_stream,
            events,
          ],
        ],
      )

      loaded = repository.load_aggregate(:id, DummyAggregate)

      expect(loaded.event_stream).to eq(aggregate.event_stream)
      expect(loaded.loaded_events).to eq(events)
    end

    it 'should not require expected aggregate class' do
      allow(event_store).to receive(:load_events_for_aggregates).with([:id]).and_return(
        [
          [
            aggregate.event_stream,
            events,
          ],
        ],
      )
      loaded = repository.load_aggregate(:id)
      expect(loaded.class).to eq(DummyAggregate)
    end

    it 'should load a subclass aggregate' do
      allow(event_store).to receive(:load_events_for_aggregates).with([:id]).and_return(
        [
          [
            aggregate.event_stream,
            events,
          ],
        ],
      )
      loaded = repository.load_aggregate(:id, Sequent::Core::AggregateRoot)
      expect(loaded.class).to be < Sequent::Core::AggregateRoot
    end

    it 'should fail when the expected type does not match the stored type' do
      allow(event_store).to receive(:load_events_for_aggregates).with([:id]).and_return(
        [
          [
            aggregate.event_stream,
            events,
          ],
        ],
      )
      expect { repository.load_aggregate(:id, Integer) }.to raise_error TypeError
    end

    it 'should commit and clear events from aggregates in the identity map' do
      repository.add_aggregate aggregate
      aggregate.uncommitted_events = [:event]
      allow(event_store).to receive(:commit_events).with(:command, [[aggregate.event_stream, [:event]]]).once

      repository.commit(:command)

      expect(aggregate.uncommitted_events).to be_empty
    end

    context 'clear!' do
      it 'fails when uncommitted events are present' do
        repository.add_aggregate aggregate
        aggregate.uncommitted_events = [:event]

        expect { repository.clear! }.to raise_error Sequent::Core::AggregateRepository::HasUncommittedEvents
        expect(Thread.current[Sequent::Core::AggregateRepository::AGGREGATES_KEY]).to_not be_nil
      end

      it 'clears unit of work when no uncommitted events' do
        repository.add_aggregate aggregate

        expect { repository.clear! }.to_not raise_error
        expect(Thread.current[Sequent::Core::AggregateRepository::AGGREGATES_KEY]).to be_nil
      end
    end

    it 'should return aggregates from the identity map after loading from the event store' do
      allow(event_store).to receive(:load_events_for_aggregates).with([aggregate.id]).and_return(
        [
          [
            aggregate.event_stream, events
          ],
        ],
      ).once
      allow(event_store).to receive(:load_events_for_aggregates).with([]).and_return([]).once

      a = repository.load_aggregate(aggregate.id, DummyAggregate)
      b = repository.load_aggregate(aggregate.id, DummyAggregate)
      expect(a).to equal(b)
    end

    it 'should check type when returning aggregate from identity map' do
      allow(event_store).to receive(:load_events_for_aggregates).with([]).and_return([]).once

      repository.add_aggregate aggregate
      expect { repository.load_aggregate(aggregate.id, String) }.to raise_error { |error|
        expect(error).to be_a TypeError
      }
    end

    it 'should prevent different aggregates with the same id from being added' do
      another = DummyAggregate.new(aggregate.id)

      repository.add_aggregate aggregate
      expect do
        repository.add_aggregate another
      end.to raise_error Sequent::Core::AggregateRepository::NonUniqueAggregateId
    end

    it 'should indicate if a aggregate exists' do
      allow(event_store).to receive(:load_events_for_aggregates).with([]).and_return([]).once

      repository.add_aggregate aggregate
      expect(repository.ensure_exists(aggregate.id, DummyAggregate)).to be_truthy
    end

    it 'should raise exception if a aggregate does not exists' do
      expect { repository.ensure_exists(:foo, InvoiceCreatedEvent) }.to raise_exception NameError
    end

    it 'contains an aggregate' do
      allow(event_store).to receive(:stream_exists?).with(aggregate.id).and_return(true)
      allow(event_store).to receive(:events_exists?).with(aggregate.id).and_return(true)

      expect(repository.contains_aggregate?(aggregate.id)).to eq(true)
    end

    it 'does not contain an aggregate' do
      allow(event_store).to receive(:stream_exists?).with(aggregate.id).and_return(false)

      expect(repository.contains_aggregate?(aggregate.id)).to eq(false)
    end

    describe '#load_aggregate_for_snapshotting' do
      class MyEvent < Sequent::Core::Event
      end

      context 'without snapshot events' do
        let(:event_1) { MyEvent.new(aggregate_id: aggregate.id, sequence_number: 1) }
        let(:aggregate_stream_with_events) { [aggregate.event_stream, event_1] }

        it 'returns the stream' do
          allow(event_store).to receive(:find_event_stream)
            .with(aggregate.id).and_return(aggregate.event_stream)

          allow(event_store).to receive(:stream_events_for_aggregate)
            .with(aggregate.id, load_until: nil)
            .and_return(aggregate_stream_with_events)

          loaded_aggregate = repository.load_aggregate_for_snapshotting(aggregate.id)
          loaded_aggregate.stream_from_history(aggregate_stream_with_events)

          expect(loaded_aggregate.event_stream).to eq(aggregate.event_stream)
        end
      end
    end

    describe '#load_aggregates' do
      context 'arguments' do
        it 'fails when aggregate_ids is nil' do
          expect { repository.load_aggregates(nil) }.to raise_error ArgumentError
        end

        it 'returns an empty list when aggregate_ids is empty ' do
          expect(repository.load_aggregates([])).to be_empty
        end
      end

      context 'with an empty store' do
        it 'raises an error when nothing is found' do
          allow(event_store).to receive(:load_events_for_aggregates).with([aggregate.id]).and_return([]).once

          expect do
            repository.load_aggregates([aggregate.id])
          end.to raise_error Sequent::Core::AggregateRepository::AggregateNotFound
        end
      end

      context 'with aggregates in the event store' do
        let(:aggregate_stream_with_events) { [aggregate.event_stream, events] }

        let(:aggregate_2) { DummyAggregate.new(Sequent.new_uuid) }
        let(:events_2) { [Sequent::Core::Event.new(aggregate_id: aggregate_2.id, sequence_number: 1)] }
        let(:aggregate_2_stream_with_events) { [aggregate_2.event_stream, events_2] }

        let(:aggregate_3) { DummyAggregate2.new(Sequent.new_uuid) }
        let(:events_3) { [Sequent::Core::Event.new(aggregate_id: aggregate_3.id, sequence_number: 1)] }
        let(:aggregate_3_stream_with_events) { [aggregate_3.event_stream, events_3] }

        it 'returns all the aggregates found' do
          allow(event_store)
            .to(
              receive(:load_events_for_aggregates)
                .with([aggregate.id, aggregate_2.id])
                .and_return([aggregate_stream_with_events, aggregate_2_stream_with_events])
                .once,
            )

          aggregates = repository.load_aggregates([aggregate.id, aggregate_2.id])
          expect(aggregates).to have(2).items

          expect(aggregates[0].event_stream).to eq aggregate.event_stream
          expect(aggregates[0].loaded_events).to eq(events)

          expect(aggregates[1].event_stream).to eq aggregate_2.event_stream
          expect(aggregates[1].loaded_events).to eq(events_2)
        end

        it 'raises error even if only one aggregate cannot be found' do
          allow(event_store).to(
            receive(:load_events_for_aggregates)
            .with([aggregate.id, :foo])
            .and_return([aggregate_stream_with_events])
            .once,
          )

          expect do
            repository.load_aggregates(
              [
                aggregate.id,
                :foo,
              ],
            )
          end.to raise_error(
            Sequent::Core::AggregateRepository::AggregateNotFound,
            'Aggregate with id [:foo] not found',
          )
        end

        it 'can handle duplicate input for load_aggregates' do
          allow(event_store).to(
            receive(:load_events_for_aggregates)
            .with([aggregate.id])
            .and_return([aggregate_stream_with_events])
            .once,
          )

          aggregates = repository.load_aggregates([aggregate.id, aggregate.id])
          expect(aggregates).to have(1).items
        end

        it 'fails if one if the aggregates in the identity map is of incorrect type' do
          allow(event_store)
            .to(
              receive(:load_events_for_aggregates)
                .with([aggregate.id])
                .and_return([aggregate_stream_with_events])
                .once,
            )

          expect { repository.load_aggregates([aggregate.id], Integer) }.to raise_error TypeError
        end

        it 'fails if one if the aggregates in the events store is not of the requested type' do
          allow(event_store)
            .to(
              receive(:load_events_for_aggregates)
                .with([aggregate.id, aggregate_3.id])
                .and_return([aggregate_stream_with_events, aggregate_3_stream_with_events])
                .once,
            )

          expect { repository.load_aggregates([aggregate.id, aggregate_3.id], DummyAggregate) }.to raise_error TypeError
        end

        it 'can return multiple aggregates of different types' do
          allow(event_store)
            .to(
              receive(:load_events_for_aggregates)
                .with([aggregate.id, aggregate_3.id])
                .and_return([aggregate_stream_with_events, aggregate_3_stream_with_events])
                .once,
            )

          aggregates = repository.load_aggregates([aggregate.id, aggregate_3.id])
          expect(aggregates).to have(2).items

          expect(aggregates[0].event_stream).to eq aggregate.event_stream
          expect(aggregates[0].loaded_events).to eq(events)

          expect(aggregates[1].class).to eq DummyAggregate2
          expect(aggregates[1].event_stream).to eq aggregate_3.event_stream
          expect(aggregates[1].loaded_events).to eq(events_3)
        end

        context 'loaded in the identity map' do
          before :each do
            allow(event_store).to receive(:load_events_for_aggregates).with([]).and_return([]).once
          end

          it 'does not query the event store again' do
            allow(event_store)
              .to(
                receive(:load_events_for_aggregates)
                  .with([aggregate.id, aggregate_2.id])
                  .and_return([aggregate_stream_with_events, aggregate_2_stream_with_events])
                  .once,
              )

            aggregates_1 = repository.load_aggregates([aggregate.id, aggregate_2.id])
            aggregates_2 = repository.load_aggregates([aggregate.id, aggregate_2.id])

            expect(aggregates_1[0]).to equal(aggregates_2[0])
            expect(aggregates_1[1]).to equal(aggregates_2[1])
          end

          it 'fails if one of the aggregates in the identity map is not of the correct type' do
            allow(event_store)
              .to(
                receive(:load_events_for_aggregates)
                  .with([aggregate.id, aggregate_3.id])
                  .and_return([aggregate_stream_with_events, aggregate_3_stream_with_events])
                  .once,
              )

            repository.load_aggregates([aggregate.id, aggregate_3.id])
            expect do
              repository.load_aggregates([aggregate.id, aggregate_3.id], DummyAggregate)
            end.to raise_error TypeError
          end
        end
      end
    end
  end

  context 'Aggregate repository integration test' do
    class DummyCreated < Sequent::Core::Event; end
    class DummyPinged < Sequent::Core::Event; end
    class DummyCommand < Sequent::Core::BaseCommand; end
    class DummyAggregate3 < Sequent::Core::AggregateRoot
      attr_reader :pinged

      def initialize(id)
        super
        apply DummyCreated
      end

      def ping
        apply DummyPinged
      end

      on DummyCreated do
      end

      on DummyPinged do
        @pinged ||= 0
        @pinged += 1
      end
    end

    before do
      repository.clear
    end

    let(:repository) { Sequent.configuration.aggregate_repository }
    let(:aggregate) { DummyAggregate3.new(Sequent.new_uuid) }

    context '#load_aggregate_for_snapshotting' do
      it 'loads the aggregate' do
        dummy_aggregate = DummyAggregate3.new(Sequent.new_uuid)

        Sequent.aggregate_repository.add_aggregate(dummy_aggregate)
        Sequent.aggregate_repository.commit(DummyCommand.new)
        Sequent.aggregate_repository.clear

        aggregate = Sequent.aggregate_repository.load_aggregate_for_snapshotting(dummy_aggregate.id)

        expect(aggregate.pinged).to eq(dummy_aggregate.pinged)
      end

      it 'streams the aggregate up until time given' do
        dummy_aggregate = DummyAggregate3.new(Sequent.new_uuid)

        Timecop.travel(1.hour.ago)
        dummy_aggregate.ping
        Timecop.travel(1.hour)
        dummy_aggregate.ping

        Sequent.aggregate_repository.add_aggregate(dummy_aggregate)
        Sequent.aggregate_repository.commit(DummyCommand.new)
        Sequent.aggregate_repository.clear

        aggregate = Sequent.aggregate_repository.load_aggregate_for_snapshotting(
          dummy_aggregate.id,
          load_until: Time.now - 30.minutes,
        )
        expect(aggregate.pinged).to eq(1)
      end

      it 'streams all events, ignoring snapshots' do
        dummy_aggregate = DummyAggregate3.new(Sequent.new_uuid)
        Timecop.travel(1.hour.ago)
        dummy_aggregate.ping

        Sequent.aggregate_repository.add_aggregate(dummy_aggregate)
        Sequent.aggregate_repository.commit(DummyCommand.new)
        snapshot = dummy_aggregate.take_snapshot
        Sequent.configuration.event_store.store_snapshots([snapshot])

        Timecop.travel(30.minutes)
        dummy_aggregate.ping
        Sequent.aggregate_repository.commit(DummyCommand.new)
        Sequent.aggregate_repository.clear

        aggregate = Sequent.aggregate_repository.load_aggregate_for_snapshotting(
          dummy_aggregate.id,
          load_until: Time.now - 10.minutes,
        )
        expect(aggregate.pinged).to eq(1)
      end

      it 'loads the current aggregate' do
        dummy_aggregate = DummyAggregate3.new(Sequent.new_uuid)
        dummy_aggregate.ping
        Sequent.aggregate_repository.add_aggregate(dummy_aggregate)
        Sequent.aggregate_repository.commit(DummyCommand.new)
        snapshot = dummy_aggregate.take_snapshot
        Sequent.configuration.event_store.store_snapshots([snapshot])
        dummy_aggregate.ping
        Sequent.aggregate_repository.commit(DummyCommand.new)
        Sequent.aggregate_repository.clear

        aggregate = Sequent.aggregate_repository.load_aggregates([dummy_aggregate.id])
        expect(aggregate.first.pinged).to eq(2)
      end
    end

    context 'with unique keys' do
      class DummyWithUniqueKeysCreated < Sequent::Core::Event
        attrs unique_keys: Object
      end

      class DummyAggregateWithUniqueKeys < Sequent::Core::AggregateRoot
        def initialize(id, unique_keys)
          super(id)
          apply DummyWithUniqueKeysCreated, unique_keys:
        end

        def unique_keys
          @unique_keys || {}
        end

        on DummyWithUniqueKeysCreated do |event|
          @unique_keys = event.unique_keys
        end
      end

      it 'enforces key uniqueness with the same scope' do
        dummy1 = DummyAggregateWithUniqueKeys.new(Sequent.new_uuid, {email: 'test@example.com'})
        dummy2 = DummyAggregateWithUniqueKeys.new(Sequent.new_uuid, {email: 'test@example.com'})
        Sequent.aggregate_repository.add_aggregate(dummy1)
        Sequent.aggregate_repository.add_aggregate(dummy2)

        expect { Sequent.aggregate_repository.commit(DummyCommand.new) }
          .to raise_error Sequent::Core::EventStore::AggregateKeyNotUniqueError
      end
    end
  end
end
