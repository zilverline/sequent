# frozen_string_literal: true

require 'spec_helper'

RSpec.configure do |config|
  config.include Sequent::Test::CommandHandlerHelpers
  config.include Sequent::Test::WorkflowHelpers, workflows: true
end

describe 'Test Helpers' do
  after do
    # assert that sequent configuration is correctly reset after tagged group
    expect(Sequent.command_service.class).to_not eq(Sequent::Test::WorkflowHelpers::FakeCommandService)
  end

  let(:spec) { double }

  it 'fails then trying to include without WorkflowHelpers without metadata argument workflows' do
    allow(spec).to receive(:metadata).and_return({})

    expect do
      Sequent::Test::WorkflowHelpers.included(spec)
    end.to raise_error(/Missing metadata argument `workflows: true` when including Sequent::Test::WorkflowHelpers/)
  end

  context Sequent::Test::WorkflowHelpers, workflows: true do
    it 'uses the FakeCommandService in specs tagged with workflows' do
      expect(Sequent.command_service.class).to eq(Sequent::Test::WorkflowHelpers::FakeCommandService)
    end
  end

  context Sequent::Test::CommandHandlerHelpers do
    it 'does not conflict with Sequent::Test::WorkflowHelpers' do
      expect(Sequent.command_service.class).to eq(Sequent::Core::CommandService)
    end

    context 'then_events' do
      let(:actual_events) do
        [
          Sequent::Fixtures::Event1.new(aggregate_id: '1', sequence_number: 1),
          Sequent::Fixtures::Event4.new(aggregate_id: '1', sequence_number: 2, name: 'foo'),
        ]
      end
      before do
        allow(Sequent.configuration.event_store)
          .to receive(:load_events_since_marked_position)
          .and_return([actual_events])
      end

      context 'when number of events does not match' do
        it 'shows a nice error message' do
          expect { then_events([]) }.to raise_error(RSpec::Expectations::ExpectationNotMetError) { |error|
            expect(error.message)
              .to include('Actual [Sequent::Fixtures::Event1, Sequent::Fixtures::Event4] expected []')
          }
        end

        context 'when there are no events' do
          let(:actual_events) { [] }

          it 'shows a nice error message' do
            expect do
              then_events(
                Sequent::Fixtures::Event1.new(
                  aggregate_id: '1',
                  sequence_number: 1,
                ),
              )
            end.to raise_error(RSpec::Expectations::ExpectationNotMetError) { |error|
              expect(error.message)
                .to include('Number of actual events (0) is not equal to expected events (1)')
            }
          end
        end
      end

      it 'can match by type only' do
        expect { then_events(Sequent::Fixtures::Event1, Sequent::Fixtures::Event2) }
          .to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
            expect(error.message).to start_with('event 2 has incorrect type')
          end
      end

      it 'can match using a matcher' do
        expect { then_events(have_attributes(aggregate_id: '1'), have_attributes(aggregate_id: '2')) }
          .to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
            expect(error.message).to start_with('event 2 does not match')
          end
      end

      context 'when an event does not match' do
        let(:expected_events) do
          [
            Sequent::Fixtures::Event1.new(aggregate_id: '1', sequence_number: 1),
            Sequent::Fixtures::Event4.new(aggregate_id: '1', sequence_number: 2, name: 'bar'),
          ]
        end
        it 'shows a nice error message using the differ' do
          expect { then_events(expected_events) }.to raise_error(RSpec::Expectations::ExpectationNotMetError) do |error|
            expect(error.message).to start_with('event 2 does not match').and(include('Diff'))
          end
        end
      end
    end
  end
end
