# frozen_string_literal: true

module Sequent
  module Fixtures
    Command1 = Class.new(Sequent::Core::BaseCommand) do
      attrs id: String
    end

    Command2 = Class.new(Sequent::Core::BaseCommand) do
      attrs id: String
    end

    Command3 = Class.new(Sequent::Core::BaseCommand) do
      attrs id: String
    end

    Command4 = Class.new(Sequent::Core::BaseCommand) do
      attrs id: String
      attrs id_2: String
    end

    class Event1 < Sequent::Event
    end
    class Event2 < Sequent::Event
    end
    class Event3 < Sequent::Event
    end
    Event4 = Class.new(Sequent::Event) do
      attrs name: String
    end

    AggregateClass = Class.new(Sequent::Core::AggregateRoot) do
      def initialize(id)
        super

        apply Event1
      end

      def c2
        apply Event2
      end

      def c3
        apply Event3
      end

      on(Event1) {}
      on(Event2) {}
      on(Event3) {}
    end
  end
end
