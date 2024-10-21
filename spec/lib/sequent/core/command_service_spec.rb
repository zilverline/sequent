# frozen_string_literal: true

require 'spec_helper'

class TestCommandHandler < Sequent::CommandHandler
  class DummyCommand < Sequent::Core::Command
  end

  class DummyBaseCommand < Sequent::Core::BaseCommand
    attrs mandatory_string: String
    validates_presence_of :mandatory_string
  end

  class CustomValidationCommand < Sequent::Core::BaseCommand
    attrs mandatory_string: String
    validate :mandatory_string_presence

    def mandatory_string_presence
      errors.add(:mandatory_string, I18n.t('errors.messages.blank')) if mandatory_string.blank?
    end
  end

  class NotHandledCommand < Sequent::Core::Command
  end

  class WithIntegerCommand < Sequent::Command
    attrs value: Integer
  end

  class CommandWithSecret < Sequent::Core::BaseCommand
    attrs password: Sequent::Secret
  end

  def initialize(*args)
    reset
    super
  end

  def reset
    @@called = nil
    @@password = nil
  end

  def called
    @@called
  end

  def password
    @@password
  end

  on DummyCommand do
    @@called = 'DummyCommand'
  end

  on DummyBaseCommand do
    @@called = 'DummyBaseCommand'
  end

  on WithIntegerCommand do |command|
    @@called = command
  end

  on CommandWithSecret do |command|
    @@password = command.password
  end
end

describe Sequent::Core::CommandService do
  let(:event_store) { double }

  let(:command_handler) { TestCommandHandler.new }

  let(:command_service) do
    Sequent.configuration.command_handlers = [command_handler]
    Sequent.configuration.command_service
  end

  it 'does not break when it does not handle a certain command' do
    command_service.execute_commands(TestCommandHandler::NotHandledCommand.new(aggregate_id: '1'))
    expect(command_handler.called).to be_nil
  end

  it 'calls a command handler when it does handle a certain command' do
    command_service.execute_commands(TestCommandHandler::DummyCommand.new(aggregate_id: '1'))
    expect(command_handler.called).to eq 'DummyCommand'
  end

  it 'raises a CommandNotValid for invalid commands' do
    expect { command_service.execute_commands(TestCommandHandler::DummyBaseCommand.new) }
      .to raise_error(Sequent::Core::CommandNotValid)
  end

  context 'given multiple available locales' do
    before do
      I18n.config.available_locales = %i[en nl]
      I18n.backend.store_translations(:nl, {errors: {messages: {blank: 'Verplicht veld'}}})
    end

    context 'ActiveModel validations' do
      it 'raises a CommandNotValid for invalid commands in english' do
        expect { command_service.execute_commands(TestCommandHandler::DummyBaseCommand.new) }.to raise_error(
          an_instance_of(Sequent::Core::CommandNotValid)
            .and(having_attributes(errors: {mandatory_string: ["can't be blank"]})),
        )
      end

      context 'and dutch as error locale' do
        before { Sequent.configuration.error_locale_resolver = -> { :nl } }
        after { Sequent.configuration.error_locale_resolver = -> { :en } }

        it 'raises a CommandNotValid for invalid commands in dutch' do
          expect { command_service.execute_commands(TestCommandHandler::DummyBaseCommand.new) }.to raise_error(
            an_instance_of(Sequent::Core::CommandNotValid)
              .and(having_attributes(errors: {mandatory_string: ['Verplicht veld']})),
          )
        end
      end
    end

    context 'custom validations' do
      it 'raises a CommandNotValid for invalid commands in english' do
        expect { command_service.execute_commands(TestCommandHandler::CustomValidationCommand.new) }.to raise_error(
          an_instance_of(Sequent::Core::CommandNotValid)
            .and(having_attributes(errors: {mandatory_string: ["can't be blank"]})),
        )
      end

      context 'and dutch as error locale' do
        before { Sequent.configuration.error_locale_resolver = -> { :nl } }
        after { Sequent.configuration.error_locale_resolver = -> { :en } }

        it 'raises a CommandNotValid for invalid commands in dutch' do
          expect { command_service.execute_commands(TestCommandHandler::CustomValidationCommand.new) }.to raise_error(
            an_instance_of(Sequent::Core::CommandNotValid)
              .and(having_attributes(errors: {mandatory_string: ['Verplicht veld']})),
          )
        end
      end
    end
  end

  it 'always clear repository after execute' do
    expect { command_service.execute_commands(TestCommandHandler::DummyBaseCommand.new) }
      .to raise_error(Sequent::Core::CommandNotValid)
    expect(Thread.current[Sequent::Core::AggregateRepository::AGGREGATES_KEY]).to be_nil
  end

  context 'command value parsing' do
    it 'parses secrets using bcrypt when executing' do
      command_service.execute_commands(TestCommandHandler::CommandWithSecret.new(password: 'secret'))

      expect(Sequent::Secret.verify_secret(command_handler.password.value, 'secret')).to be_truthy
      expect(command_handler.password.verify_secret('secret')).to be_truthy
    end

    it 'parses the values in the command if it is valid' do
      command_service.execute_commands(TestCommandHandler::WithIntegerCommand.new(aggregate_id: '1', value: '2'))
      expect(command_handler.called.value).to eq 2
    end

    it 'removes leading zeros if it is valid' do
      command_service.execute_commands(TestCommandHandler::WithIntegerCommand.new(aggregate_id: '1', value: '02'))
      expect(command_handler.called.value).to eq 2
    end

    it 'does not parse values if the command is invalid' do
      command = TestCommandHandler::WithIntegerCommand.new(value: 'A', aggregate_id: '1')
      expect { command_service.execute_commands(command) }.to raise_error do |e|
        expect(e.errors[:value]).to eq ['is not a number']
      end
    end

    it 'does not removes leading zeros if command is invalid' do
      command = TestCommandHandler::WithIntegerCommand.new(aggregate_id: '1', value: '0x')
      expect { command_service.execute_commands(command) }.to raise_error do |e|
        expect(e.errors[:value]).to eq ['is not a number']
      end
    end

    it 'does not removes leading zeros when using hexadecimal values' do
      command = TestCommandHandler::WithIntegerCommand.new(aggregate_id: '1', value: '0x10')
      expect { command_service.execute_commands(command) }.to raise_error do |e|
        expect(e.errors[:value]).to eq ['is not a number']
      end
    end
  end

  context 'scheduling order' do
    let(:ch) do
      Class.new(Sequent::CommandHandler) do
        on Sequent::Fixtures::Command1 do |command|
          Sequent.aggregate_repository.add_aggregate(Sequent::Fixtures::AggregateClass.new(command.id))
        end

        on Sequent::Fixtures::Command2 do |command|
          aggregate = Sequent.aggregate_repository.load_aggregate(command.id)
          aggregate.c2
        end

        on Sequent::Fixtures::Command3 do |command|
          aggregate = Sequent.aggregate_repository.load_aggregate(command.id)
          aggregate.c3
        end

        on Sequent::Fixtures::Command4 do |command|
          aggregate_1 = Sequent.aggregate_repository.load_aggregate(command.id)
          aggregate_2 = Sequent.aggregate_repository.load_aggregate(command.id_2)
          aggregate_2.c2
          aggregate_1.c2
          aggregate_1.c2
          aggregate_2.c2
        end
      end.new
    end

    let(:wf) do
      Class.new(Sequent::Workflow) do
        on Sequent::Fixtures::Event1 do |event|
          Sequent.command_service.execute_commands(Sequent::Fixtures::Command3.new(id: event.aggregate_id))
        end
      end.new
    end
    let(:aggregate1) { Sequent.new_uuid }
    let(:aggregate2) { Sequent.new_uuid }
    let(:wrapping_event_publisher) do
      Class.new(Sequent::Core::EventPublisher) do
        attr_reader :published_events

        def initialize
          super
          @published_events = []
        end

        def publish_events(events)
          super
          @published_events += events
        end

        def clear!
          @published_events = []
        end
      end.new
    end

    before do
      Sequent.configure do |config|
        config.command_handlers = [ch]
        config.event_handlers = [wf]
        config.event_publisher = wrapping_event_publisher
      end
      Sequent.logger.level = Logger::DEBUG
    end

    let(:published_events) do
      wrapping_event_publisher.published_events.map { |e| [e.aggregate_id, e.class] }
    end

    after do
      wrapping_event_publisher.clear!
      Sequent::Configuration.reset
    end

    context 'with workflow' do
      it 'publishes events' do
        Sequent.command_service.execute_commands(
          Sequent::Fixtures::Command1.new(id: aggregate1),
        )
        expect(published_events).to eq(
          [
            [aggregate1, Sequent::Fixtures::Event1],
            [aggregate1, Sequent::Fixtures::Event3],
          ],
        )
      end

      it 'with multiple commands publishes events based on command queueing order' do
        Sequent.command_service.execute_commands(
          Sequent::Fixtures::Command1.new(id: aggregate1),
          Sequent::Fixtures::Command2.new(id: aggregate1),
        )
        expect(published_events).to eq(
          [
            [aggregate1, Sequent::Fixtures::Event1],
            [aggregate1, Sequent::Fixtures::Event2],
            [aggregate1, Sequent::Fixtures::Event3],
          ],
        )
      end
      context 'multiple aggregates' do
        it 'with multiple commands publishes events based on command queueing order' do
          Sequent.command_service.execute_commands(
            Sequent::Fixtures::Command1.new(id: aggregate1),
            Sequent::Fixtures::Command1.new(id: aggregate2),
            Sequent::Fixtures::Command2.new(id: aggregate1),
          )
          expect(published_events).to eq(
            [
              [aggregate1, Sequent::Fixtures::Event1],
              [aggregate2, Sequent::Fixtures::Event1],
              [aggregate1, Sequent::Fixtures::Event2],
              [aggregate1, Sequent::Fixtures::Event3],
              [aggregate2, Sequent::Fixtures::Event3],
            ],
          )
        end

        it 'touching multiple aggregates in same command publishes events per aggregate on aggregate load order' do
          Sequent.configuration.event_handlers = [] # remove workflow, not needed to this test
          Sequent.command_service.execute_commands(
            Sequent::Fixtures::Command1.new(id: aggregate1),
            Sequent::Fixtures::Command1.new(id: aggregate2),
            Sequent::Fixtures::Command4.new(id: aggregate1, id_2: aggregate2),
          )

          expect(published_events).to eq(
            [
              [aggregate1, Sequent::Fixtures::Event1],
              [aggregate2, Sequent::Fixtures::Event1],
              [aggregate1, Sequent::Fixtures::Event2],
              [aggregate1, Sequent::Fixtures::Event2],
              [aggregate2, Sequent::Fixtures::Event2],
              [aggregate2, Sequent::Fixtures::Event2],
            ],
          )
        end
      end
    end
  end

  context 'commands triggered by workflows' do
    let(:handler_1) do
      Class.new(Sequent::CommandHandler) do
        attr_reader :ping_command

        attr_reader :create_command

        on Sequent::Fixtures::CreateTestAggregate do |command|
          @create_command = command
          aggregate = Sequent::Fixtures::TestAggregateRoot.new(command.aggregate_id)
          Sequent.aggregate_repository.add_aggregate(aggregate)
        end

        on Sequent::Fixtures::PingTestAggregate do |command|
          @ping_command = command
        end
      end.new
    end

    let(:handler_2) do
      Class.new(Sequent::CommandHandler) do
        attr_reader :notify_command

        on Sequent::Fixtures::NotifyTestAggregateCreated do |command|
          @notify_command = command
        end
      end.new
    end

    let(:workflow) do
      Class.new(Sequent::Workflow) do
        on Sequent::Fixtures::TestAggregateCreated do |event|
          Sequent.command_service.execute_commands Sequent::Fixtures::NotifyTestAggregateCreated.new(
            aggregate_id: Sequent.new_uuid,
            test_aggregate_id: event.aggregate_id,
          )
        end
      end
    end

    before :each do
      Sequent.configure do |config|
        config.command_handlers = [
          handler_1,
          handler_2,
        ]
        config.event_handlers = [
          workflow.new,
        ]
      end
    end

    it 'only registers the current event when executed' do
      aggregate_id = Sequent.new_uuid
      Sequent.command_service.execute_commands(
        Sequent::Fixtures::CreateTestAggregate.new(
          aggregate_id: aggregate_id,
        ),
        Sequent::Fixtures::PingTestAggregate.new(
          aggregate_id: aggregate_id,
          message: 'ping',
        ),
      )

      # these commands should not be enriched with the event_aggregate_id
      # since they are not called via the workflow
      expect(handler_1.create_command.aggregate_id).to eq aggregate_id
      expect(handler_1.create_command.event_aggregate_id).to be_nil
      expect(handler_1.create_command.event_sequence_number).to be_nil

      expect(handler_1.ping_command.aggregate_id).to eq aggregate_id
      expect(handler_1.ping_command.message).to eq 'ping'
      expect(handler_1.ping_command.event_aggregate_id).to be_nil
      expect(handler_1.ping_command.event_sequence_number).to be_nil

      # this handler is executed via the workflow so they should have
      # the aggregate_id and sequence number of the event that
      # triggered the command
      expect(handler_2.notify_command.aggregate_id).to_not eq aggregate_id
      expect(handler_2.notify_command.test_aggregate_id).to eq aggregate_id
      expect(handler_2.notify_command.event_aggregate_id).to eq aggregate_id
      expect(handler_2.notify_command.event_sequence_number).to eq 1

      Sequent.command_service.execute_commands(
        Sequent::Fixtures::PingTestAggregate.new(
          aggregate_id: aggregate_id,
          message: 'pong',
        ),
      )

      # executing a commands afterward should not have the event_aggregate_id
      # this ensure no state is left behind
      expect(handler_1.ping_command.aggregate_id).to eq aggregate_id
      expect(handler_1.ping_command.message).to eq 'pong'
      expect(handler_1.ping_command.event_aggregate_id).to be_nil
      expect(handler_1.ping_command.event_sequence_number).to be_nil
    end

    context 'super nested workflows' do
      let(:handler_2) do
        Class.new(Sequent::CommandHandler) do
          attr_reader :notify_command

          attr_reader :ping_received_command

          on Sequent::Fixtures::NotifyTestAggregateCreated do |command|
            @notify_command = command
            aggregate = Sequent.aggregate_repository.load_aggregate(command.test_aggregate_id)
            aggregate.ping('notify created!')
          end

          on Sequent::Fixtures::NotifyTestAggregatePingReceived do |command|
            @ping_received_command = command
          end
        end.new
      end

      let(:workflow) do
        Class.new(Sequent::Workflow) do
          on Sequent::Fixtures::TestAggregateCreated do |event|
            Sequent.command_service.execute_commands Sequent::Fixtures::NotifyTestAggregateCreated.new(
              aggregate_id: Sequent.new_uuid,
              test_aggregate_id: event.aggregate_id,
            )
          end

          on Sequent::Fixtures::TestAggregatePinged do |event|
            Sequent.command_service.execute_commands Sequent::Fixtures::NotifyTestAggregatePingReceived.new(
              aggregate_id: Sequent.new_uuid,
              test_aggregate_id: event.aggregate_id,
            )
          end
        end
      end

      it 'registers the correct event_aggregate_ids for super nested workflows' do
        aggregate_id = Sequent.new_uuid
        Sequent.command_service.execute_commands(
          Sequent::Fixtures::CreateTestAggregate.new(
            aggregate_id: aggregate_id,
          ),
        )

        expect(handler_2.notify_command.aggregate_id).to_not eq aggregate_id
        expect(handler_2.notify_command.test_aggregate_id).to eq aggregate_id
        expect(handler_2.notify_command.event_aggregate_id).to eq aggregate_id
        expect(handler_2.notify_command.event_sequence_number).to eq 1

        expect(handler_2.ping_received_command.aggregate_id).to_not eq aggregate_id
        expect(handler_2.ping_received_command.test_aggregate_id).to eq aggregate_id
        expect(handler_2.ping_received_command.event_aggregate_id).to eq aggregate_id
        expect(handler_2.ping_received_command.event_sequence_number).to eq 2
      end
    end
  end

  describe 'command middleware' do
    before do
      Sequent.configure do |config|
        config.command_middleware.add(middleware)
      end
    end

    after do
      Sequent.configure do |config|
        config.command_middleware.clear
      end
    end

    let(:middleware) { double('middleware') }
    let(:some_command) { TestCommandHandler::DummyCommand.new(aggregate_id: 'some-id') }
    let(:another_command) { TestCommandHandler::DummyCommand.new(aggregate_id: 'another-id') }

    it 'invokes command middleware for each command to execute' do
      expect(middleware).to receive(:call).ordered.with(some_command)
      expect(middleware).to receive(:call).ordered.with(another_command)

      command_service.execute_commands(some_command, another_command)
    end
  end
end
