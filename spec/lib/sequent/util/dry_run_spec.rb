# frozen_string_literal: true

require 'spec_helper'

describe 'dry run' do
  context 'records the commands and events' do
    let(:command_handler) do
      Class.new(Sequent::CommandHandler) do
        on Sequent::Fixtures::CreateTestAggregate do |command|
          pong = Sequent::Fixtures::TestAggregateRoot.new(command.aggregate_id)
          Sequent
            .aggregate_repository
            .add_aggregate(
              pong,
            )
          pong.ping('foo')
        end

        on Sequent::Fixtures::PingTestAggregate do |command|
          aggregate = Sequent.aggregate_repository.load_aggregate(command.aggregate_id)
          aggregate.ping(command.message)
        end
      end
    end

    let(:workflow) do
      Class.new(Sequent::Workflow) do
        on Sequent::Fixtures::TestAggregateCreated do
          fail 'should not reach this'
        end
      end
    end

    let(:projector) do
      Class.new(Sequent::Projector) do
        manages_tables AccountRecord

        on Sequent::Fixtures::TestAggregateCreated do
          fail 'should not reach this'
        end

        on Sequent::Fixtures::TestAggregatePinged do
          fail 'should not reach this'
        end
      end
    end

    let(:projector_2) do
      Class.new(Sequent::Projector) do
        manages_tables MessageRecord

        on Sequent::Fixtures::TestAggregateCreated do
          fail 'should not reach this'
        end
      end
    end

    before :each do
      allow(Sequent::Core::Workflow).to receive(:descendants).and_return([workflow])
      allow(Sequent::Core::Projector).to receive(:descendants).and_return([projector, projector_2])
      # stub for current_event_store declaration in DryRun.these_commands method
      allow(Sequent.configuration)
        .to receive(:event_store)
        .and_return(Sequent::Test::CommandHandlerHelpers::FakeEventStore.new)
      # unstub to actually use it during dry run
      allow(Sequent.configuration)
        .to receive(:event_store)
        .and_call_original

      Sequent.configure do |config|
        config.command_handlers = [
          command_handler.new,
        ]
      end
    end

    let(:create_test_aggregate) do
      Sequent::Fixtures::CreateTestAggregate.new(
        aggregate_id: Sequent.new_uuid,
      )
    end

    it 'records consequences of a specific command' do
      result = Sequent.dry_run(create_test_aggregate)

      expect(result.tree.keys).to eq [create_test_aggregate]
      expect(result.tree[create_test_aggregate]).to have(2).items
      expect(result.tree[create_test_aggregate][0].event).to be_a(Sequent::Fixtures::TestAggregateCreated)
      expect(result.tree[create_test_aggregate][0].projectors).to eq([projector, projector_2])
      expect(result.tree[create_test_aggregate][0].workflows).to eq([workflow])

      expect(result.tree[create_test_aggregate][1].event).to be_a(Sequent::Fixtures::TestAggregatePinged)
      expect(result.tree[create_test_aggregate][1].projectors).to eq([projector])
      expect(result.tree[create_test_aggregate][1].workflows).to be_empty
    end

    context 'multiple commands' do
      let(:ping_command) do
        Sequent::Fixtures::PingTestAggregate.new(
          aggregate_id: create_test_aggregate.aggregate_id,
          message: 'pong ping',
        )
      end

      it 'records consequences of all commands' do
        result = Sequent.dry_run(create_test_aggregate, ping_command)

        expect(result.tree.keys).to eq [create_test_aggregate, ping_command]
        expect(result.tree[ping_command]).to have(1).item
        expect(result.tree[ping_command][0].event).to be_a(Sequent::Fixtures::TestAggregatePinged)
        expect(result.tree[ping_command][0].event.message).to eq 'pong ping'
        expect(result.tree[ping_command][0].projectors).to eq([projector])
        expect(result.tree[ping_command][0].workflows).to be_empty
      end
    end
  end
end
